"""Backup & restore script"""
# -*- coding: utf-8 -*-################################### {COPYRIGHT-TOP} ###
# Licensed Materials - Property of IBM
# 5737-I32
#
# (C) Copyright IBM Corp. 2023
#
# US Government Users Restricted Rights - Use, duplication, or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# ######################################################### {COPYRIGHT-END} ###
#pylint: disable=line-too-long
import sys
import os
import time
import datetime
import subprocess
import base64
import logging
import logging.config

#Logger start
LOG_FORMAT = '[%(asctime)s] - [%(name)s][%(levelname)s] - %(message)s'
logging.basicConfig(format=LOG_FORMAT)
logging.root.setLevel(logging.DEBUG)
logger = logging.getLogger('Backup_Restore')
#  logger.addHandler(logging.FileHandler('Backup_Restore.log'))
#Environment Variables and parameters to use
namespace = os.environ.get('project_name','ibm-data-cataloging')
db2User = os.environ.get('DB2_USER','bluadmin')


def main():
    """Main function of the Backup and Restore DB2 for DataCataloging 
    """
    logger.info("========Backup and Restore Data Cataloging Utility========")
    logger.info("checking if Openshift console is installed")
    run_command("oc")
    logger.info("We will use '%s' cluster namespace",namespace)
    logger.info("if you need other dcs namespace exit and export env variable with")
    logger.info("export project_name=your_project_namespace")
    logger.info("before running this script and keep oc logged")

    while True:
        print("1) Backup")
        print("2) Restore")
        print("3) StopDB2")
        print("4) StartDB2")
        print("5) Exit")
        action = input("Enter a number to start:")
        if action == '1':
            backup_db2()
            logger.info("Please wait a couple of minutes to let all pods run correctly")
            break
        if action == '2':
            restore_db2()
            logger.info("Please wait a couple of minutes to let all pods run correctly")
            logger.info("NOTE: To see the discover records, you'll need to refresh summary table database")
            logger.info("DCS-UI Dataconnections ---> Discover Databases ----> Metadata Summarization Table ----> Run table refresh")
            break
        if action == '3':
            logger.info("Getting db2 Pod")
            head_pod_name=f"oc -n {namespace} get pod --selector name=dashmpp-head-0 --no-headers"
            db2_pod=run_command(head_pod_name).split()[0]
            shutdown_db2(db2_pod)
            break
        if action == '4':
            logger.info("Getting db2 Pod")
            head_pod_name=f"oc -n {namespace} get pod --selector name=dashmpp-head-0 --no-headers"
            db2_pod=run_command(head_pod_name).split()[0]
            start_db2(db2_pod)
            break
        if action == '5':
            break
    logger.info("DONE")
    sys.exit(0)



def backup_db2():
    """backup code that will create a tar file inside dcs-bak directory"""
    logger.info("Getting db2 Pod")
    head_pod_name=f"oc -n {namespace} get pod --selector name=dashmpp-head-0 --no-headers"
    db2_pod=run_command(head_pod_name).split()[0]
    logger.info("Getting db2 bluadmin Password")
    cmd = f"oc -n {namespace} get secrets c-isd-ldapblueadminpassword -o go-template --template={{{{.data.password}}}}"
    db2_pass = base64.b64decode(run_command(cmd)).decode("ascii")
    #scale the pods down
    scale_pods('down')
    shutdown_db2(db2_pod)
    logger.info("====START DB2 BACKUP====")
    logger.info("Create backup dir")
    cmd = f"oc -n {namespace} exec {db2_pod} -- /usr/bin/mkdir -p /mnt/blumeta0/dcs-bak"
    run_command(cmd)
    cmd = f"oc -n {namespace} exec {db2_pod} -- sudo chown db2inst1 /mnt/blumeta0/dcs-bak/"
    run_command(cmd)
    logger.info("Create backup in pod directory")
    cmd = f"oc -n {namespace} exec {db2_pod} -- su - db2inst1 'db2 connect to BLUDB user {db2User} using {db2_pass} && cd /mnt/blumeta0/dcs-bak && /mnt/blumeta0/home/db2inst1/sqllib/bin/db2move BLUDB export -sn bluadmin -tn ACES,ACESLOADBASE,ACESMAP,ACESMAPLOADBASE,ACOG,ACOGLOADBASE,ACOGMAP,ACOGMAPLOADBASE,AGENTS,APPLICATIONCATALOG,BUCKETS,CONNECTIONS,DATABASECHANGELOG,DATABASECHANGELOGLOCK,DUPLICATES,METAOCEAN,METAOCEAN_QUOTA,POLICY,POLICYHISTORY,QUICKQUERY,REGEX,REPORTS,SCANHISTORY,TAGS'"
    run_command(cmd)
    logger.info("Compressing and return the backup file")
    timestamp=datetime.datetime.now().strftime("%m%d%Y_%H%M%S")
    cmd = f"oc -n {namespace} exec {db2_pod} -- su - db2inst1 'cd /mnt/blumeta0 && /usr/bin/tar cvfz dcs_Backup_{timestamp}.tar.gz dcs-bak/'"
    run_command(cmd)
    cmd = f"oc cp -n {namespace} {db2_pod}:/mnt/blumeta0/dcs_Backup_{timestamp}.tar.gz ./dcs-Backups/dcs_Backup_{timestamp}.tar.gz"
    run_command(cmd)
    logger.info("Backup saved as dcs_Backup_%s.tar.gz", db2_pod)
    logger.info("Cleaning backup files from the pod")
    cmd = f"oc exec -it -n {namespace} {db2_pod} -- su - db2inst1 -c 'rm -rf /mnt/blumeta0/dcs-bak'"
    run_command(cmd)
    cmd = f"oc exec -it -n {namespace} {db2_pod} -- su - db2inst1 -c 'rm /mnt/blumeta0/dcs_Backup_{timestamp}.tar.gz'"
    run_command(cmd)

    start_db2(db2_pod)

    scale_pods('up')

    logger.info("Database Backup done, saved in ./dcs-Backups/dcs_Backup_%s.tar.gz",timestamp)


def restore_db2():
    """Restore function that will pull the tar from the local dcs-bak directory
    then replace the db2 database with this"""
    pak = select_backup()
    if not pak:
        return
    logger.info("Will restore from file: %s",pak)
    time.sleep(2)
    logger.info("Getting db2 Pod")
    head_pod_name=f"oc -n {namespace} get pod --selector name=dashmpp-head-0 --no-headers"
    db2_pod=run_command(head_pod_name).split()[0]
    logger.info("Getting db2 bluadmin Password")
    cmd = f"oc -n {namespace} get secrets c-isd-ldapblueadminpassword -o go-template --template={{{{.data.password}}}}"
    db2_pass = base64.b64decode(run_command(cmd)).decode("ascii")
    #scale the pods down
    logger.info("Copying tar file to pod and extract")
    cmd = f"oc cp -n {namespace} ./dcs-Backups/{pak} {db2_pod}:/mnt/blumeta0/{pak}"
    run_command(cmd)
    cmd = f"oc -n {namespace} exec {db2_pod} -- su - db2inst1 -c '/usr/bin/tar xvfz /mnt/blumeta0/{pak} -C /mnt/blumeta0/' "
    run_command(cmd)
    cmd = f"oc -n {namespace} exec {db2_pod} -- su - db2inst1 -c 'chmod -R 777 /mnt/blumeta0/dcs-bak/'"
    logger.info("====Prepare db2 to import backup====")
    scale_pods('down')
    shutdown_db2(db2_pod)
    #  clean_db2(db2_pod,db2_pass)
    logger.info("====Import tables from backup====")
    cmd = f"oc -n {namespace} exec {db2_pod} -- su - db2inst1 -c 'db2 connect to BLUDB user {db2User} using {db2_pass} && cd /mnt/blumeta0/dcs-bak && /mnt/blumeta0/home/db2inst1/sqllib/bin/db2move BLUDB import -u {db2User} -p {db2_pass} -io REPLACE -l /mnt/blumeta0/dcs-bak/ '"
    run_command(cmd)
    time.sleep(10)
    logger.info("====Tables imported, cleaning backup files====")
    cmd = f"oc -n {namespace} exec {db2_pod} -- su - db2inst1 -c 'rm -rf /mnt/blumeta0/dcs-bak'"
    run_command(cmd)
    cmd = f"oc -n {namespace} exec {db2_pod} -- su - db2inst1 -c 'rm /mnt/blumeta0/{pak}'"
    run_command(cmd)

    logger.info("====start db2 and pods up====")
    start_db2(db2_pod)
    scale_pods('up')


def shutdown_db2(db2_pod):
    """Function to shutdown db2 then start in 'maintenance' mode
    This run one by one then pause for 20s as db2 needs time to apply changes
    """
    logger.info("Shutdown db2 database")
    db2commands=[
        "sudo wvcli system disable -m 'Disable HA before Db2 maintenance'",
        #  "db2 list applications",
        "db2 force application all",
        "db2 terminate",
        "db2stop",
        "ipclean -a",
        "db2set -null DB2COMM",
        "db2start admin mode restricted access",
    ]
    for db2cmd in db2commands:
        cmd=f'oc exec -it -n {namespace} {db2_pod} -- su - db2inst1 -c "{db2cmd}"'
        run_command(cmd)
        time.sleep(20)

def start_db2(db2_pod):
    """Function to shutdown db2 and recover normal state
    This run one by one then pause for 20s as db2 needs time to apply changes"""
    logger.info("Start db2 database")
    db2commands=[
        "db2stop",
        "ipclean -a",
        "db2set DB2COMM=TCPIP,SSL",
        "db2start",
        "db2 activate db bludb",
        "sudo wvcli system enable -m 'Enable HA after Db2 maintenance'",
    ]
    for db2cmd in db2commands:
        cmd=f'oc exec -it -n {namespace} {db2_pod} -- su - db2inst1 -c "{db2cmd}"'
        run_command(cmd)
        time.sleep(20)

def clean_db2(db2_pod,db2_pass):
    """Clean DB2 Tables: Not stable function for now. This might be deleted"""
    logger.info("====Cleaning Database====")
    tables=["ACES",
            "ACESLOADBASE",
            "ACESMAP", 
            "ACESMAPLOADBASE",
            "ACOG",
            "ACOGLOADBASE",
            "ACOGMAP",
            "ACOGMAPLOADBASE",
            "AGENTS",
            "APPLICATIONCATALOG",
            "BUCKETS",
            "CONNECTIONS",
            "DATABASECHANGELOG",
            "DATABASECHANGELOGLOCK",
            "DUPLICATES",
            "METAOCEAN",
            "METAOCEAN_QUOTA",
            "POLICY",
            "POLICYHISTORY",
            "QUICKQUERY",
            "REGEX",
            "REPORTS",
            "SCANHISTORY",
            "TAGS"]
    for table in tables:
        cmd =f"oc -n {namespace} exec {db2_pod} -- su - db2inst1 -c 'db2 connect to BLUDB user {db2User} using {db2_pass} && db2 delete from bluadmin.{table}'"
        run_command(cmd)
        time.sleep(2)
def select_backup():
    """Simple menu to select the tar file from dcs-Backup local directory"""
    if not os.path.exists('dcs-Backups'):
        logger.error("No backup has been done yet or directory dcs-Backups is missing!!!")
        return False
    if not any('.tar.gz' in file for file in os.listdir('dcs-Backups')):
        logger.error("No tar files found in dcs-Backups folder!!!")
        return False
    cmd = "cd dcs-Backups/ && ls *tar.gz && cd .."
    backup_list=run_command(cmd).split()
    print("Backup list")
    count=1
    for package in backup_list:
        print(f"{count}){package}")
        count+=1
    while True:
        try:
            action=int(input("Select Backup to restore:"))-1
            if action < 0: 
                raise IndexError
            logger.info(f"Selected {backup_list[action]}")
            break
        except ValueError:
            logger.error("Enter a Valid number")
        except IndexError:
            logger.error("File number does not exists")
    return backup_list[action]

def scale_pods(action='up'):
    """Function to scale DCS pods for maintenance"""
    logger.info("====Scaling pods %s====",action)
    replicas= 1 if action=='up' else 0
    cmd =f'oc -n {namespace} scale --replicas={replicas} deployment,statefulset -l component=discover'
    run_command(cmd)
    if replicas == 1:
        logger.info("====Scale consumer pods====")
        consumer_pods=['ceph-le',
                        'cos-le',
                        'cos-scan',
                        'file-scan',
                        'protect-scan',
                        'scale-le',
                        'scale-scan']
        logger.info("====Wait 60s to let pods finish====")
        time.sleep(60)
        for pod in consumer_pods:
            cmd = f'oc -n {namespace} scale --replicas=10 deployment isd-consumer-{pod}'
            run_command(cmd)
    else:
        logger.info("====Wait 60s to let pods finish====")
        time.sleep(60)

def run_command (cmd):
    """Command shell runner"""
    logger.debug("running command: %s",cmd)
    try:
        process = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True
        )
        output, error = process.communicate()
        if process.returncode in (0,3):
            return str(output.decode('UTF-8'))
        assert False, f"Error ocurred in command {cmd} over ssh. Error was {error.strip()} message: {str(output)} "
    except OSError as err:
        assert False, f"System error ocurred running command {cmd} over ssh. return code: {err.errno}, message:{err.strerror}"

if __name__ == "__main__":
    #start main function
    try:
        main()
    except KeyboardInterrupt:
        logger.info("Process cancelled by user")
