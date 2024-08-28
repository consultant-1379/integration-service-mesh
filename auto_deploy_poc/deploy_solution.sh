#!/bin/bash 

readonly NS="5g-integration"
readonly YANG_PASS="EricSson@12-34"
readonly CRD_NS="eric-crd-ns"

function printMessage() {
  local message="$1"
  echo "******************************************"
  echo "${message}"
  echo "******************************************"
}

function cleanup() {
  printMessage "Sleeping 5 seconds for additional checks.."
  sleep 5
  printMessage "Removing previous installation"
  local releases
  releases=$(helm list --all --namespace "${NS}" | grep -v NAME | awk '{print $1}')
  if [ -n "${releases}" ]; then
    echo "Removing ${releases}"
    helm uninstall ${releases} --namespace "${NS}" --no-hooks
  fi
  kubectl delete deployment --all -n "${NS}"
  kubectl delete sts --all -n "${NS}"
  kubectl delete pod --all -n "${NS}"
  kubectl delete cm --all -n "${NS}"
  kubectl delete pvc --all -n "${NS}"
  kubectl delete job --all -n "${NS}"

  local secrets
  secrets=$(kubectl get secret -n "${NS}" | grep "^eric-sec\|^eric-data-distributed\|^eric-adp\|^eric-cm\|^eric-data-document\|snmp-alarm-provider" | awk '{print $1}')
  if [ -n "${secrets}" ]; then
    kubectl delete secret -n "${NS}" ${secrets}
  fi

  kubectl delete secret -l "com.ericsson.sec.tls/created-by=eric-sec-sip-tls" -n "${NS}"
  #kubectl delete ns ${NS}
  kubectl delete leases -n "${NS}" eric-tm-ingress-controller-cr-leader
  kubectl delete clusterrole `kubectl get clusterrole |grep -v system|grep 'mesh\|eric-adp-5g-udm\|5g-integration'|awk '{print $1}'`
  kubectl delete clusterrolebinding `kubectl get clusterrolebinding |grep -v system|grep 'mesh\|eric-adp-5g-udm\|5g-integration'|awk '{print $1}'`
  kubectl delete MutatingWebhookConfiguration eric-ccsm-datainjector-5g-integration
  kubectl delete ValidatingWebhookConfiguration istio-validator-5g-integration
}

function install() {
  printMessage "INSTALLATION"

  kubectl get ns | grep -q "${NS}" || kubectl create ns "${NS}"
  kubectl get ns | grep -q "${CRD_NS}" || kubectl create ns "${CRD_NS}"

  armdocker_secret_exists=$(kubectl get secrets -n "${NS}" armdocker 2> /dev/null)
  if [ -z "${armdocker_secret_exists}" ]; then
    kubectl create -n "${NS}" -f -<<EOF
apiVersion: v1
data:
  .dockerconfigjson: eyJhdXRocyI6eyJhcm1kb2NrZXIucm5kLmVyaWNzc29uLnNlIjp7InVzZXJuYW1lIjoiZXNkY2NjaSIsInBhc3N3b3JkIjoiUGNkbGNjaTEiLCJhdXRoIjoiWlhOa1kyTmphVHBRWTJSc1kyTnBNUT09In19fQ==
kind: Secret
metadata:
  name: armdocker
type: kubernetes.io/dockerconfigjson
EOF
  fi

  selndocker_secret_exists=$(kubectl get secrets -n "${NS}" selndocker 2> /dev/null)
  if [ -z "${selndocker_secret_exists}" ]; then
    kubectl create -n "${NS}" -f -<<EOF
apiVersion: v1
data:
  .dockerconfigjson: eyJhdXRocyI6eyJzZWxuZG9ja2VyLm1vLnN3LmVyaWNzc29uLnNlIjp7InVzZXJuYW1lIjoiZXNkY2NjaSIsInBhc3N3b3JkIjoiUGNkbGNjaTEiLCJhdXRoIjoiWlhOa1kyTmphVHBRWTJSc1kyTnBNUT09In19fQ==
kind: Secret
metadata:
  name: selndocker
type: kubernetes.io/dockerconfigjson
EOF
  fi

  snmp_alarm_provider_config_secret_exists=$(kubectl get secrets -n "${NS}" snmp-alarm-provider-config 2> /dev/null)
  if [ -z "${snmp_alarm_provider_config_secret_exists}" ]; then
    cat > config.json <<EOF
{}
EOF
    kubectl create secret generic snmp-alarm-provider-config --from-file=./config.json -n "${NS}"
  fi

  eric_sec_access_mgmt_creds_secret_exists=$(kubectl get secrets -n "${NS}" eric-sec-access-mgmt-creds 2> /dev/null)
  if [ -z "${eric_sec_access_mgmt_creds_secret_exists}" ]; then
    kubectl create secret generic eric-sec-access-mgmt-creds -n "${NS}" --from-literal=pguserid=pguser --from-literal=pgpasswd=pgpw --from-literal=kcadminid=admin --from-literal=kcpasswd=Ericsson@12-kcpw --dry-run=client -o yaml | kubectl apply -f -
  fi

  eric_data_distributed_coordinator_creds_secret_exists=$(kubectl get secrets -n "${NS}" eric-data-distributed-coordinator-creds 2> /dev/null)
  if [ -z "${eric_data_distributed_coordinator_creds_secret_exists}" ]; then
   kubectl create secret generic eric-data-distributed-coordinator-creds -n "${NS}" --from-literal=etcdpasswd=$(echo -n "admin" | base64)
  fi

  eric_sec_ldap_server_creds_secret_exists=$(kubectl get secrets -n "${NS}" eric-sec-ldap-server-creds 2> /dev/null)
  if [ -z "${eric_sec_ldap_server_creds_secret_exists}" ]; then
    ldap_pass=$(python3 -c 'import crypt;print (crypt.crypt("ericsson","$6$Afe145T7$"))')
    kubectl create secret generic eric-sec-ldap-server-creds -n "${NS}" --from-literal=adminuser=sysadmin --from-literal=adminpasswd=${ldap_pass} --from-literal=passwd=keycloak --dry-run=client -o yaml | kubectl apply -f -
  fi

  #eric_data_object_storage_mn_creds_exists=$(kubectl get secrets -n "${NS}" eric-data-object-storage-mn-creds 2> /dev/null)
  #if [ -z "${eric_data_object_storage_mn_creds_exists}" ]; then
  #  kubectl create secret generic eric-data-object-storage-mn-creds --from-literal=accesskey=AKIAIOSFODNN7EXAMPLE --from-literal=secretkey=wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY -n "${NS}"
  #fi
  
  #touch user-configuration.json
  eric_sec_admin_user_mngmt_secret_exists=$(kubectl get secrets -n "${NS}" eric-sec-admin-user-mngmt 2> /dev/null)
  if [ -z "${eric_sec_admin_user_mngmt_secret_exists}" ]; then
    MACHINE_PWD=$(python3 -c 'import crypt;print(crypt.crypt("123456789", crypt.mksalt(crypt.METHOD_SHA512)))')
    cat > user-configuration.json <<EOF
{
      "user": [
        {
          "name": "machine-user-1",
          "password": "'$MACHINE_PWD/'",
          "groups": [
            "nrf-admin",
            "nrf-security-admin",
            "nssf-admin",
            "nssf-security-admin",
            "nrfagent-admin",
            "nrfagent-security-admin",
            "sragent-admin"
          ]
        }
      ]
    }
EOF
        kubectl create secret generic eric-sec-admin-user-mngmt --from-file=./user-configuration.json -n "${NS}"
      fi

  touch dummy
  eric_ccsm_sbi_server_certs_cacert=$(kubectl get secrets -n "${NS}" eric-ccsm-sbi-server-certs-cacert 2> /dev/null)
  if [ -z "${eric_ccsm_sbi_server_certs_cacert}" ]; then
    kubectl create -n "${NS}" secret generic eric-ccsm-sbi-server-certs-cacert --from-file=cacert=dummy
  fi
  eric_ccsm_sbi_client_certs=$(kubectl get secrets -n "${NS}" eric-ccsm-sbi-client-certs 2> /dev/null)
  if [ -z "${eric_ccsm_sbi_client_certs}" ]; then
    kubectl create -n "${NS}" secret generic eric-ccsm-sbi-client-certs --from-file=tls.crt=dummy
  fi
  eric_ccsm_sbi_client_certs_cacert=$(kubectl get secrets -n "${NS}" eric-ccsm-sbi-client-certs-cacert 2> /dev/null)
  if [ -z "${eric_ccsm_sbi_client_certs_cacert}" ]; then
    kubectl create -n "${NS}" secret generic eric-ccsm-sbi-client-certs-cacert --from-file=ca-chain.cert.pem=dummy
  fi

  printMessage "Deploying common components"
  helm env

  REPO_ALIAS="adp-to-test"
  helm repo add --username "${ARM_USER}" --password "${ARM_PASS}" "${REPO_ALIAS}" "${CHART_REPO}"
  helm repo update

  printMessage "Deploying CRD chart"
  for line in $(grep -v ^# ./versions_list | grep "^crd"); do
    crdName=$(echo "${line}" |awk -F [/] '{print $NF}'| sed 's/.*\(eric-.*-crd\).*/\1/')
    crdNameWithVersion=$(echo "${line}" |awk -F [/] '{print $NF}'| awk -F '.tgz' '{print $1}'| sort -d)
    helmListChart=$(helm ls -A | grep "${crdName}" | awk '{print $9}')
    if [[ ${helmListChart} != ${crdNameWithVersion} ]]; then
      link=$(echo "${line}" | cut -d= -f2)
      linkWithCredentials=$(echo "${link}" | sed 's/https:\/\//&'"${ARM_USER}"':'"${ARM_PASS}"'@/')

      printMessage "Deploying CRD chart  ${crdName}"
      if [ $crdName = "eric-tm-ingress-controller-cr-crd" ]; then
        helm upgrade --install  "${crdName}" "${linkWithCredentials}" --namespace "${CRD_NS}" --atomic --set rbac.create=true
      else
        helm upgrade --install  "${crdName}" "${linkWithCredentials}" --namespace "${CRD_NS}" --atomic
      fi
      if [ $? -ne 0 ]; then
        echo "Failed to deploy ${crdName}"
        exit 1
      fi
    else
      printMessage "CRD correct version already installed, skip it"
    fi
  done
  echo "Wait 10s for CRDs to be ready"
  sleep 5

  printMessage "Deploying mesh"
  if [ "${CHART_NAME}" = "eric-udm-mesh-integration" ]; then
    helm pull "${CHART_REPO}""${CHART_NAME}"/"${CHART_NAME}""-""${CHART_VERSION}"".tgz" --username "${ARM_USER}" --password "${ARM_PASS}"
  else
    sm=$(grep -v ^# ./versions_list | grep "^sm=" | cut -d= -f2)
    helm pull "$sm" --username "${ARM_USER}" --password "${ARM_PASS}"
  fi
  if [ $? -ne 0 ]; then
    echo "Failed to download service-mesh chart"
    exit 1
  fi

  sm_tar=$(find ./ -name "eric-udm-mesh-integration-*.tgz" | rev | cut -d/ -f1 | rev)
  helm install eric-udm-mesh-integration ${sm_tar} -f ./values/adp-sm_values.yaml --namespace "${NS}" --timeout 600s
  if [ $? -ne 0 ]; then
    echo "Failed to deploy sevice-mesh chart."
    exit 1
  fi

  printMessage "First SM deployed, deploying 2nd SM.."

  sm_tar2=$(find ./ -name "eric-udm-mesh-integration2*.tgz" | rev | cut -d/ -f1 | rev)
  helm install eric-udm-mesh-integration2 ${sm_tar2} -f ./values/adp-sm_values2.yaml --namespace "${NS}" --timeout 600s
  if [ $? -ne 0 ]; then
    echo "Failed to deploy sevice-mesh chart."
    exit 1
  fi

  kubectl label ns "${NS}" istio-injection-
  
  echo "******************************************"
  echo "******************************************"
  sleep 10
  printMessage "Deploying adp"
  if [ "${CHART_NAME}" = "eric-adp-5g-udm" ]; then
    helm pull "${CHART_REPO}""${CHART_NAME}"/"${CHART_NAME}""-""${CHART_VERSION}"".tgz" --username "${ARM_USER}" --password "${ARM_PASS}"
  else
    adp=$(grep -v ^# ./versions_list | grep "^adp=" | cut -d= -f2)
    helm pull "$adp" --username "${ARM_USER}" --password "${ARM_PASS}"
  fi
  if [ $? -ne 0 ]; then
    echo "Failed to download adp."
    exit 1
  fi

  adp_tar=$(find ./ -name "eric-adp-5g-udm*.tgz" | rev | cut -d/ -f1 | rev)
  declare -a listOfAdpFiles=("adp_values.yaml" "adp_values2.yaml" "adp_values3.yaml")
  for file in "${listOfAdpFiles[@]}"; do
    if [ ${file} == "adp_values.yaml" ]; then
      helm install eric-adp-5g-udm ${adp_tar} -f ./values/${file} --namespace "${NS}" --timeout 600s
    elif [ ${file} == "adp_values2.yaml" ]; then
      helm install eric-adp-5g-udm-ccsm-license ${adp_tar} -f ./values/${file} --namespace "${NS}" --timeout 600s
    else
      helm install eric-adp-5g-udm-ccdm-license ${adp_tar} -f ./values/${file} --namespace "${NS}" --timeout 600s
    fi
    if [ $? -ne 0 ]; then
      echo "Failed to deploy adp."
      exit 1
    fi
    echo "******************************************"
    echo "******************************************"
  done

  kubectl -n "${NS}" patch svc eric-cm-mediator -p "{\"spec\":{\"type\":\"NodePort\"}}"
  kubectl -n "${NS}" patch svc eric-sec-access-mgmt-http -p '{"spec":{"type":"NodePort"}}'

  #<---WA for image path in new SNMP_AP (12.0.0 onwards)--->
  chart_version=$(kubectl describe deploy -n 5g-integration eric-fh-snmp-alarm-provider | grep 'chart=.*' | cut -d'-' -f6)
  first_number=$(echo "${chart_version}" | cut -d'.' -f1)

  if [ "${first_number}" -ge 12 ]; then
    echo "Patching SNMP deployment.."
    OLD_IMAGE_PATH_SNMP=$(kubectl get deployment eric-fh-snmp-alarm-provider -n 5g-integration -o=jsonpath='{.spec.template.spec.containers[0].image}')
    NEW_IMAGE_PATH_SNMP=$(echo ${OLD_IMAGE_PATH_SNMP} | sed 's|selndocker.mo.sw.ericsson.se|armdocker.rnd.ericsson.se|g')
    kubectl -n "${NS}" patch deployment eric-fh-snmp-alarm-provider -n 5g-integration --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"'${NEW_IMAGE_PATH_SNMP}'"}]'
  fi

  #<---WA for inverted ports in new SM version (12.1.0-42 onwards)--->
  # Fetch the ingress information
  ingress_info=$(kubectl get svc -n 5g-integration | grep eric-ingressgw-nrf-traffic)
  # Extract the port section from the ingress information
  ports=$(echo $ingress_info | awk '{print $5}')
  # Store the ports in separate variables
  port1=$(echo $ports | cut -d',' -f1 | cut -d':' -f2 | cut -d'/' -f1)
  port2=$(echo $ports | cut -d',' -f2 | cut -d':' -f2 | cut -d'/' -f1)
  port3=$(echo $ports | cut -d',' -f3 | cut -d':' -f2 | cut -d'/' -f1)

  kubectl patch svc -n "${NS}" eric-ingressgw-nrf-traffic -p "{
  \"spec\": {
    \"ports\": [
      {\"name\": \"http2\", \"nodePort\": $port3, \"port\": 80, \"protocol\": \"TCP\", \"targetPort\": 8080},
      {\"name\": \"geode-locators\", \"nodePort\": $port2, \"port\": 91, \"protocol\": \"TCP\", \"targetPort\": 8091},
      {\"name\": \"geode-gw-rcvs\", \"nodePort\": $port1, \"port\": 92, \"protocol\": \"TCP\", \"targetPort\": 8092}
    ]
  }
}"

  for line in $(grep -v ^# ./versions_list | grep -v "^sm\|^adp\|^crd\|^ausf\|^udm\|^nrf\|^nssf\|^nrf-agent\|^udr"); do
    nf=$(echo "${line}" | cut -d= -f1)
    nf_chart=$(echo "${line}" | cut -d= -f2 | awk -F [/] '{print $NF}')
    link=$(echo "${line}" | cut -d= -f2)
    linkWithCredentials=$(echo "${link}" | sed 's/https:\/\//&'"${ARM_USER}"':'"${ARM_PASS}"'@/')

    printMessage "Deploying ${nf}"
    if [ ${nf} = "ccrc" ]; then
      helm pull ${link} --username "${ARM_USER}" --password "${ARM_PASS}" --untar 
      sed -i -e '1N;$!N;s/\(.*proj-5g-udm-release-helm.*tags:\)/\1\n  - adp/;P;D' eric-ccrc/requirements.yaml
      sed -i -e '1N;$!N;s/\(.*proj-ccrc-helm-local.*tags:\)/\1\n   - common/;P;D' eric-ccrc/requirements.yaml
      sed -i -e '1N;$!N;s/\(.*proj-adp-gs-all-helm.*tags:\)/\1\n   - kvdb/;P;D'  eric-ccrc/requirements.yaml
      rm -rf ${nf_chart}
      tar czf ${nf_chart} eric-ccrc
      helm install eric-"${nf}" "${nf_chart}" --namespace "${NS}" -f ./values/"${nf}"_values.yaml --set tags.adp=false --set tags.common=false --set tags.kvdb=false --timeout 600s --disable-openapi-validation
      if [ $? -ne 0 ]; then
        echo "Failed to deploy ${nf}"
        exit 1
      fi
      echo "******************************************"
      echo "******************************************"
    elif [ ${nf} = "ccdm" ]; then
      helm pull ${link} --username "${ARM_USER}" --password "${ARM_PASS}" --untar
      sed -i -e '/.*condition: global.nrfagent.enabled/d' eric-ccdm/requirements.yaml
      rm -rf ${nf_chart}
      tar czf ${nf_chart} eric-ccdm
      helm install eric-"${nf}" "${nf_chart}" --namespace "${NS}" -f ./values/"${nf}"_values.yaml --timeout 2400s --disable-openapi-validation
      if [ $? -ne 0 ]; then
        echo "Failed to deploy ${nf}"
        exit 1
      fi
      echo "******************************************"
      echo "******************************************"
    else
    helm install eric-"${nf}" "${linkWithCredentials}" --namespace "${NS}" -f ./values/"${nf}"_values.yaml --timeout 2400s --disable-openapi-validation
    # for eda don't check depploy exit code because sometimes it will condition timeout
    if [ $? -ne 0 ]; then
      if [ ${nf} != "eda" ]; then
       echo "Failed to deploy ${nf}"
       exit 1
      fi
    fi
    if [ ${nf} = "eda" ]; then
      createEdaResources
    fi
    echo "******************************************"
    echo "******************************************"
    fi 
  done

  #WA D72 CCSM directly connection to nrf-register and nrf-discovery
  kubectl -n "${NS}" patch sts eric-ausf-engine --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value":{"name":"NRF_DISCOVER_AGENT","value":"http://eric-nrf-discovery-agent:3202"}},
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value":{"name":"NRF_REGISTER_AGENT","value":"http://eric-nrf-register-agent:3002"}}]'
  kubectl get deploy -n "${NS}" eric-ccsm-nrfgw -o yaml | \
  sed '/nrfregister/{n;s/\(.*- \).*/\1http:\/\/eric-nrf-register-agent:3002/}' | \
  sed '/nrfdiscovery/{n;s/\(.*- \).*/\1http:\/\/eric-nrf-discovery-agent:3202/}' | \
  kubectl apply -f -

  #scaling minReplica to 1 for hpa in udm, nssf, ingressgw, mesh-controller
  scaleMinHpa
  sleep 5
  #scaling maxReplica and deploy replicas for udm pods to 1
  scaleInUdm
  sleep 40
}

function scaleInUdm() {
  echo
  echo "Scaling hpa in udm"
  echo
  for HPA in $(kubectl get hpa -n "${NS}" --no-headers | grep eric-udm | awk '{print $1}'); do
    kubectl -n "${NS}" patch hpa $HPA -p '{"spec": {"maxReplicas":1}}';
  done
  sleep 5
  echo
  echo "Scaling deploy in udm"
  echo
  for dep in $(kubectl get deployment -n "${NS}" | grep eric-udm | grep -v udm-sidf | awk '{print $1}'); do
    kubectl scale deployment ${dep} --replicas=1 -n "${NS}";
  done 
}

function scaleMinHpa() {
  echo
  echo "Scaling other pods"
  echo
  for HPA in $(kubectl get hpa -n "${NS}" --no-headers | grep -v eric-udr | grep -v eric-nrf | grep -v eric-ausf | awk '{print $1}'); do
    kubectl -n "${NS}" patch hpa $HPA -p '{"spec": {"minReplicas":1}}';
  done
}

function createEdaResources() {
  kubectl apply -f eric-act-ccdm-prov-ingress.yaml -n "${NS}"
  kubectl apply -f eric-eda-provisioning-gw.yaml -n "${NS}"
}

function configure() {

  KCUSERNAME="sysadmin"
  KCPASSWORD="ericsson"

  printMessage "CONFIGURATION"
  printMessage "Collect environment info..."
  export ISTIO_SVC=$(kubectl get svc -n "${NS}" | grep ingressgw)
  export NODE_IP=$(kubectl describe node $(echo $(kubectl get node | awk '$3~/node/' | awk 'NR==1{print $1}')) | grep InternalIP -m1 | awk '{print $2}')
  export NRF_INT_IP=$(echo "${ISTIO_SVC}" | grep "eric-ingressgw-nrf-traffic" | awk '{print $3}')
  export AGENT_INT_IP=$(echo "${ISTIO_SVC}" | grep "eric-ingressgw-nrf-agent-traffic" | awk '{print $3}')
  export NRF_INT_PORT=$(echo "${ISTIO_SVC}" | grep "eric-ingressgw-nrf-traffic" | awk '{print $5}' | cut -d: -f1)
  export AGENT_INT_PORT=$(echo "${ISTIO_SVC}" | grep "eric-ingressgw-nrf-agent-traffic" | awk '{print $5}' | cut -d: -f1)
  export AUSF_PORT=$(echo "${ISTIO_SVC}" | grep eric-ingressgw-ausf-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  export UDM_PORT=$(echo "${ISTIO_SVC}" | grep eric-ingressgw-udm-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  export UDR_PORT=$(echo "${ISTIO_SVC}" | grep eric-ingressgw-udr-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  export NSSF_PORT=$(echo "${ISTIO_SVC}" | grep eric-ingressgw-nssf-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  export NEF_PORT=$(echo "${ISTIO_SVC}" | grep eric-ingressgw-nef-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  export PCF_PORT=$(echo "${ISTIO_SVC}" | grep eric-ingressgw-pcf-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  export NRF_PORT=$(echo "${ISTIO_SVC}" | grep eric-ingressgw-nrf-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1 | head -1)
  export AGENT_PORT=$(echo "${ISTIO_SVC}" | grep eric-ingressgw-nrf-agent-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  export CM_PORT=$(kubectl -n "${NS}" get svc | grep cm-mediator | awk '{print $5}' | head -1 | cut -d: -f2 | cut -d/ -f1)
  get_yang_svc=$(kubectl -n "${NS}" get svc | grep "eric-cm-yang-provider-external" | wc -c)

  get_frontend_pods=$(kubectl get pod -n kube-system | grep front |wc -l)
  if [ "${get_frontend_pods}" -gt 0 ]; then
    #this means that is CAPO cluster, and NODE_IP address is eth1 address, not master IP
    export NODE_IP=$(kubectl exec -n kube-system ds/eric-tm-external-connectivity-frontend-speaker -it --  birdcl show interfaces summary | grep eth1 | awk '{print $3}' | cut -d/ -f1)
  else
    #this means that is ANSIBLE cluster, and NODE_IP address is master address
    export NODE_IP=$(kubectl describe node $(echo $(kubectl get node | awk '$3~/node/' | awk 'NR==1{print $1}')) | grep InternalIP -m1 | awk '{print $2}')
  fi
  
  if [ "${get_yang_svc}" -gt 0 ]; then
    export YANG_PORT=$(kubectl -n "${NS}" get svc | grep "eric-cm-yang-provider-external" | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  else
    export YANG_PORT=$(kubectl -n "${NS}" get svc | grep "eric-cm-yang-provider " | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
  fi

  printMessage "Modify configuration templates..."
  NFs=$(grep -v ^# ./versions_list | grep -v "^sm\|^adp\|^crd\|^ccsm\|^kvdb\|^ccrc\|^ccdm" | cut -d= -f1)
  # Change the udr.xml uploading order, because sometimes it will cause cm_yang pod restart.
  Sort_NFs=$(echo "${NFs}" | sed '/udr/d'|sed '/ausf/a\udr')

  for nf in ${Sort_NFs};do
    if [ -f configurations/${nf}.*template ]; then
      echo "Prepare file for ${nf}"
    else
      echo "NF ${nf} doesn't have configuration template"
      continue
    fi

    input=$(ls configurations/"${nf}".*template)
    output="${input%".template"}"
    eval "cat <<EOF
$(<"${input}")
EOF" > "${output}"

    cat "${output}"
  done

  SSH_ASKPASS_SCRIPT=/tmp/ssh-askpass-script
  cat > "${SSH_ASKPASS_SCRIPT}" <<EOL
#!/bin/bash
echo "${KCPASSWORD}"
EOL
  chmod u+x "${SSH_ASKPASS_SCRIPT}"
  export DISPLAY=:0
  export SSH_ASKPASS="${SSH_ASKPASS_SCRIPT}"

  printMessage "Create admin user"
  attempt_yp=0
  MAX_YP_ATTEMPTS=5
  while [ "${attempt_yp}" -le "${MAX_YP_ATTEMPTS}" ]; do
    sleep 60
    kubectl get pod -n "${NS}" | grep cm-yang
    YANG_OUTPUT=$(setsid ssh -o "ConnectTimeout=5" -o "StrictHostKeyChecking no" sysadmin@"${NODE_IP}" -p"${YANG_PORT}"  -s netconf < ./configurations/adduser.xml)
    RESULT_CODE=$?
    if [ "${RESULT_CODE}" -ne 0 ]; then
      echo "ERROR: Problem with connecting to YANG provider!"
      echo "WA: Restart CMYP because of problem in UDR yang models"
      kubectl delete -n "${NS}" pod $(kubectl get pod -n "${NS}" |grep eric-cm-yang-provider|awk '{print $1}')
      sleep 120
    else
      echo "Create the user admin successfully"
      break
    fi
    attempt_yp=$(( ${attempt_yp} + 1 ))
  done
  if [ "${attempt_yp}" -gt "${MAX_YP_ATTEMPTS}" ]; then
    echo "FAILURE: Create user admin unsuccessfully"
    exit 1;
  fi

  printMessage "Changing admin user password for the first time login"
  sleep 60
  export DISPLAY=:0
  export SSH_ASKPASS=/tmp/ssh-askpass-script
  setsid ./autoChangePwd.sh "${NODE_IP}" "${YANG_PORT}"

  printMessage "Put configuration to CM"
  cat > "${SSH_ASKPASS_SCRIPT}" <<EOL
#!/bin/bash
echo "${YANG_PASS}"
EOL

  printMessage "Create iccr tls certification"
  setsid ssh -o "ConnectTimeout=5" -o "StrictHostKeyChecking no" admin@"${NODE_IP}" -p"${YANG_PORT}"  -s netconf < ./configurations/ccrc_iccr.xml

  for nf in ${Sort_NFs}; do
    if [ -f configurations/${nf}.*template ]; then
      echo "Configuration loading for ${nf}"
    else
      echo "NF ${nf} doesn't have configuration to load"
      continue
    fi
    attempt_cm=0
    MAX_CM_ATEMPTS=30
    while [ "${attempt_cm}" -le "${MAX_CM_ATEMPTS}" ]; do

      if [ "${nf}" == 'udm' ]; then
        sleep 30
      fi

      SCHEMA=$(curl -s http://"${NODE_IP}":"${CM_PORT}"/cm/api/v1.0/schemas/ericsson-"${nf}" | wc -c)
      if [ "${SCHEMA}" -lt 100 ]; then
        echo
        echo "ERROR: Problem with ${nf}! Missing schema?"
        echo
        sleep 20
      else
        echo "Upload file for ${nf}"
        attempt_yp=0
        MAX_YP_ATTEMPTS=20
        while [ "${attempt_yp}" -le "${MAX_YP_ATTEMPTS}" ]; do
          YANG_OUTPUT=$(setsid ssh -o "ConnectTimeout=5" -o "StrictHostKeyChecking no" admin@"${NODE_IP}" -p"${YANG_PORT}"  -s netconf < ./configurations/"${nf}".xml)
          RESULT_CODE=$?
          echo "${YANG_OUTPUT}"
          CONF_ERROR=false
          echo "${YANG_OUTPUT}" | grep -q "<rpc-error>" && CONF_ERROR=true

          if [ "${RESULT_CODE}" -ne 0 ]; then
            echo "ERROR: Problem with connecting to YANG provider!"
          elif [ "${CONF_ERROR}" == 'true' ]; then
            echo "${YANG_OUTPUT}" | grep -q "Seed can only be set if Customer Key is not defined\|Cannot set encrypted-customer-key if hn-keys have any value set"
            if [ $? -eq 0 ]; then
              echo "Except for ARPF seed/customer-key, there are no other errors. Continue..."
              break
            fi
            echo "ERROR: Configuration loading returned errors!"
            if [ ${attempt_yp} -eq 10 ]; then
              echo "Collecting logs from CM for TR ADPPRG-39219"
              cmPods=$(kubectl get pod -n "${NS}" -o=wide --no-headers| grep eric-cm | grep -v eric-cm-mediator-key-init |awk '{print $1}')
              for i in ${cmPods}
                do
                  for j in `kubectl --namespace "${NS}" get pod $i -o jsonpath='{.spec.containers[*].name}'`
                    do
                      echo "********************************************"
                      echo "Print log for $i container ${j}:"
                      echo "********************************************"
                      kubectl --namespace "${NS}" logs $i -c $j
                    done
                done
                exit 1
            #kubectl delete -n "${NS}" pod $(kubectl get pod -n "${NS}" |grep eric-cm-yang-provider|awk '{print $1}')
            #sleep 60
            fi
          else
            echo "Configuration loaded successfully"
            break
          fi
          sleep 10
          attempt_yp=$(( ${attempt_yp} + 1 ))
        done
        if [ "${attempt_yp}" -gt "${MAX_YP_ATTEMPTS}" ]; then
          echo "FAILURE: Unable to load configuration for ${nf}"
          exit 1;
        fi
        echo
        echo
        break
      fi
      attempt_cm=$(( ${attempt_cm} + 1 ))
    done
    if [ "${attempt_cm}" -gt "${MAX_CM_ATEMPTS}" ]; then
      echo "FAILURE: Problem with ${nf}! Missing schema?"
      exit 1;
    fi
  done

  echo "***********************uploading the DDC config xml*******************"
  setsid ssh -o "ConnectTimeout=5" -o "StrictHostKeyChecking no" admin@"${NODE_IP}" -p"${YANG_PORT}"  -s netconf < ./configurations/ddc_conf_example.xml
  sleep 10
}

function waiting() {
  printMessage "Wait for pods to get up"
  attempt=0
  attemptNum=30
  UDR_PROV_SYNC_FE_UP_RUNNING=false
  
  ## Patch hpa with max replica because always see it scale out unexpectedly
  udr_hpa=$(kubectl get hpa -n "${NS}" | grep eric-udr |awk '{print $1}')
  for hpa in ${udr_hpa}; do
    kubectl -n "${NS}" patch hpa "${hpa}" -p "{\"spec\":{\"maxReplicas\":2}}"
  done

  while [ "${attempt}" -lt "${attemptNum}" ]; do
    CHECK_PODS=$(kubectl get pod -n "${NS}" -o=wide --no-headers | grep -v '\([0-9]\{1,2\}\)/\1' | grep -v Completed | grep -v eric-pcf-cm- | wc -l)
    curator_down=$(kubectl get pod -n "${NS}" -o=wide | grep eric-data-search-engine-curator | grep -v '\([0-9]\{1,2\}\)/\1'| grep -v Completed |  wc -l)
    curator_up=$(kubectl get pod -n "${NS}" -o=wide | grep eric-data-search-engine-curator | grep Completed |  wc -l)
    curator_exist=$(kubectl get pod -n "${NS}" -o=wide | grep eric-data-search-engine-curator | wc -l)

    evictedPodsNum=$(kubectl get pod -n "${NS}" | grep Evicted | wc -l)
    if [ "${evictedPodsNum}" -gt 0 ]; then
      evictedPods=$(kubectl get pod -n "${NS}" | grep Evicted | awk '{print $1}')
      echo "Deleting Evicted pods.."
      kubectl delete pod -n "${NS}" ${evictedPods}
    fi

    UDR_PROV_SYNC_FE_UP=$(kubectl get pod -n "${NS}" | grep eric-udr-prov-sync-fe | grep Running | wc -l)
    if [ ${UDR_PROV_SYNC_FE_UP} -ne 0 ] && [ "${UDR_PROV_SYNC_FE_UP_RUNNING}" == "false" ]; then
      UDR_PROV_SYNC_FE_UP_RUNNING=true
      #WA for D89-CCDM pod eric-udr-prov-sync-fe, disable istio-proxy container
      kubectl -n "${NS}" patch deploy eric-udr-prov-sync-fe -p '{"spec":{"template":{"metadata":{"labels":{"sidecar.istio.io/inject":"false"}}}}}'
    fi
    
    if [[ "${CHECK_PODS}" > 0 && "${CHECK_PODS}" != ${curator_down} ]]; then
      echo
      echo "WARNING: some pods are not running:"
      kubectl get pod -n "${NS}" -o=wide | grep -v '\([0-9]\{1,2\}\)/\1' | grep -v Completed | grep -v eric-pcf-cm-

      eda_pods_down=$(kubectl get pod -n "${NS}" -o=wide | grep eric-act | grep -v '\([0-9]\{1,2\}\)/\1' | grep -v Completed| wc -l)
      wcdb_pods_down=$(kubectl get pod -n "${NS}" -o=wide | grep eric-data-wide-column-database-cd | grep -v '\([0-9]\{1,2\}\)/\1' | grep -v Completed |  wc -l)
      if [ "${eda_pods_down}" -ge 1 ]; then
        if [ "${wcdb_pods_down}" -eq 0 ]; then
          eda_pods=$(kubectl get pod -n "${NS}" | grep eric-act | grep -v '\([0-9]\{1,2\}\)/\1' | grep -v Completed| awk '{print $1}')
          echo "Restart pods '${eda_pods}'"
          kubectl delete pod -n "${NS}" ${eda_pods}
        fi
      fi

      nssf_pods_pending=$(kubectl get pod -n "${NS}" | grep eric-nssf-kvdb-ag-server | grep Pending | wc -l)
      nssf_pods_age=$(kubectl get pod -n "${NS}" | grep eric-nssf-kvdb-ag-server | awk '{print $NF}' | egrep -v '^[0-9]+s|^2m[0-9]*s|^3m[0-9]*s' | wc -l)
      if [ ${nssf_pods_pending} -ge 1 ] && [ ${nssf_pods_age} -ge 1 ]; then
        echo "Found some NSSF pods down, restarting them.."
        kubectl delete pod -n "${NS}"  $(kubectl get pod -n "${NS}" | grep eric-nssf-kvdb-ag-server | awk '{print $1}')
      fi

      kvdb_pods_down=$(kubectl get pod -n "${NS}" -o=wide | grep eric-udr-kvdb-ag-server|grep Running | grep -v '\([0-9]\{1,2\}\)/\1' | wc -l)
      # Sometimes pvc of new sts will be deleted so pod will be pending(except ag-server), if so repeat restart steps
      kvdb_pods_pending=$(kubectl get pod -n "${NS}" | grep eric-udr-kvdb-ag|grep -v eric-udr-kvdb-ag-server |grep Pending| wc -l)
      if [ ${kvdb_pods_down} -ge 1 ] || [ ${kvdb_pods_pending} -ge 1 ]; then
        # If kvdb-server pods are running for more than 4m but still not ready then restart them
        age=$(kubectl get pod -n "${NS}" | grep eric-udr-kvdb-ag-server-0 | awk '{print $NF}' | egrep -v '^[0-9]+s|^2m[0-9]*s|^3m[0-9]*s|^4m[0-9]*s|^5m[0-9]*s|^6m[0-9]*s'| wc -l)
        if [ ${age} -ge 1 ] || [ ${kvdb_pods_pending} -ge 1 ]; then
          echo "Restarting KVDB pods because they failed to startup"
          kubectl delete pod -n "${NS}"  $(kubectl get pod -n "${NS}" | grep "dbmanager\|model\|dbmon\|udr-kvdb" | grep -v "udr-kvdb-ag-operator" | awk '{print $1}')
        fi
      fi
      echo
      sleep 60
    elif [[ "${curator_exist}" -gt 0 && "${curator_up}" -eq 0 ]]; then
      echo "Curator is not completed yet.."
      sleep 60
      kubectl get pod -n "${NS}" -o=wide | grep eric-data-search-engine-curator
    else
      printMessage "All PODs up and running"

      printMessage "Checking the httpproxy status"
      kubectl get httpproxy -n "${NS}"

      printMessage "Change the UdmUrl value in eric-ausf-engine-configmap"
      kubectl get configmap eric-ausf-engine-configmap -o yaml -n "${NS}"| sed  's/{scheme}:\/\/{authority}/http:\/\/'"${NODE_IP}":"${UDM_PORT}"'/'|kubectl replace -f -

      echo
      sleep 5
      echo "Checking NRF registrations"

      NRF_PORT=$(kubectl get svc -n "${NS}" | grep eric-ingressgw-nrf-traffic | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
      nfInstances=$(curl -s http://"${NODE_IP}":"${NRF_PORT}"/nnrf-nfm/v1/nf-instances|grep f8b5865c-49e8-463e-8f16-4dd6a15d3f41|grep 0c765084-9cc5-49c6-9876-ae2f5fa2a63f |grep 13a1de33-ec45-4cd6-a842-ce5bb3cba3d8|grep 841d1b7c-5103-11e9-8c09-174c95907e28 |wc -l)
      
      ausfStatus=$(curl -s http://"${NODE_IP}":"${NRF_PORT}"/nnrf-nfm/v1/nf-instances/0c765084-9cc5-49c6-9876-ae2f5fa2a63f | jq .nfStatus)
      udrStatus=$(curl -s http://"${NODE_IP}":"${NRF_PORT}"/nnrf-nfm/v1/nf-instances/f8b5865c-49e8-463e-8f16-4dd6a15d3f41 | jq .nfStatus)
      nssfStatus=$(curl -s http://"${NODE_IP}":"${NRF_PORT}"/nnrf-nfm/v1/nf-instances/13a1de33-ec45-4cd6-a842-ce5bb3cba3d8 | jq .nfStatus)
      udmStatus=$(curl -s http://"${NODE_IP}":"${NRF_PORT}"/nnrf-nfm/v1/nf-instances/841d1b7c-5103-11e9-8c09-174c95907e28 | jq .nfStatus)

      if [ "${nfInstances}" -eq 0 ]; then
        echo "Found some NF not registered in NRF, restarting nrf-register-agent pods"
        kubectl delete pod -n "${NS}" `kubectl get pod -n "${NS}" |grep nrf-register-agent |awk '{print $1}'`
        sleep 30
      elif [ "${ausfStatus}" == '"SUSPENDED"' ] || [ "${udrStatus}" == '"SUSPENDED"' ] || [ "${nssfStatus}" == '"SUSPENDED"' ] || [ "${udmStatus}" == '"SUSPENDED"' ]; then
        echo "Found some NF are suspended in NRF, restarting nrf-register-agent pods"
        kubectl delete pod -n "${NS}" `kubectl get pod -n "${NS}" |grep nrf-register-agent |awk '{print $1}'`
        sleep 30
      fi

      pcfWithStatusError=$(kubectl  get pod -n "${NS}" | grep pcf | grep Error | awk '{print $1}')
      if [ -n "${pcfWithStatusError}" ]; then
        echo
        echo "Deleting PCF pod's with status Error: ${pcfWithStatusError}"
        kubectl -n "${NS}" delete pod ${pcfWithStatusError}
      fi
      exit 0
    fi
    attempt=$(( ${attempt} + 1 ))
  done

  echo
  echo "FAIL: some pods are not running:"
  podsDown=$(kubectl get pod -n "${NS}" -o=wide --no-headers| grep -v '\([0-9]\{1,2\}\)/\1' | grep -v Completed | grep -v eric-pcf-cm-|awk '{print $1}')
  for i in ${podsDown}
      do
          echo "********************************************"
          echo "Describe pod ${i}:"
          echo "********************************************"
          kubectl -n "${NS}" describe pod $i
          for j in `kubectl --namespace "${NS}" get pod $i -o jsonpath='{.spec.containers[*].name}'`
              do
                  echo "********************************************"
                  echo "Print log for $i container ${j}:"
                  echo "********************************************"
                  kubectl --namespace "${NS}" logs $i -c $j
              done
      done
  exit 1
}

main() {
  cleanup
  install
  configure
  waiting
}

main

