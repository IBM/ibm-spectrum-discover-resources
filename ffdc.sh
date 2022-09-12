#!/bin/bash
# Licensed Materials - Property of IBM
#
# (C) COPYRIGHT International Business Machines Corp. 2022
# All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

LOG_DIRS="/var/log/backup-restore \
          /var/log/kafka \
          /var/log/secure"

FFDC_ID=mo-ffdc-$(date +"%Y%m%d%H%M%S%3N")
FFDC_DIR=/tmp/${FFDC_ID}

function setup_ffdc {
	mkdir -p ${FFDC_DIR}	
}

function close_ffdc {
	tar cJf ${FFDC_ID}.tar.xz -C ${FFDC_DIR} . && rm -rf ${FFDC_DIR:-uh-oh}
	info "Collected FFDC in ${FFDC_ID}.tar.xz" 
}

function fail_unless_bastion {
	oc_project_output=$(oc project ${project_name})
	if [[ "$?" != "0" ]]	
	then
		error "Must be run on the Openshift bastion node with the Openshift command line."
	fi	
	info "${oc_project_output}"
}

function gather_versions {
	setup_ffdc
	VERSION_FFDC_DIR=${FFDC_DIR}/versions
	info "Gathering application versions..."
	mkdir -p ${VERSION_FFDC_DIR}
	# System version
	cp /etc/*release ${VERSION_FFDC_DIR}
	# Docker version
	docker version >${VERSION_FFDC_DIR}/docker.txt 
	# Kubernetes version
	kubectl version >${VERSION_FFDC_DIR}/kubernetes.txt
	# OC version
	oc version >${VERSION_FFDC_DIR}/openshiftcommand.txt
	# OCP version
	oc get clusterversion >${VERSION_FFDC_DIR}/openshiftCluster.txt
	# AMQ Streams version
	AMQ_HEAD=$(oc -n ${namespace} get po | grep amq | awk '{print $1}')
	oc exec -n ${project_name} -it ${AMQ_HEAD} -- ls lib > ${VERSION_FFDC_DIR}/amq.txt
}

function gather_logs {
	setup_ffdc
	REL_LOG_DIRS=""
	LOGS_FFDC_DIR=${FFDC_DIR}/logs
	mkdir -p ${LOGS_FFDC_DIR}
	for path in ${LOG_DIRS}
	do
		REL_LOG_DIRS="${REL_LOG_DIRS} ${path#/}"
	done
	info "Archiving log files..."
	sudo tar cJf ${LOGS_FFDC_DIR}/logs.tar.xz -C / ${REL_LOG_DIRS} 2>${LOGS_FFDC_DIR}/logs.stderr
	[ -s ${LOGS_FFDC_DIR}/logs.stderr ] || rm -rf ${LOGS_FFDC_DIR}/logs.stderr
}

function gather_system_stats {
	setup_ffdc
	STATS_FFDC_DIR=${FFDC_DIR}/system_stats
	info "Gathering bastion system statistics..."
	mkdir -p ${STATS_FFDC_DIR}
	df -h >${STATS_FFDC_DIR}/disk_free.txt
	last reboot >${STATS_FFDC_DIR}/last_reboot.txt
	vmstat >${STATS_FFDC_DIR}/vmstat.txt
	netstat -a >${STATS_FFDC_DIR}/netstat-a.txt
	info "Gathering Openshift Cluster statistics..."
	oc get pvc --all-namespaces >${STATS_FFDC_DIR}/pvc_data.txt
	oc get node >${STATS_FFDC_DIR}/nodes.txt
	for node in $(oc get node --no-headers | awk '{print $1}');do oc describe node $node;done >${STATS_FFDC_DIR}/node_data.txt
	oc get sc >${STATS_FFDC_DIR}/sc_data.txt
}

function gather_db2_logs {
	setup_ffdc
	DB2WH_HEAD=$(oc -n ${namespace} get po --no-headers --selector name=dashmpp-head-0 | awk '{print $1}')
    info "Head node: ${DB2WH_HEAD}"
	LOGS_FFDC_DIR=${FFDC_DIR}/logs
	mkdir -p ${LOGS_FFDC_DIR}
	info "Gathering DB2WH logs..."
	CMD_OUTPUT=${LOGS_FFDC_DIR}/db2diag.log
	info "${CMD_OUTPUT}"
	oc exec -n ${project_name} -it ${DB2WH_HEAD} -- su - db2inst1 -c 'db2diag' > ${CMD_OUTPUT}	
	info "Gathering DB2 BLUDB Details..."
	info "Creating DB configuration script..."
    oc exec -n ${project_name} -it ${DB2WH_HEAD} -- sudo su - db2inst1 -c "cat <<EOF >/mnt/blumeta0/db2/scripts/db2_info.clp
    -- CLP script to run DB2 CFG info
	CONNECT TO BLUDB;
	GET DB CFG;
	GET DBM CFG;
	TERMINATE;
	EOF"
	info "Get DB config..."
    oc exec -n ${project_name} -it ${DB2WH_HEAD} -- sudo su - db2inst1 -c "db2 -tvf /mnt/blumeta0/db2/scripts/db2_info.clp" >${LOGS_FFDC_DIR}/db2_cfg.txt	
}

function gather_project_info {
	setup_ffdc
	SD_FFDC_DIR=${FFDC_DIR}/project
	mkdir -p ${SD_FFDC_DIR}
	info "Gathering info for project ${project_name}..."
	PROJECT_DIR=${SD_FFDC_DIR}/${project_name}
	mkdir -p ${PROJECT_DIR}
	PODS=$(oc get pods -n ${project_name} --no-headers |awk '{print $1}')
	for pod in ${PODS}
	do
		oc describe pod ${pod} -n ${project_name} > ${PROJECT_DIR}/${pod}.yaml
		CONTAINERS=$(oc get pods ${pod} -n ${project_name} -ojsonpath={.spec.containers[*].name})
		for container in ${CONTAINERS}
		do
			oc logs ${pod} -n ${project_name} ${container} &>${PROJECT_DIR}/${pod}_${container}.log
		done
	done
	oc get events -ojson -n ${project_name} >${PROJECT_DIR}/events.json
}

function gather_config_map {
	setup_ffdc
	CM_FFDC_DIR=${FFDC_DIR}/cm
	mkdir -p ${CM_FFDC_DIR}
	info "Gather Config maps for ${project_name}..."
	CMS=$(oc get cm -n ${project_name} --no-headers | awk '{print $1}')
	for cm in ${CMS}
	do
	  oc describe cm ${cm} -n ${project_name} > ${CM_FFDC_DIR}/${cm}.yaml
	done
}

function gather_service_status {
	setup_ffdc
	SERVICES_FFDC_DIR=${FFDC_DIR}/services
	info "Gathering service statuses..."
	mkdir -p ${SERVICES_FFDC_DIR}
	ps -ef >${SERVICES_FFDC_DIR}/processes.txt
	systemctl list-units --type=service &>${SERVICES_FFDC_DIR}/services.txt
}

function gather_remote_services {
	setup_ffdc
	SERVICES_FFDC_DIR=${FFDC_DIR}/services
	for NODE in $(oc get node --no-headers | awk '{print $1}')
	do
		info "Gathering services from ${NODE}"
		SERVICE_FFDC_DIR=${SERVICES_FFDC_DIR}/${NODE}
		mkdir -p ${SERVICE_FFDC_DIR}
		oc debug node/${NODE} -T -- chroot /host sh -c "ps -ef" >${SERVICE_FFDC_DIR}/${NODE}_processes.txt
		oc debug node/${NODE} -T -- chroot /host sh -c "systemctl list-units --type=service" >${SERVICE_FFDC_DIR}/${NODE}_services.txt
	done
}

function usage {
	info "$0 [all|logs|project|configmap|services|system|versions]"
	info "\t$(tput bold)logs$(tput sgr0) - Collect Db2 diagnostic and system log files"
	info "\t$(tput bold)project$(tput sgr0) - Collect project data logs"
	info "\t$(tput bold)configmap$(tput sgr0) - Collect project config maps"
	info "\t$(tput bold)services$(tput sgr0) - Collect processes and services"
	info "\t$(tput bold)system$(tput sgr0) - Collect system information"
	info "\t$(tput bold)versions$(tput sgr0) - Collect application versions"
	info "\t$(tput bold)all$(tput sgr0) - All of the above"
	info "The $(tput bold)all$(tput sgr0) call uses remote collection of logs and service statuses."
	info "Must be run on the Red Hat Openshift bastion node."
}

function error() {
    echo -e "$(date +%Y-%m-%d\ %H:%M:%S) - ${RED}ERROR${NC} - $1"
}

function info() {
    echo -e "$(date +%Y-%m-%d\ %H:%M:%S) - ${GREEN}INFO${NC} - $1"
}

if [[ -z "${project_name}" ]]; then
  error "Environment variable project_name is not defined. Try export project_name=\"<deployment_namespace>\""
  exit 1
fi

namespace=${project_name}
info "Namespace: ${namespace}"

case $1 in 	
	logs)
		fail_unless_bastion
		gather_db2_logs
		gather_logs
		;;
	project)
		fail_unless_bastion
		gather_project_info
		;;
	services)
		fail_unless_bastion
		gather_remote_services
		gather_service_status
		;;
	system)
		fail_unless_bastion
		gather_system_stats
		;;
	versions)
		fail_unless_bastion
		gather_versions
		;;
	configmap)
	    fail_unless_bastion
		gather_config_map
		;;
	all)
		fail_unless_bastion
		gather_db2_logs
		gather_logs
		gather_project_info
		gather_remote_services
		gather_service_status
		gather_system_stats
		gather_versions
		;;
	*)
		usage
		exit 0
		;;
esac

close_ffdc
