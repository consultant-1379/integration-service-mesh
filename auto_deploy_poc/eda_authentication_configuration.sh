#!/bin/bash

NS="5g-integration"

echo "Exposing eric-act-aaa-service"
NODE_IP=$(kubectl describe node $(echo $(kubectl get node | awk '$3~/node/' | awk 'NR==1{print $1}')) | grep InternalIP -m1 | awk '{print $2}')
kubectl patch svc eric-act-aaa -n "${NS}" -p '{"spec":{"type": "NodePort"}}'
kubectl patch svc eric-act-aaa -n "${NS}" -p '{"spec":{"externalIPs":["'"${NODE_IP}"'"]}}'

sleep 10

attempt=0
MAX_ATEMPTS=4
while [ "${attempt}" -le "${MAX_ATEMPTS}" ]; do
  RESULT=$(curl https://${NODE_IP}:8383 --insecure | wc -c)
  echo ${RESULT}
  if [ "${RESULT}" -eq 0 ]; then
    echo
    echo "Waiting for REST API"
    echo
    sleep 15
  else
    break
  fi
  attempt=$(( ${attempt} + 1 ))
done

cat > onboarding.json <<EOF
{
    "users": [
        {
            "user_name": "admin@ericsson.com",
            "password": "Password!1234"
        }
    ],
    "service_account": [
        {
            "user_name": "superuser@ericsson.com",
            "password": "Password!1234"
        }
    ],
    "clients": [
        {
            "client_id": "comp1",
            "client_name": "edaLocal"
        }
    ]
}
EOF

EDA_ONBOARDING_RESULT=$(curl -X POST -H "Content-Type: application/json; charset=utf-8" https://${NODE_IP}:8383/oauth/v1/onboard --insecure -d @onboarding.json)

CLIENT_ID=$(echo ${EDA_ONBOARDING_RESULT} | sed 's/.*client_id":"//g' | sed 's/".*//g')
CLIENT_SECRET=$(echo ${EDA_ONBOARDING_RESULT} | sed 's/.*client_secret":"//g' | sed 's/".*//g')
echo "client_id: "${CLIENT_ID}
echo "client_secret: "${CLIENT_SECRET}
echo -e "\n\n"

echo ${EDA_ONBOARDING_RESULT} >> eda_onboarding_result.txt
cat eda_onboarding_result.txt

cat > fetch_access_token <<EOF
client_id=${CLIENT_ID}&
client_secret=${CLIENT_SECRET}&
grant_type=password&
username=superuser@ericsson.com&
password=Password!1234&
scope=openid+scopes.ericsson.com/activation/roles.read+scopes.ericsson.com/activation/roles.write+scopes.ericsson.com/activation/oauth.authn.user.read+scopes.ericsson.com/activation/oauth.authn.user.write+scopes.ericsson.com/activation/oauth.authn.user.reset+scopes.ericsson.com/activation/oauth.authn.user.lock+scopes.ericsson.com/activation/oauth.core.client.read+scopes.ericsson.com/activation/oauth.core.client.write+scopes.ericsson.com/activation/oauth.core.user.read+scopes.ericsson.com/activation/oauth.core.user.write
EOF

EDA_FETCH_ACCESS_TOKEN_RESULT=$(curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d @fetch_access_token https://${NODE_IP}:8383/oauth/v1/token --insecure)
EDA_ACCESS_TOKEN=$(echo ${EDA_FETCH_ACCESS_TOKEN_RESULT} | sed 's/.*access_token":"//g' | sed 's/".*//g')

NEW_ROLE="CcdmTestUser"

cat > roles_from_scopes.json <<EOF
{
    "types": "role",
    "id": "${NEW_ROLE}",
    "description": "Finally User",
    "value": {
        "scopes": [
            "scopes.ericsson.com/activation/log-consolidation.delete",
            "scopes.ericsson.com/activation/log-consolidation.export",
            "scopes.ericsson.com/activation/oauth.core.client.write",
            "scopes.ericsson.com/activation/oauth.core.client.read",
            "scopes.ericsson.com/activation/mapi.read",
            "scopes.ericsson.com/activation/mapi.write",
            "scopes.ericsson.com/activation/roles.read",
            "scopes.ericsson.com/activation/roles.write",
            "scopes.ericsson.com/activation/oauth.authn.user.read",
            "scopes.ericsson.com/activation/oauth.authn.user.write",
            "scopes.ericsson.com/activation/oauth.core.user.read",
            "scopes.ericsson.com/activation/oauth.authn.user.reset",
            "scopes.ericsson.com/activation/oauth.authn.user.lock",
            "scopes.ericsson.com/activation/oauth.core.user.write"
        ]
    }
}
EOF

curl -X POST --header "Authorization: Bearer ${EDA_ACCESS_TOKEN}" --header "Content-Type: application/json; charset=utf-8" -d @roles_from_scopes.json https://${NODE_IP}:8383/accessrules/v1/roles --insecure

CURRENT_PROFILE_OUTPUT=$(curl -X GET --header "Authorization: Bearer ${EDA_ACCESS_TOKEN}" https://${NODE_IP}:8383/oauth/v1/users/profile/this --insecure)
echo "CURRENT PROFILE OUTPUT"
echo ${CURRENT_PROFILE_OUTPUT}
echo -e "\n\n"
USER_PROFILE=$(echo ${CURRENT_PROFILE_OUTPUT} | jq -r '.user_id')

ADD_ROLE_CURRENT_PROFILE=$(echo $CURRENT_PROFILE_OUTPUT | jq '.user_info_internal.roles |="[\"System setup manager\",\"CcdmTestUser\"]"')
echo "MODIFIED CURRENT PROFILE"
echo ${ADD_ROLE_CURRENT_PROFILE} | jq > update_user_profile.json
echo -e "\n\n"

curl -X PUT --header "Authorization: Bearer ${EDA_ACCESS_TOKEN}" --header "Content-Type: application/json; charset=utf-8" -d @update_user_profile.json https://${NODE_IP}:8383/oauth/v1/users/profile/${USER_PROFILE} --insecure

cat > deployment.properties<<EOF
CLIENT_ID=${CLIENT_ID}
CLIENT_SECRET=${CLIENT_SECRET}
EOF