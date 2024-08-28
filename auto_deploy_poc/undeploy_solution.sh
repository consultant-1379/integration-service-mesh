#!/bin/bash

NS=5g-integration

echo "******************************************"
echo "Removing previous installation"
echo "******************************************"
releases=$(helm list --all --namespace ${NS} | grep -v NAME | awk '{print $1}')
if [ ! -z "${releases}" ]; then
  helm delete --purge ${releases} --no-hooks
fi
kubectl delete cm --all -n ${NS}
kubectl delete pvc --all -n ${NS}
kubectl delete job --all -n ${NS}
secrets=$(kubectl get secret -n ${NS} | grep "^eric-sec\|^eric-data-distributed\|^eric-adp\|^eric-cm\|^eric-data-document\|^eric-odca-diagnostic\|snmp-alarm-provider" | awk '{print $1}')
if [ ! -z "${secrets}" ]; then
  kubectl delete secret -n ${NS} ${secrets}
fi