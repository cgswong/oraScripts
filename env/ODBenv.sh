#!/bin/sh
######################################################
# NAME: ODBenv.sh
#
# DESC: Configures environment for Oracle access as required.
#       The oraenv script must be accessible as it's used by this script.
#       The ORATAB file should also be accessible for alias setup.
#       The following are set within the environment:
#
#       ORACLE_SID
#       ORACLE_HOME
#       GRID_HOME or DB_HOME (if ASM or DB)
#       ORACLE_UNQNAME
#       PATH
#       LD_LIBRARY_PATH
#       ORACLE_BASE
#
# NOTE: Due to constraints of the shell in regard to environment
#       variables, the command MUST be prefaced with ".". If it
#       is not, then no permanent change in the user's environment
#       can take place.
#
# LOG:
# yyyy/mm/dd [user] - [notes]
# 2012/01/19 cgwong - Created initial version from oraenv, dbhome, and
#                     other reference scripts.
# 2013/01/15 cgwong - Included further DBA required variables
# 2013/02/08 cgwong - Eliminated redundant code
# 2014/01/17 cgwong - [v1.0.0] Added name and version to header.
#                   - Update some variables and set sudo to '-i' from '-s'
#                   - Added more aliases
# 2014/05/08 cgwong: [v1.0.1] Updated some statements.
# 2014/09/19 cgwong: [v2.0.0] Now leverage oraenv.
#                   - Removed SVN variables.
#                   - Further code cleanup.
######################################################

# -- VARIABLES -- #
# Set a few variables
ORAENV_ASK=NO ; export ORAENV_ASK
ORAENV=/usr/local/bin/oraenv
EGREP=/bin/egrep

# DBA variables
[ -d "/dbamaint" ] && DBA_BASE="/dbamaint"                ; export DBA_BASE
[ -d "${DBA_BASE}/bin"] && DBA_BIN="${DBA_BASE}/bin"      ; export DBA_BIN
[ -d "${DBA_BASE}/sql"] && DBA_SQL="${DBA_BASE}/sql"      ; export DBA_SQL
[ -d "${DBA_BASE}/rman"] && DBA_RMAN="${DBA_BASE}/rman"   ; export DBA_RMAN
[ -d "${DBA_BASE}/logs"] && DBA_LOG="${DBA_BASE}/logs"    ; export DBA_LOG
[ -d "${DBA_BASE}/exp"] && DBA_EXP="${DBA_BASE}/exp"      ; export DBA_EXP

# Script name variables
SCRIPT=`basename $0`                                # Script name without path

# --MAIN -- #
# Process command line arguments
ORASID=${ORACLE_SID:-NOTSET}   # ORACLE_SID was set, otherwise set to "NOTSET"
ORASID=${1:-$ORASID}           # ORACLE_SID was provided on the command line, otherwise reset based on previous

# Process ORASID to get matching ORAHOME from oratab
case "$ORASID" in
  NOTSET)     # ORACLE_SID not passed in and not in environment
    echo "ORACLE_SID is not set and was not passed as a command line argument."
    echo "Please set ORACLE_SID or pass a valid SID as a command line argument."
    echo "Usage: ${SCRIPT} [SID]"
    return ${RET_NOSID}
    ;;
  *)  # ORACLE_SID was set or provided on the command line
    . ${ORAENV} -s
    ;;
esac

# Set GRID_HOME if this is a Grid Infrastructure (ASM) ORACLE_HOME
# otherwise set DB_HOME for database ORACLE_HOME
if `echo ${ORACLE_SID} | ${EGREP} -q "ASM"` ; then
  GRID_HOME=${ORACLE_HOME} ; export GRID_HOME
  unset ORACLE_UNQNAME
else
  DB_HOME=${ORACLE_HOME} ; export DB_HOME
  ORACLE_UNQNAME=${ORACLE_UNQNAME:-$ORACLE_SID}; export ORACLE_UNQNAME
fi

# Some applications read the EDITOR variable to determine your favourite text editor.
# Determine if 'vim' is available and use instead of 'vi' (personal preference).
if [ -x '/usr/bin/vim' ]; then
  EDITOR="/usr/bin/vim"
else
  EDITOR="/usr/bin/vi"
fi
export EDITOR

# SQL script default locations
ORACLE_PATH=.
[ -d '~/sql' ] && ORACLE_PATH=${ORACLE_PATH}:.:~/sql
[ ! -z ${DBA_SQL} ] && ORACLE_PATH=${ORACLE_PATH}:${DBA_SQL}
export ORACLE_PATH

# Set prompt to include the SID
PS1="${USER}@${HOST}/${ORACLE_SID}:${PWD}> " ; export PS1

# -- ALIASES -- #
alias showenv='
echo "ORACLE_BASE: ${ORACLE_BASE} ${ORABASE_SET}"
echo "ORACLE_HOME: ${ORACLE_HOME}"
echo "ORACLE_SID: ${ORACLE_SID}"
echo "ORACLE_UNQNAME: ${ORACLE_UNQNAME}"
echo "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"
echo "PATH: ${PATH}"
'
alias so='sudo -H -u oracle -i'
alias sids=`awk 'BEGIN {printf "%-10s %-64s\n", "SID","HOME"}' ; awk 'BEGIN {printf "%-12s %-64s\n", "----------","----------------------------------------"}' ; cat /etc/oratab | egrep ":N|:Y" | egrep -v "\#|\*" | sort | awk -F: '{printf "%-10s %-64s\n", $1,$2}'`
alias oenv='echo "'$(egrep -v "(^#|^$)" /etc/oratab | awk -F: '\''{printf $1" "}'\'')"; . oraenv'
alias ss="${ORACLE_HOME}/bin/sqlplus '/ as sysdba'"

# -- END -- #