#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function info() {
    echo
    echo -e "$(date +%Y-%m-%d\ %H:%M:%S) - ${GREEN}INFO${NC} - $1"
}

function error() {
    echo
    echo -e "$(date +%Y-%m-%d\ %H:%M:%S) - ${RED}ERROR${NC} - $1"
}

if [[ -z "${project_name}" ]]; then
    error "Environment variable project_name is not defined. Try export project_name=\"<deployment_namespace>\""
    exit 1
fi

namespace=${project_name}
info "Namespace: ${namespace}"
release_statefulset=$(oc -n ${namespace} get statefulset --no-headers --selector type=engine | awk '{print $1}')
head_node=$(oc -n ${namespace} get po --no-headers --selector name=dashmpp-head-0 | awk '{print $1}')
info "Head node: ${head_node}"

workload=$(oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2set -all | grep DB2_WORKLOAD= | awk '{print \$2}'")
if [[ "${workload}" == "DB2_WORKLOAD=PUREDATA_OLAP"* ]]
then
    info "Workload already set. Exiting."
    exit 0
fi

info "Disabling HA"
oc exec -n ${namespace} -it ${head_node} -- wvcli system disable -m "Stop HA"

info "Current list of running applications:"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2 list applications"

info "Attempting to kill all running applications"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2 force applications all"

info "Deactivate the DB"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2 deactivate db bludb"

info "Stop DB2"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2stop force"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "rah 'ipclean -a'"

info "Set workload type"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2set DB2_WORKLOAD=PUREDATA_OLAP"

info "Starting DB"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2start"

info "Creating DB configuration script"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "cat <<EOF >/mnt/blumeta0/db2/scripts/db2_autocfg.clp
-- CLP script to run DB2 AUTOCONFIGURE

ACTIVATE DB BLUDB;
CONNECT TO BLUDB;
UPDATE DB CFG FOR BLUDB USING SELF_TUNING_MEM OFF;
UPDATE DB CFG FOR BLUDB USING LOGPRIMARY 50;
UPDATE DB CFG FOR BLUDB USING LOGSECOND 200;
UPDATE DB CFG FOR BLUDB USING LOGARCHMETH1 OFF; 
AUTOCONFIGURE USING KEEP_LOG_SETTINGS YES MEM_PERCENT 50 APPLY DB AND DBM;
AUTOCONFIGURE USING KEEP_LOG_SETTINGS YES MEM_PERCENT 50 APPLY NONE REPORT FOR MEMBER -2;
CONNECT RESET;
FORCE APPLICATIONS ALL;
DEACTIVATE DB BLUDB;
TERMINATE;
EOF"

info "Refresh DB config"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2 -tvf /mnt/blumeta0/db2/scripts/db2_autocfg.clp"

info "Stopping DB"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2stop force"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "rah 'ipclean -a'"

info "Starting DB"
oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2start"

info "Enabling HA"
oc exec -n ${namespace} -it ${head_node} -- wvcli system enable -m "Start HA"

info "Forcing pod restart on non-head nodes"
oc delete pod -n ${namespace} --selector type=engine,name!=dashmpp-head-0

info "Waiting for non-head pods readiness"
oc rollout status --watch --timeout=600s -n ${namespace} statefulset ${release_statefulset}

workload=$(oc exec -n ${namespace} -it ${head_node} -- sudo su - db2inst1 -c "db2set -all | grep DB2_WORKLOAD= | awk '{print \$2}'")
info "Workload is: ${workload}"
