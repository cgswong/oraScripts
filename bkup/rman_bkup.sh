#!/bin/sh
###############################################################################################
# NAME: rman_bkup.sh                                                                          
# DESC: This RMAN backup script is for backing up both to disk and tape (via NetBackup).      
#       An optional parameter file can be used instead of command line parameters. The usage  
#       output should be reviewed for useful information on the options.                      
#                                                                                             
#       IMPORTANT: The script uses oraenv to set the oracle environment, which means that     
#                  all instances have to be listed in the oratab file with their correct home 
#                                                                                             
#
# LOG:
# yyyy/mm/dd [name]: [version]-[notes]
# 2014/08/27 cgwong: v0.1.0-Initial creation
###############################################################################################

# -- VARIABLES -- #
EXIT_SUCC=0     # Exit success code
EXIT_ERR=1      # Exit error code

# Recovery window size (in days)
RECOVER_WINDOW=7

# Set debug message level if not already set
# Valid values:
# 0: None (default)
# 1: Screen output
# 2: Log output
# 3: Screen & log output
DEBUG_LVL=${DEBUG_LVL:-0}

# -- FUNCTIONS -- #
msg ()
{ # Print message to screen and/or log file
  # Parameters:
  #   $1 - Output target [SCR (default) | LOG | BOTH]
  #   $2 - function name
  #   $3 - Message Type or status
  #   $4 - message
  #
  # Log format:
  #   Timestamp: [yyyy-mm-dd hh24:mi:ss]
  #   Component ID: [compID: ]
  #   Process ID (PID): [pid: ]
  #   Host: [hostID: ]
  #   User ID: [userID: ]
  #   Message Type (STATUS): [INFO | WARN | ERROR | DEBUG]
  #   Message Text: "Metadata Services: Metadata archive (MAR) not found."

  # Variables
  LOG_DT=`date "+%Y-%m-%d %H:%M:%S"`
  case $1 in      # Output choice
    "BOTH")       # Output to both screen and log
      echo -e "[${LOG_DT}];PRC: ${2};PID: ${PID};HOST: ${HOSTNAME};USER: ${USER};STATUS: ${3};MSG: ${4}" | tee -a ${LOGFILE}
    ;;
    "LOG")        # Only output to log
      echo -e "[${LOG_DT}];PRC: ${2};PID: ${PID};HOST: ${HOSTNAME};USER: ${USER};STATUS: ${3};MSG: ${4}" >> ${LOGFILE}
    ;;
    "SCR" | *)    # Output only to screen
      echo -e "[${LOG_DT}];PRC: ${2};PID: ${PID};HOST: ${HOSTNAME};USER: ${USER};STATUS: ${3};MSG: ${4}"
    ;;
  esac
}

debugmsg ()
{ # Print debug messages
  DMESG=$2

  case $1 in
    "1")
      msg "SCR" debugmsg DEBUG "${DMESG}"
    ;;
    "2")
      msg "LOG" debugmsg DEBUG "${DMESG}"
    ;;
    "3")
      msg "BOTH" debugmsg DEBUG "${DMESG}"
    ;;
  esac
}

show_usage ()
{ # Show script usage
  echo "
 ${SCRIPT} - Shell script to run RMAN backup to disk or take (via NetBackup).
             The parameter file, ${PARFILE}, is used in configuring
             the backup environment. The default parameter file should be 
             reviewed to understand the format and values. The below command
             line options are also available:

 USAGE
 ${SCRIPT} [OPTIONS]

 OPTIONS
  -b [ full | inc | arch | merged | maint | cold | d2t ]
    Type of backup to run. This is a mandatory option. Valid values are:
    
    full   - Full, level 0 online backup which is used as a base for further 
             incremental backups. All database blocks are backed up, as well 
             archived redo logs and a controlfile backup. The database must be
             archive log mode.
    inc    - Incremental differential (level 1) backup which captures changed blocks
             since the last incremental online backup. Ensure that Block Change 
             Tracking (BCT) is enabled for optimal performance when using this option.
             The database must be archive log mode.
    arch   - Archived redo log backups only. Note that the dynamic script will backup
             from a single archive log location relying on the archived redo log failover
             feature to ensure a complete backup even if some archiving destinations
             are missing logs or contain logs with corrupt data. Following a successful
             backup archived logs are removed from all locations, conforming to the 
             archived redo log policy. The database must be archive log mode.
    merged - A Merged Incremental backup is performed whereby the image backup is kept
             as current as the last such run. The database must be archive log mode.
    maint  - Perform maintenance operations such as crosschecking and removing files
             based on the recovery window. This is done after running all backups.
    cold   - Database is taken offline (in MOUNT status) and a full backup is performed.
    d2t    - Copy backup set from disk to tape.

  -d [0 | 1 | 2 | 3]
    Enable debugging. The environment variable DEBUG_LVL can also be used to
    set a valid debug level:
    
    0: No output (default)
    1: Screen output
    2: Log output
    3: Screen & log output    

  -f [FILE]
    Use alternate parameter file specified. The full path must be used. Review
    the default parameter file for the expected format when making your own
    custom parameter file.

  -l [ BKUP_DEST | sbt_tape ]
    The default backup destination is disk (${BKUP_DEST}). Use this parameter
    to specify an alternative backup destination. Either a disk location 
    (i.e. directory), or tape. The specific tape media management settings are
    taken from the parameter file. 
    
  -s {NAME}
    By default scripts are dynamically created for running backups. This parameter
    specifies that an RMAN catalog script should be used instead. The optional 
    NAME arugment runs the catalog script specified, otherwise the default
    naming convention is used to determine the script to be executed. The naming
    convention used is [hostname_sid_type] where type is [full | arch | inc | main].

  -t [TAG]
    A default tag for each backup is assigned based on certain backup criteria
    (such as mode and type). This parameter can be used to assign a custom tag instead.
    
  -h
    Display this help screen.
"
}

init ()
{ # Initialize by setting the configuration variables and environment
  FNC="init"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"

  PATH=/usr/local/bin:$PATH ; export PATH
  GREP=/bin/grep
  EGREP=/bin/egrep
  HOSTNAME=/bin/hostname
  SH=/bin/sh
  MAIL=/bin/mail
  NSLOOKUP=/usr/bin/nslookup
  PID=$$

  SCRIPT=`basename $0`                                # Script name without path
  SCRIPT_PATH=$(dirname $0)                           # Script path
  SCRIPT_NM=`echo $SCRIPT | awk -F"." '{print $1}'`   # Script name without any extension
  
  PARFILE=${PARFILE:-"${SCRIPT_PATH}/${SCRIPT_NM}.par"}     # Parameter file

  LOGDIR="/dbamaint/logs/bkup"                            # Log directory
  LOGFILE="${LOGDIR}/${SCRIPT_NM}.log"                    # Script log file

  ORACLE_USER=${ORACLE_USER:-oracle}                      # Oracle user
  ORAENV=${ORAENV:-"/usr/local/bin/oraenv"}               # Oracle environment file (assume Linux if not set).

  SENDLOG=${SENDLOG:-Y}                                   # Mail RMAN log flag (Y | N). Assume we send logs if not set.
  MAILTO=${MAILTO:-"support.dba@email.com"}            # Mail to field
  MAILFROM=${MAILFROM:-"${USER}@`${HOSTNAME} -f`"}        # Mail recipient

  debugmsg ${DEBUG_LVL} " PATH     : ${PATH}"
  debugmsg ${DEBUG_LVL} " LOGDIR   : ${LOGDIR}"
  debugmsg ${DEBUG_LVL} " LOGFILE  : ${LOGFILE}"
  debugmsg ${DEBUG_LVL} " ORAENV   : ${ORAENV}"
  debugmsg ${DEBUG_LVL} " MAILFROM : ${MAILFROM}"
  
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

bckCOMMON ()
{ # RMAN script used to set common RMAN (control file or catalog) settings.
  FNC="bckCOMMON"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"

  case ${ARCHIVELOG_DELETE_POLICY} in
    "applied" | "APPLIED")
      # Only deleted after being applied to all mandatory sites.
      # Using ALL would have specified all standbys, not just mandatory
      # This only works (in 11g+) if LOG_ARCHIVE_DEST_2 has been set
      # on a primary with the standby as a mandatory destination; otherwise an error is reported:
      # RMAN-08591: WARNING: invalid archived log deletion policy
      # WARNING: Changing a remote desitnation to mandatory means the primary shuts down if
      # it can't talk to the standby.
      LOG_DELETE_POLICY="CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON STANDBY;"
    ;;
    "shipped" | "SHIPPED")
      # Only deleted after being transferred to all mandatory sites.
      # Using ALL would have specified all standbys, not just mandatory
      # This only works (in 11g+) if LOG_ARCHIVE_DEST_2 has been set
      # on a primary with the standby as a mandatory destination; otherwise an error is reported:
      # RMAN-08591: WARNING: invalid archived log deletion policy
      # WARNING: Changing a remote desitnation to mandatory means the primary shuts down if
      # it can't talk to the standby.
      LOG_DELETE_POLICY="CONFIGURE ARCHIVELOG DELETION POLICY TO SHIPPED TO STANDBY;"
    ;;
    "disk" | "DISK")
      # Only deleted after being backed up once to disk.
      LOG_DELETE_POLICY="CONFIGURE ARCHIVELOG DELETION POLICY BACKED UP 1 TIMES TO DEVICE TYPE disk;"
    ;;
    "tape" | "TAPE")
      # Only deleted after being backed up once to tape.
      LOG_DELETE_POLICY="CONFIGURE ARCHIVELOG DELETION POLICY BACKED UP 1 TIMES TO DEVICE TYPE sbt;"
    ;;
    *)
      # Default deletion policy.
      LOG_DELETE_POLICY="CONFIGURE ARCHIVELOG DELETION POLICY TO NONE;"
    ;;
  esac
  if [ ${BKUP_DEST} != "sbt_tape" ]; then
    CTRLF_FORMAT="CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE disk TO '${BKUP_DEST}/%F';"
    CHANNEL_DISK_DEVICE="CONFIGURE CHANNEL DEVICE TYPE disk FORMAT '${BKUP_DEST}/%U_%t';"
    CHANNEL_TAPE_DEVICE=""
  else
    CTRLF_FORMAT=""
    CHANNEL_DISK_DEVICE=""
    CHANNEL_TAPE_DEVICE="CONFIGURE CHANNEL DEVICE TYPE sbt PARMS='SBT_LIBRARY=/usr/openv/netbackup/bin/libobk.so64 ENV=(NB_ORA_POLICY=${NB_ORA_POLICY}, NB_ORA_CLASS=${NB_ORA_CLASS}, NB_ORA_SERV=${NB_ORA_SERV})';"
  fi
  CMD_STR="${CMD_STR}
# Set backup retention policy using recovery window
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF ${RECOVER_WINDOW} DAYS;

${LOG_DELETE_POLICY}

# Skip backing up files for which there already exists
# a valid backup with the same checkpoint.
CONFIGURE BACKUP OPTIMIZATION ON;

# Enable CONTROLFILE AUTOBACKUP
# This is not necessary when using an RMAN Catalog.
CONFIGURE CONTROLFILE AUTOBACKUP ON;
${CTRLF_FORMAT}
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt TO '%F';

# Set SBT channel configuration
CONFIGURE DEVICE TYPE sbt PARALLELISM ${CHANNELS};
CONFIGURE CHANNEL DEVICE TYPE sbt FORMAT '%U_%t';
${CHANNEL_TAPE_DEVICE}

# Set DISK channel configuration
CONFIGURE DEVICE TYPE disk PARALLELISM ${CHANNELS};
${CHANNEL_DISK_DEVICE}

# Set the default channel to disk
CONFIGURE DEFAULT DEVICE TYPE TO disk;

# Output the configuration
SHOW ALL;
"
  debugmsg ${DEBUG_LVL} " CMD_STR: ${CMD_STR}"
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

bckHOT ()
{ # RMAN script used for hot/online backups.
  FNC="bckHOT"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"
  
  CMD_STR="${CMD_STR}
# 1. Backup the database plus archived redo logs and control file
# 2. Remove the archived redo logs after the backup
RUN
{ 
  BACKUP
    ${BKUP_OPTS}
    TAG ${BKUP_TAG}
    DATABASE 
      INCLUDE CURRENT CONTROLFILE
      PLUS ARCHIVELOG DELETE ALL INPUT
  ;
}
"
  debugmsg ${DEBUG_LVL} " CMD_STR: ${CMD_STR}"
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

bckD2T ()
{ # RMAN script used for copying backup sets from disk to tape.
  FNC="bckD2T"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"
  
  CMD_STR="${CMD_STR}
# Backup the BACKUPSETS from disk that are not already backed up
RUN
{ BACKUP
    BACKUPSET ALL
  ;
}
"
  debugmsg ${DEBUG_LVL} " CMD_STR: ${CMD_STR}"
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

bckMAINT ()
{ # RMAN script used for backup maintenance.
  FNC="bckMAINT"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"
 
  if [ ${BKUP_DEST} == "sbt_tape" ]; then
    SEND_CMD="SEND 'NB_ORA_CLIENT=${NB_ORA_CLIENT}';"
    DEVICE_TYPE="sbt_tape"
  else
    DEVICE_TYPE="disk"
  fi
  CMD_STR="${CMD_STR}
RUN
{
  ALLOCATE CHANNEL DEVICE TYPE ${DEVICE_TYPE};
  ${SEND_CMD}
  
  # Archived redo log maintenance
  CROSSCHECK ARCHIVELOG ALL;
  # Ensure ARCHIVELOG deletion policy is followed
  DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
  
  # Datafile maintenance
  CROSSCHECK BACKUP;
  DELETE NOPROMPT EXPIRED BACKUP;

  DELETE NOPROMPT OBSOLETE;
  RELEASE CHANNEL;
}
"
  debugmsg ${DEBUG_LVL} " CMD_STR: ${CMD_STR}"
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

bckCOLD ()
{ # RMAN script used for offline backups.
  FNC="bckCOLD"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"
  
  CMD_STR="${CMD_STR}
# Restart the DB in mount mode
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;

# Backup the database (not necessary to backup any archived redo logs)
RUN
{ 
  BACKUP
    ${BKUP_OPTS}
    TAG ${BKUP_TAG}
    DATABASE
      INCLUDE CURRENT CONTROLFILE
  ;
}

# Open the database again
SQL 'ALTER DATABASE OPEN';
"
  debugmsg ${DEBUG_LVL} " CMD_STR: ${CMD_STR}"
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

bckARCH ()
{ # RMAN script used for archived redo log backups.
  FNC="bckARCH"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"

  CMD_STR="${CMD_STR}
RUN
{ 
  BACKUP
    ${BKUP_OPTS}
    TAG ${BKUP_TAG}
    ARCHIVELOG ALL DELETE ALL INPUT
  ;
}
"
  debugmsg ${DEBUG_LVL} " CMD_STR: ${CMD_STR}"
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

bckMERGED ()
{ # RMAN script used for Merged Incremental backups.
  FNC="bckMERGED"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"

  CMD_STR="${CMD_STR}
# 1. Create a new level 1 incremental backup.
#    On first run this will be level 0 incremental
#    and then a level 1 incremental on subsequent days.
# 2. Roll forward last level 0 copy of database 
#    applying level 1 incremental backup taken previously.
RUN
{ 
  BACKUP
    ${BKUP_OPTS}
    INCREMENTAL LEVEL 1 
    FOR RECOVER OF COPY WITH TAG ${BKUP_TAG}
    DATABASE 
  ;
  RECOVER COPY OF DATABASE 
    WITH TAG ${BKUP_TAG}
  ;
}
"
  debugmsg ${DEBUG_LVL} " CMD_STR: ${CMD_STR}"
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

setBackupOptions ()
{ # Determine which RMAN options should be used.
  FNC="setBackupOptions"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"

  # Get RMAN options via command line options
  while getopts ":b:d:f:l:s:t:h" optval "$@"; do
    case $optval in
    "b") # Backup mode
      BKUP_TYPE=${OPTARG}
    ;;
    "d") # Debug level
      case ${OPTARG} in
        0 | 1 | 2 | 3)
          DEBUG_LVL=${OPTARG}
        ;;
        *)
          msg "BOTH" ${FNC} WARN "Invalid option with parameter -${OPTARG}"
          sleep 5         # Brief pause to read error before usage display and continuation
          show_usage
        ;;
      esac
    ;;
    "f") # Set alternate parameter file
      PARFILE="${OPTARG}"
    ;;
    "l") # Backup location/destination.
      BKUP_DEST="${OPTARG}"
    ;;
    "s") # Use RMAN catalog scripts instead of companion scripts
      if [ -z ${OPTARG} ]; then
        RCAT_SCRIPT="Y"
      else
        RCAT_SCRIPT=${OPTARG}
      fi
    ;;
    "t") # Backup tag to be applied.
      BKUP_TAG=${OPTARG}
    ;;
    "h") # Print help and exit
      show_usage
      exit ${EXIT_SUCC}
    ;;
    "\?") # Print help and exit
      echo "Invalid option -${OPTARG}"
      show_usage
      exit ${EXIT_ERR}
    ;;
    :)
      echo "Option -${OPTARG} requires an argument"
      show_usage
      exit ${EXIT_ERR}
    ;;
    *)
      echo "Invalid option with parameter -${OPTARG}"
      show_usage
      exit ${EXIT_ERR}
    ;;
    esac
  done
  shift $(($OPTIND -1))
  
  # Get RMAN options via the parameter file.
  . ${PARFILE}
  
  # Set some defaults if values are missing in parameter file.
  NB_ORA_SERV=${NB_ORA_SERV:-"na1000bmaprd01"}
  NB_ORA_CLASS=${NB_ORA_CLASS:-"Oracle_Hot"}
  CATALOG=${CATALOG:-"nocatalog"}
  CHANNELS=${CHANNELS:-1}
  BKUP_DEST=${BKUP_DEST:-"/dbamaint/bkups/files"}
  MAXOPENFILES=${MAXOPENFILES:-10}
  FILESPERSET=${FILESPERSET:-10}
  ARCHIVELOG_DELETE_POLICY=${ARCHIVELOG_DELETE_POLICY:default}
  
  debugmsg ${DEBUG_LVL} " NB_ORA_SERV  : ${NB_ORA_SERV}"
  debugmsg ${DEBUG_LVL} " NB_ORA_CLASS : ${NB_ORA_CLASS}"
  debugmsg ${DEBUG_LVL} " NB_ORA_POLICY: ${NB_ORA_POLICY}"
  debugmsg ${DEBUG_LVL} " ORACLE_SID   : ${ORACLE_SID}"
  debugmsg ${DEBUG_LVL} " TGT_CONN     : ${TGT_CONN}"
  debugmsg ${DEBUG_LVL} " CATALOG      : ${CATALOG}"
  debugmsg ${DEBUG_LVL} " BKUP_TYPE    : ${BKUP_TYPE}"
  debugmsg ${DEBUG_LVL} " BKUP_DEST    : ${BKUP_DEST}"
  debugmsg ${DEBUG_LVL} " ARCHIVELOG_DELETE_POLICY  : ${ARCHIVELOG_DELETE_POLICY}"
  debugmsg ${DEBUG_LVL} " CHANNELS     : ${CHANNELS}"
  debugmsg ${DEBUG_LVL} " MAXOPENFILES : ${MAXOPENFILES}"
  debugmsg ${DEBUG_LVL} " FILESPERSET  : ${FILESPERSET}"
  debugmsg ${DEBUG_LVL} " BLKSIZE      : ${BLKSIZE}"
  debugmsg ${DEBUG_LVL} " COMPRESSION  : ${COMPRESSION}"

  # Check if a RMAN catalog needs to be used
  if [ "$CATALOG" = "nocatalog" ]; then
    RCAT_CONN=""
  else
    RCAT_CONN="CONNECT CATALOG ${CATALOG}"
  fi

  # Construct the backup options and set the tag if not user defined
  FILE_DT=`date '+%Y%m%d%H%M%S'`
  case ${BKUP_TYPE} in
    "ARCH" | "arch" )       # Archive backup
      BKUP_TAG=${BKUP_TAG:-"ARCH"}     # Set TAG if not set
      BKUP_OPTS="${BKUP_OPTS} FILESPERSET ${FILESPERSET}"
    ;;
    "D2T" | "d2t" )         # Disk to tape copy
      BKUP_TAG=${BKUP_TAG:-"D2T"}      # Set TAG if not set
    ;;
    "FULL" | "full")        # Combine hot with level
      BKUP_TAG=${BKUP_TAG:-"HOT_L0"}   # Set TAG if not set
      BKUP_OPTS="${BKUP_OPTS} INCREMENTAL LEVEL 0 FILESPERSET ${FILESPERSET}"
    ;;
    "COLD" | "cold")        # Cold/offline backup
      BKUP_TAG=${BKUP_TAG:-"COLD"}     # Set TAG if not set
    ;;
    "INC" | "inc" )         # Incremental
      BKUP_TAG=${BKUP_TAG:-"INCD_L1"}   # Set TAG if not set
      BKUP_OPTS="${BKUP_OPTS} INCREMENTAL LEVEL 1 FILESPERSET ${FILESPERSET}"
    ;;
    "MERGED" | "merged" )   # Merged Incremental Backup
      BKUP_TAG=${BKUP_TAG:-"MERGED"}       # Set TAG if not set
      BKUP_OPTS="${BKUP_OPTS} FILESPERSET ${FILESPERSET}"
    ;;
  esac
  RMAN_LOG=${LOGDIR}/rman_${ORACLE_SID}_${BKUP_TYPE}-${FILE_DT}.log
  
  debugmsg ${DEBUG_LVL} " RCAT_CONN       : ${RCAT_CONN}"
  debugmsg ${DEBUG_LVL} " BKUP_TAG        : ${BKUP_TAG}"
  debugmsg ${DEBUG_LVL} " BKUP_OPTS       : ${BKUP_OPTS}"
  debugmsg ${DEBUG_LVL} " RMAN_LOG        : ${RMAN_LOG}"
  
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

checkRun ()
{ # Check if already running instance and shutdown. Otherwise create lock file.
  FNC="checkRun"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"
  
  # PID/Lock file to ensure only single backup for each ORACLE_SID is running
  # at any point in time. This file will need to be manually cleared
  # or forced execution specified in certain situations such as abnormal program
  # exit.
  LOCK_FILE="/tmp/${SCRIPT_NM}-${ORACLE_SID}.lck"
  if [ -f ${LOCK_FILE} ]; then
    debugmsg ${DEBUG_LVL} "Lock file ${LOCK_FILE} exists!"
    debugmsg ${DEBUG_LVL} "Running PID: `cat ${LOCK_FILE}`"
    exit ${EXIT_ERR}
  else
    echo ${PID} > ${LOCK_FILE}
    
    # Process RMAN log file
    touch ${RMAN_LOG}
    chmod 666 ${RMAN_LOG}
  fi
  debugmsg ${DEBUG_LVL} " PID       : ${PID}"  
  debugmsg ${DEBUG_LVL} " LOCK_FILE : ${LOCK_FILE}"  
  
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

setEnv ()
{ # Process command line options and set the environment.
  # The ORACLE_SID used in the oraenv script is set via the setBackupOptions routine
  FNC="setEnv"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"

  CUSER=`id |cut -d"(" -f2 | cut -d ")" -f1`
  ORAENV_ASK=NO ; export ORAENV_ASK
  . ${ORAENV} -s
  RMAN=${ORACLE_HOME}/bin/rman
  NLS_DATE_FORMAT='DD/MM/YYYY HH24:MI:SS' ; export NLS_DATE_FORMAT
  NB_ORA_CLIENT=${HOSTNAME}
  
  # Use NetBackup interface if available
  ${NSLOOKUP} ${ORACLE_SID}-b
  RSTAT=$?
  if [ ${RSTAT} ]; then
    NB_ORA_CLIENT="${ORACLE_SID}-b"
  else
    ${NSLOOKUP} ${HOSTNAME}-b
    RSTAT=$?
    if [ ${RSTAT} ]; then
      NB_ORA_CLIENT="${HOSTNAME}-b"
    else
      NB_ORA_CLIENT="${HOSTNAME}"
    fi
  fi
  export NB_ORA_CLIENT
  
  debugmsg ${DEBUG_LVL} " ORACLE_HOME  : ${ORACLE_HOME}"
  debugmsg ${DEBUG_LVL} " ORACLE_BASE  : ${ORACLE_BASE}"
  debugmsg ${DEBUG_LVL} " RMAN         : ${RMAN}"
  debugmsg ${DEBUG_LVL} " NB_ORA_CLIENT: ${NB_ORA_CLIENT}"

  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

printHeader ()
{ # Print header for RMAN log file
  FNC="printHeader"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"
  
  # Log script start
  PRT_DT=`date '+%Y/%m/%d-%H%M%S'`
  echo "*** SCRIPT: ${SCRIPT} | START: ${PRT_DT} ***" >> ${RMAN_LOG}

  # Log variables set by this script
  echo   "RMAN       : ${RMAN}"         >> ${RMAN_LOG}
  echo   "ORACLE_SID : ${ORACLE_SID}"   >> ${RMAN_LOG}
  echo   "ORACLE_USER: ${ORACLE_USER}"  >> ${RMAN_LOG}
  echo   "ORACLE_HOME: ${ORACLE_HOME}"  >> ${RMAN_LOG}
  echo >> ${RMAN_LOG}
  echo   "SCHEDULE            : ${SCHEDULE_NAME}" >> ${RMAN_LOG}
  echo   "BACKUP TYPE         : ${BKUP_TYPE}"     >> ${RMAN_LOG}
  echo   "PARALLELISM         : ${CHANNELS}"      >> ${RMAN_LOG}
  echo   "TAG                 : ${BKUP_TAG}"      >> ${RMAN_LOG}
  echo   "NB_ORA_SERV         : ${NB_ORA_SERV}"   >> ${RMAN_LOG}
  echo   "NB_ORA_CLASS        : ${NB_ORA_CLASS}"  >> ${RMAN_LOG}
  echo   "NB_ORA_POLICY       : ${NB_ORA_POLICY}" >> ${RMAN_LOG}
  echo   "NB_ORA_CLIENT       : ${NB_ORA_CLIENT}" >> ${RMAN_LOG}

  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

printFooter ()
{ # Print footer for RMAN log file
  FNC="printFooter"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"
  
  debugmsg ${DEBUG_LVL} " RSTAT: ${RSTAT}"
  PRT_DT=`date '+%Y/%m/%d-%H%M%S'`
  echo >> ${RMAN_LOG}
  if [ ${RSTAT} -eq 0 ]; then
    echo "*** END SUCCESS: ${PRT_DT} ***" >> ${RMAN_LOG}
  else
    echo "*** END ERROR: ${PRT_DT} ***"   >> ${RMAN_LOG}
  fi
  echo >> ${RMAN_LOG}

  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

runBackup ()
{ # Determine which command string should be created and execute it.
  # Also trap the exit code for further use.
  FNC="runBackup"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"

  # Create the correct command string
  CMD_STR="
    ORACLE_HOME=${ORACLE_HOME}  ; export ORACLE_HOME
    ORACLE_SID=${ORACLE_SID}    ; export ORACLE_SID
    NLS_DATE_FORMAT='DD/MM/YYYY HH24:MI:SS' ; export NLS_DATE_FORMAT

    ${RMAN} MSGLOG ${RMAN_LOG} APPEND << EOF
      CONNECT TARGET ${TGT_CONN}
      ${RCAT_CONN}
      SET ECHO ON
"
  bckCOMMON
  case ${BKUP_TYPE} in
    "FULL" | "full")
      debugmsg ${DEBUG_LVL} "Full HOT (online) backup."
      bckHOT
    ;;
    "COLD" | "cold")
      debugmsg ${DEBUG_LVL} "Full COLD (offline) backup."
      bckCOLD
    ;;
    "ARCH" | "arch")
      debugmsg ${DEBUG_LVL} "ARCH (online) backup."
      bckARCH
    ;;
    "INC" | "inc")
      debugmsg ${DEBUG_LVL} "INC (online) backup."
      bckDISK_HOT
    ;;
    "MERGED" | "merged")
      debugmsg ${DEBUG_LVL} "MERGED INCREMENTAL (online) backup."
      bckMERGED
    ;;
    "D2T" | "d2t")
      debugmsg ${DEBUG_LVL} "Backup backupsets to tape."
      bckDISK2TAPE
    ;;
    *)
      debugmsg ${DEBUG_LVL} "Invalid backup type."
      rm -f ${LOCK_FILE}
      exit ${EXIT_ERR}
    ;;
  esac

  # Complete command string creation
  CMD_STR="${CMD_STR}
EOF
"
  # Initiate the command string
  if [ "$CUSER" = "root" ]; then
    debugmsg ${DEBUG_LVL} "Switching to user ${ORACLE_USER} to run backup."
    su - $ORACLE_USER -c "${CMD_STR}"
    RSTAT=$?
    debugmsg ${DEBUG_LVL} "Result code: ${RSTAT}"
  else
    debugmsg ${DEBUG_LVL} "Running backup as user: ${ORACLE_USER}"
    $SH -c "${CMD_STR}"
    RSTAT=$?
    debugmsg ${DEBUG_LVL} "Result code: ${RSTAT}"
  fi
  
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

sendLog ()
{ # Mail the RMAN log file
  FNC="sendLog"
  debugmsg ${DEBUG_LVL} "Routine START: ${FNC}"
  
  # Check if the log file has to be mailed
  if [ "$SENDLOG" = "Y" ] || [ "$SENDLOG" = "y" ]; then
    debugmsg ${DEBUG_LVL} "Log sending enabled"
    # Construct the subject of the mail.
    PRT_DT=`date '+%Y/%m/%d-%H%M%S'`
    MAILSUBJ="RMAN ${ORACLE_SID} on ${HOSTNAME} - ${PRT_DT}"
    # Make distinction between successful and failed backups
    [ ${RSTAT} -ne 0 ] && MAILSUBJ="${MAILSUBJ} (FAIL)"

    # Send the mail
    debugmsg ${DEBUG_LVL} "MAILSUBJ : ${MAILSUBJ}"
    debugmsg ${DEBUG_LVL} "MAILTO   : ${MAILTO}"
    debugmsg ${DEBUG_LVL} "RMAN_LOG : ${RMAN_LOG}"
    mail -r ${MAILFROM} -s "${MAILSUBJ}" ${MAILTO} < ${RMAN_LOG}
  fi
 
  debugmsg ${DEBUG_LVL} "Route END: ${FNC}"
}

# -- MAIN -- #

# Main execution section
debugmsg ${DEBUG_LVL} "START: Main"
# Initialize script
init

# Get the backup options to be used from the parameter file and command line.
# Set the necessary variables. Note that the full command line MUST be passed to the
# function for correct command line processing
setBackupOptions "$@"

# Set the Oracle environment variables
setEnv

# Check for existing conflicting running instance
checkRun

# Set the header in the RMAN log file
printHeader

# Construct and run the RMAN command string.
# Output will be logged in the RMAN log file
runBackup

# Print the footer in the RMAN log file
printFooter

# Send the logfile
sendLog

# Exit with the RMAN result code, so NB knows if the backup succeeded or not
rm -f ${LOCK_FILE}
debugmsg ${DEBUG_LVL} "END: Main"
exit ${RSTAT}

# -- END -- #