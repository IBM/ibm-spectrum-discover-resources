########################################################## {COPYRIGHT-TOP} ###
# Licensed Materials - Property of IBM
# 5737-I32
#
# (C) Copyright IBM Corp. 2022
#
# US Government Users Restricted Rights - Use, duplication, or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
########################################################## {COPYRIGHT-END} ###

if [[ -z "${PROJECT_NAME}" ]]; then
  echo -e "$(date +%Y-%m-%d\ %H:%M:%S) - \033[0;31mERROR\033[0m - Environment variable PROJECT_NAME is not defined. Try export PROJECT_NAME=\"<deployment_namespace>\""
fi

function podlog {
	selector=$1
	oc -n ${PROJECT_NAME} logs --selector=${selector} --all-containers
}

function podbash {
	selector=$1
	deployment=$(oc -n ${PROJECT_NAME} get deployment --selector=${selector} -o name)
	oc -n ${PROJECT_NAME} rsh ${deployment}
}

function delpod {
	selector=$1
	oc -n ${PROJECT_NAME} delete pod --selector=${selector}
}

function redeploy {
	deployment=$1
	image=$2
	container="${3}:-spectrum-discover"
	oc -n ${PROJECT_NAME} patch deployment/${deployment} -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"${container}\",\"image\":\"${image}\"}]}}}}"
}

# UI Frontend log
alias uiflog='podlog role=ui,sub-role=frontend'
# UI Backend log
alias uiblog='podlog role=ui,sub-role=backend'
# Shell into the running db2wh-rest container
alias db2ex='podbash role=db2whrest'
# Shell into the running policy engine container
alias peex='podbash role=policyengine'
# Shell into the running connection management container
alias conex='podbash role=connmgr'
# Delete db2wh-rest pod
alias redb2='delpod role=db2whrest'
# Db2wh-rest log
alias db2log='podlog role=db2whrest'
# Connection management log
alias conlog='podlog role=connmgr'
# Policy Engine log
alias pollog='podlog role=policyengine'
alias pelog='podlog role=policyengine'
# SD Monitor log
alias sdmonlog='podlog role=sdmonitor'
# Db2wh password
alias pw='oc -n ${PROJECT_NAME} exec -c spectrum-discover $(oc -n ${PROJECT_NAME} get pods -l role=connmgr -o name) -- env | grep DB2WHREST_PASSWORD | cut -d "=" -f 2'
# List policies
alias getpols='tcurl https://${SD_CONSOLE_ROUTE:?environment variable must be set}/policyengine/v1/policies | jq'
# List data source connections
alias getconns='tcurl https://${SD_CONSOLE_ROUTE:?environment variable must be set}/connmgr/v1/connections | jq'
# Get/restart scrips for scale/file producers
alias psplog='podlog role=scale-scan'
alias repsp='delpod role=scale-scan'
alias pfplog='podlog role=file-scan'
alias repfp='delpod role=file-scan'
# Get TLS certificates
alias tls='gettoken; curl -k -H "Authorization: Bearer ${TOKEN}" https://${SD_CONSOLE_ROUTE:?environment variable must be set}/policyengine/v1/tlscert'

# Facilitate display of producer/consumer logs
function pclog {
	pod=$1
	oc -n ${PROJECT_NAME} logs ${pod}
}
function pclogf {
	pod=$1
	oc -n ${PROJECT_NAME} logs ${pod} -f
}

# Function to load connection json doc
function load_connection() {
	CONDOC=$1
	if [ $# -ne 1 ]; then
		echo "load_connection <connection.json>"
	else
		gettoken
		curl -k -H "Authorization: Bearer ${TOKEN}" https://${SD_CONSOLE_ROUTE:?environment variable must be set}/connmgr/v1/connections -X POST -H "Content-type: application/json" -d@"$1"
	fi
}

# Get all running pods
alias allpods='oc -n ${PROJECT_NAME} get pods'
alias kp='oc -n ${PROJECT_NAME} get pods'

# Fetch a valid authentication token
alias gettoken='export TOKEN=$(curl -s -k -u ${SD_USER:-sdadmin}:${SD_PASSWORD:?environment variable must be set} https://${SD_CONSOLE_ROUTE:?environment variable must be set}/auth/v1/token -I | grep -i X-Auth-Token | cut -f 2 -d " ") | xargs'

# Curl with authorization token
alias tcurl='curl -s -k -H "Authorization: Bearer ${TOKEN}"'
alias tcurl_json='curl -k -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json"'

#COS-SCANNER aliases for running scanner scripts inside docker
alias cos-notify='oc -n ${PROJECT_NAME} exec -c spectrum-discover -it $(oc -n ${PROJECT_NAME} get pods -l role=connmgr -o name) -- bash -c "python3 -m scanners.cloud_scanner.main_notifier"'
alias cos-replay='oc -n ${PROJECT_NAME} exec -c spectrum-discover -it $(oc -n ${PROJECT_NAME} get pods -l role=connmgr -o name) -- bash -c "python3 -m scanners.cloud_scanner.main_replay"'

# Enable/disable the schedule of the duplicates/mrcapacity scan cronjobs
alias enabledupjob='gettoken; tcurl_json https://${SD_CONSOLE_ROUTE:?environment variable must be set}/db2whrest/v1/summary_tables/duplicates -X PUT -d'"'"'{"enabled": true}'"'"''
alias disabledupjob='gettoken; tcurl_json https://${SD_CONSOLE_ROUTE:?environment variable must be set}/db2whrest/v1/summary_tables/duplicates -X PUT -d'"'"'{"enabled": false}'"'"''
alias enablemrcapjob='gettoken; tcurl_json https://${SD_CONSOLE_ROUTE:?environment variable must be set}/db2whrest/v1/summary_tables/mrcapacity -X PUT -d'"'"'{"enabled": true}'"'"''
alias disablemrcapjob='gettoken; tcurl_json https://${SD_CONSOLE_ROUTE:?environment variable must be set}/db2whrest/v1/summary_tables/mrcapacity -X PUT -d'"'"'{"enabled": false}'"'"''
alias rundupjob='gettoken; tcurl_json https://${SD_CONSOLE_ROUTE:?environment variable must be set}/db2whrest/v1/summary_tables/duplicates/start -X PUT'
alias runmrcapjob='gettoken; tcurl_json https://${SD_CONSOLE_ROUTE:?environment variable must be set}/db2whrest/v1/summary_tables/mrcapacity/start -X PUT'
