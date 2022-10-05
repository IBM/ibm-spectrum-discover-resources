#!/bin/bash
# Licensed Materials - Property of IBM
#
# (C) COPYRIGHT International Business Machines Corp. 2022
# All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# 

if [ -n "$1" ]; then
   config="$1"
    . ${config}
fi

function check_var()
{
    test -z ${!1}
    ! (($?)) && echo -e "${1} Env variable not defined. Needed for continuing with the execution.\nExiting..." && exit 1
}

function restart_db()
{
    command=$1
    headConName=$2
    echo "Stopping all DB2 current connections..."
    eval "${command} ${headConName} bash" <<EOF
    su - db2inst1
    echo "Stopping DB2 application and DB connections..."
    db2 force application all
    sleep 10
    echo "Deactivating Data Base..."
    db2set -null DB2COMM
    db2 deactivate database BLUDB
    sleep 5
    echo "Stopping Data Base..."
    db2stop force
    sleep 10
    echo "Restoring connection to Data Base..."
    db2set DB2COMM=TCPIP,SSL
    sleep 5
    echo "Starting Data Base service..."
    db2start
    sleep 10
EOF
}

function check_environment()
{
    /usr/bin/echo "Checking current Discover environment..."
    expected_env=$1
    oc version 2&>1 /dev/null
    (($?)) && current_env=OVA || current_env=OCP
    [[ "${expected_env}" == "${current_env}" ]] && return 0 || /usr/bin/echo -e "ERROR: Not Spectrum Discover OCP environment.\nACTION: ${DM_ACTION} not permited on current environment.\nExiting..." && exit 1;

}

function backup_db()
{
    echo "STARTING UP THE DATABASE BACKUP, THIS MIGHT TAKE A WHILE..."
    docker exec -i --user db2inst1 Db2wh bash <<EOF
        /usr/bin/mkdir -p ${DM_DATA_PATH}/${DM_TAR_NAME}
        (($?)) && /usr/bin/echo "Cannot create working directory on given path: ${DM_DATA_PATH}/${DM_TAR_NAME}" && exit 1;
        cd ${DM_DATA_PATH}/${DM_TAR_NAME}
        /mnt/blumeta0/home/db2inst1/sqllib/bin/db2move BLUDB export -sn bluadmin -tn ACES,ACESLOADBASE,ACESMAP,ACESMAPLOADBASE,ACOG,ACOGLOADBASE,ACOGMAP,ACOGMAPLOADBASE,AGENTS,APPLICATIONCATALOG,BUCKETS,CONNECTIONS,DATABASECHANGELOG,DATABASECHANGELOGLOCK,DUPLICATES,METAOCEAN,METAOCEAN_QUOTA,POLICY,POLICYHISTORY,QUICKQUERY,REGEX,REPORTS,SCANHISTORY,TAGS
        (($?)) && /usr/bin/echo "Cannot create backup! Please check you have enough space to create backup." && exit 1;
        cd ${DM_DATA_PATH}
        /usr/bin/tar cvfz ${DM_TAR_NAME}.tar.gz ${DM_TAR_NAME}/
        (($?)) && /usr/bin/echo "Error creating the tarball: ${DM_TAR_NAME}.tar.gz" && exit 1;
        /usr/bin/echo "Backup tarball created!"
        /usr/bin/echo "Tarball path: ${DM_DATA_PATH}/${DM_TAR_NAME}.tar.gz"
EOF
        /usr/bin/echo "Trying to copy the tarball from the container to the current path..."
        /usr/bin/docker cp Db2wh:${DM_DATA_PATH}/${DM_TAR_NAME}.tar.gz .
        (($?)) && /usr/bin/echo "Error copying Db2wh:${DM_DATA_PATH}/${DM_TAR_NAME}.tar.gz to current directory. Please try to access the container and copy the tarball to a secure location." && exit 1;
}

function restore_db()
{
    echo "STARTING UP THE DATABASE RESTORE, THIS MIGHT TAKE A WHILE..."
    headPodName=$(oc -n spectrum-discover get po --selector name=dashmpp-head-0|grep spectrum-discover|awk '{print $1}')
    oc cp ${DM_TAR_NAME}.tar.gz ${headPodName}:${DM_DATA_PATH}
    (($?)) && /usr/bin/echo "ERROR: Error copying the tarball: ${DM_TAR_NAME}.tar.gz to pod's path. Please check the paths you have defined, make sure tarball exists on current location and make sure there's no space constraints." && exit 1;
    sleep 6
    oc -n spectrum-discover exec -i ${headPodName} -- bash <<EOF
    su db2inst1 -
    cd ${DM_DATA_PATH}
    echo "Extracting tarball data..."
    /usr/bin/tar xfvz ${DM_TAR_NAME}.tar.gz
    (($?)) && /usr/bin/echo "ERROR while extracting tarball data." && exit 1;
    sleep 6
    /usr/bin/chmod -R 777 ${DM_TAR_NAME}
    cd ${DM_TAR_NAME}
    sleep 6
    /mnt/blumeta0/home/db2inst1/sqllib/bin/db2move BLUDB import -io INSERT -l ${DM_DATA_PATH}/${DM_TAR_NAME}/ 
    (($?)) && /usr/bin/echo "Error has occured during the restore! Please check your current storage space. Otherwise, please contact Spectrum Discover Support." && exit 1;
EOF

}

env_vars="DM_ACTION DM_DATA_PATH DM_TAR_NAME"
for var in $(echo $env_vars); do
        check_var ${var};
done

if [ ${DM_ACTION} == "BACKUP" ]
then
    check_environment "OVA"
    restart_db "docker exec -i" "Db2wh"
    backup_db
    echo "DONE: Database backed up on tarball -> ${DM_TAR_NAME}.tar.gz on current directory $(pwd)!"

elif [ ${DM_ACTION} == "RESTORE" ]
then
    check_environment "OCP"
    headPodName=$(oc -n spectrum-discover get po --selector name=dashmpp-head-0|grep spectrum-discover|awk '{print $1}')
    restart_db "oc exec -i" "${headPodName} --"
    restore_db
    echo "DONE: Database restored. Data migration complete!"
else
        echo "No valid ACTION specified"
        exit 1
fi
