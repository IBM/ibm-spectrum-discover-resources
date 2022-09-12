########################################################## {COPYRIGHT-TOP} ###
# Licensed Materials - Property of IBM
# 5737-I32
#
# (C) Copyright IBM Corp. 2021
#
# US Government Users Restricted Rights - Use, duplication, or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
########################################################## {COPYRIGHT-END} ###

function podlog {
	podlabel=$1
	oc logs $(oc get pods -n=spectrum-discover -l app=${podlabel} -o=jsonpath='{.items[0].metadata.name}') -n=spectrum-discover
}
function podbash {
	podlabel=$1
	oc exec -it $(oc get pods -n spectrum-discover -l app=${podlabel} -o=jsonpath='{.items[0].metadata.name}') -n=spectrum-discover -- /bin/bash
}
function delpod {
	podlabel=$1
	oc delete pod $(oc get pods -n spectrum-discover -l app=${podlabel} -o=jsonpath='{.items[0].metadata.name}') -n=spectrum-discover
}
function redeploy {
	deployment=$1
	newtag=$2
	oc patch deployment.v1.apps/spectrum-discover-${deployment} -n spectrum-discover -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"spectrum-discover\",\"image\":\"$(kubectl get deployment/spectrum-discover-${deployment} -n spectrum-discover -o=jsonpath='{@.spec.template.spec.containers[0].image}' | sed -e 's/[0-9]*-[0-9]*$//')${newtag}\"}]}}}}"
}

# UI Frontend log
alias uiflog='podlog spectrum-discover-ui-frontend'
# UI Backend log
alias uiblog='podlog spectrum-discover-ui-backend'
# Shell into the running db2wh-rest container
alias db2ex='podbash spectrum-discover-db2whrest'
# Shell into the running policy engine container
alias peex='podbash spectrum-discover-policyengine'
# Shell into the running connection management container
alias conex='podbash spectrum-discover-connmgr'
# Delete db2wh-rest pod
alias redb2='delpod spectrum-discover-db2whrest'
# Db2wh-rest log
alias db2log='podlog spectrum-discover-db2whrest'
# Connection management log
alias conlog='podlog spectrum-discover-connmgr'
# Policy Engine log
alias pollog='podlog spectrum-discover-policyengine'
alias pelog='podlog spectrum-discover-policyengine'
# SD Monitor log
alias sdmonlog='podlog spectrum-discover-sdmonitor'
# Db2wh password
alias pw='oc exec -it -n=spectrum-discover $(oc get pods -n=spectrum-discover -l app=spectrum-discover-connmgr -o=jsonpath={.items[0].metadata.name}) env |grep DB2WHREST_PASSWORD | cut -d "=" -f 2'
# List policies
alias getpols='tcurl https://${SD_HOST:?environment variable must be set}/policyengine/v1/policies |jq'
# List data source connections
alias getconns='tcurl https://${SD_HOST:?environment variable must be set}/connmgr/v1/connections |jq'
# Get/restart scrips for scale/file producers
alias psplog='podlog spectrum-discover-producer-scale-scan'
alias repsp='delpod spectrum-discover-producer-scale-scan'
alias pfplog='podlog spectrum-discover-producer-file-scan'
alias repfp='delpod spectrum-discover-producer-file-scan'
# Get TLS certificates
alias tls='gettoken; curl -k -H "Authorization: Bearer ${TOKEN}"  https://${SD_HOST:?environment variable must be set}/policyengine/v1/tlscert'

# Facilitate display of producer/consumer logs
function pclog {
	pod=$1
	NAMESPACE=$(echo $pod|awk -F'-' '{print $3 $4 $5}')
	oc -n $NAMESPACE logs $pod
}
function pclogf {
	pod=$1
	NAMESPACE=$(echo $pod|awk -F'-' '{print $3 $4 $5}')
	oc -n $NAMESPACE logs $pod -f
}

# Function to load connection json doc
function load_connection() {
	CONDOC=$1
	if [ $# -ne 1 ]; then
		echo "load_connection <connection.json>"
	else
		gettoken
		curl -k -H "Authorization: Bearer ${TOKEN}" https://${SD_HOST:?environment variable must be set}/connmgr/v1/connections -X POST -H "Content-type: application/json" -d@"$1"
	fi
}

# Get all running pods
alias allpods='oc get pods --all-namespaces'
alias kp='oc get pods --all-namespaces'

# Fetch a valid authentication token
alias gettoken="export TOKEN=\$(curl -k -u \${SD_USER:?environment variable must be set}:\${SD_PASSWORD:?environment variable must be set} https://\${SD_HOST:?environment variable must be set}/auth/v1/token -I | grep X-Auth-Token |cut -f 2 -d \" \")"

# Curl with authorization token
alias tcurl="curl -k -H \"Authorization: Bearer \${TOKEN}\""
alias tcurl_json="curl -k -H \"Authorization: Bearer \${TOKEN}\" -H \"Content-type: application/json\""

#COS-SCANNER aliases for running scanner scripts inside docker
alias cos-notify='oc exec -it --namespace=spectrum-discover $(oc get pods -n=spectrum-discover -l app=spectrum-discover-connmgr -o=jsonpath='{.items[0].metadata.name}') -- bash -c "python3 -m scanners.cloud_scanner.main_notifier"'
alias cos-replay='oc exec -it --namespace=spectrum-discover $(oc get pods -n=spectrum-discover -l app=spectrum-discover-connmgr -o=jsonpath='{.items[0].metadata.name}') -- bash -c "python3 -m scanners.cloud_scanner.main_replay"'

# Enable/disable the schedule of the duplicates/mrcapacity scan cronjobs
alias enabledupjob='gettoken; tcurl_json https://${SD_HOST:?environment variable must be set}/db2whrest/v1/summary_tables/duplicates -X PUT -d'"'"'{"enabled": true}'"'"''
alias disabledupjob='gettoken; tcurl_json https://${SD_HOST:?environment variable must be set}/db2whrest/v1/summary_tables/duplicates -X PUT -d'"'"'{"enabled": false}'"'"''
alias enablemrcapjob='gettoken; tcurl_json https://${SD_HOST:?environment variable must be set}/db2whrest/v1/summary_tables/mrcapacity -X PUT -d'"'"'{"enabled": true}'"'"''
alias disablemrcapjob='gettoken; tcurl_json https://${SD_HOST:?environment variable must be set}/db2whrest/v1/summary_tables/mrcapacity -X PUT -d'"'"'{"enabled": false}'"'"''
alias rundupjob='gettoken; tcurl_json https://${SD_HOST:?environment variable must be set}/db2whrest/v1/summary_tables/duplicates/start -X PUT'
alias runmrcapjob='gettoken; tcurl_json https://${SD_HOST:?environment variable must be set}/db2whrest/v1/summary_tables/mrcapacity/start -X PUT'
