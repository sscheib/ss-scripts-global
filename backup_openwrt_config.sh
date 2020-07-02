#!/bin/bash

###
# Description:
#   This script is used to create a backup of all configured files from openwrt using sysupgrade --backup
#  
# Exit codes:
#   0: Backup was created successfully and notification mail send successfully as well
#   1: Unable to source zbx_script_monitoring.sh
#   2: Initialization of this script (openwrtConfigurationBackup::init) failed
#   3: Configuration Backup failed
#   4: Unable to send status email
#
# log file                                      : yes, by default /var/log/openwrt_configuration_backup.log
# logrotate                                     : yes, provided with the _setup script
# zabbix script monitoring integration
#  - exit and error codes                       : yes, traps in zbx_script_monitoring.sh
#  - runtime errors                             : yes, included within this script
# log file monitoring                           : yes, monitored from Zabbix   
#
# Author:
# Steffen Scheib (steffen@scheib.me)
#
# Legend:
# + New
# - Bugfix
# ~ Change
# . Various
#
# Changelog:
# 26.01.2020: . Initial

# version: 1.0
VERSION=1.0

# source Zabbix script monitoring 
source zbx_script_monitoring.sh &> /dev/null || {
  echo "ERROR: Unable to source zbx_script_monitoring.sh";
  exit 1;
};
zbx::scriptMonitoring::init::default

# exit immediatly if a command fails
set -e
# let the whole pipe fail (exit with != 0) if a command in it fails
set -o pipefail

# path of the smb share
declare -r __SHARE_PATH="/backup"
# regex to check if the share path is available
declare -r __SHARE_PATH_REGEX="synology-ds918\.(home|office)\.int\.scheib\.me.*${__SHARE_PATH}"
# get both hostname and domain from uci 
declare -r __HOSTNAME="$(echo "$(uci -q get system.@system[0].hostname)"."$(uci -q get dhcp.@dnsmasq[0].domain)" | awk '{print tolower($0)}')"
# stores the message in the mail
declare __MESSAGE=""
# initially set the hostname as subject (to append the rest later)
declare __SUBJECT="${__HOSTNAME}: "
# log file for this script
declare -r __LOG_FILE="/var/log/$(basename "${0}" | sed 's/\.sh$//').log"
# required binaries by this script
declare -ar __REQUIRED_BINARIES=(
  "sysupgrade"
  "uci"
  "mailsend"
)

###
# function openwrtConfigurationBackup::print
#---
# Description:
#---
# Writes the given message to stdout if in an interactive shell. The messages is additionally written to 
# __LOG_FILE in any case.
#---
# Arguments:
#---
#   #   | name                                   | type        | description
#-------+----------------------------------------+-------------+-------------------------------------------------------< 
#<  $1> | message                                | string      | Message to print/write
#[  $2] | level                                  | string      | Message-"Level" - simple prefix (ERROR, WARNING, INFO, 
#       |                                        |             | DEBUG, etc)
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __LOG_FILE                                    | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | Will always return 0
#####
function openwrtConfigurationBackup::print () {
  declare message="${1}"

  # if no message level is given, UNDEF will be used instead
  declare level="UNDEF"
  [[ -z "${2}" ]] || {
    level="${2}"
  };

  declare formattedMsg="$(printf "[%s] %s: %-36s: %-7s> %s\n" "$(date +'%d.%m.%y - %H:%M:%S')" "$(basename "${0}")" "${FUNCNAME[1]}" "${level}" "${message}")"
  # looks like: [02.01.20 - 17:52:51] upload_logs_gdrive.sh: main                     : INFO   > my message here

  # send the message to Zabbix in any case
  zbx::scriptMonitoring::send "${0}" "${formattedMsg}" "runtimeMessage"

  # if we are in an interactive session, we print the msg to stdout
  [[ ! -t 1 ]] || {
    echo "${formattedMsg}";
  };

  # if we have no access to the __LOG_FILE file and are not root (uid=0), we can stop here
  ( [[ -w "${__LOG_FILE}" ]] ||
    [[ "$(id)" =~ ^uid=0 ]]
  ) || {
    return 0;
  };

  # finally print the message to the logfile
  echo "${formattedMsg}" >> "${__LOG_FILE}"

  return 0;
}; # function openwrtConfigurationBackup::print ( <message> [level] )

###
# function openwrtConfigurationBackup::init
#---
# Description:
#---
# Checks if all requirements to run this script are given.
#---
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#  none
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __REQUIRED_BINARIES                           | read        | --
#   02 | __MESSAGE                                     | write       | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | If all conditions to run this script are met
# (return)   1 | If one or more binaries defined in __REQUIRED_BINARIES are missing
#####
function openwrtConfigurationBackup::init () {
  for binary in "${__REQUIRED_BINARIES[@]}"; do
      command -v "${binary}" &> /dev/null || {
      msg="Binary '${binary}' is not installed, but required by this script!";
      __MESSAGE="${msg}";
      openwrtConfigurationBackup::print "${msg}" "ERROR";
      return 1; 
    };
  done

  return 0;
}; # function openwrtConfigurationBackup::init ( )

###
# function openwrtConfigurationBackup::create
#---
# Description:
#---
# Creates a folder within __SHARE_PATH in the format __SHARE_PATH/<YEAR>/<MONTH> (if it does not exist already) 
# and writes a backup to the created folder in the format <HOSTNAME>.<DOMAIN>_<YEAR>-<MONTH>-<DAY> using sysupgrade
#---
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#  none
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __SHARE_PATH_REGEX                            | read        | --
#   02 | __SHARE_PATH                                  | read        | --
#   03 | __MESSAGE                                     | write       | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | If everything went fine
# (return)   1 | If share is not mounted
# (return)   2 | If unable to create a folder to write the backup to within __SHARE_PATH
# (return)   3 | If the sysupgrade command (which creates a backup) failes
#####
function openwrtConfigurationBackup::create () {
  openwrtConfigurationBackup::print "Checking if share is mounted .." "INFO"
  mount | grep -Eq "${__SHARE_PATH_REGEX}" &> /dev/null || {
    declare msg="Share is not mounted!";
    openwrtConfigurationBackup::print "${msg}" "ERROR";
    __MESSAGE="${msg}";
    return 1;
  };
  openwrtConfigurationBackup::print "Share is mounted" "INFO"

  declare destination="${__SHARE_PATH}/$(date +'%Y')/$(date +'%m')"
  openwrtConfigurationBackup::print "Checking if folder '${destination}' exists .." "INFO"
  [[ -d "${destination}" ]] || {
    openwrtConfigurationBackup::print "Folder '${destination}' does not exist, creating it .." "INFO";
    mkdir -p "${destination}" || {
      declare msg="Creating directory '${destination}' failed!":
      openwrtConfigurationBackup::print "${msg}" "ERROR";
      __MESSAGE="${msg}";
      return 2;
    };
  };
  openwrtConfigurationBackup::print "Folder '${destination}' existed or was successfully created" "INFO"
  
  declare archivePath="${destination}/"$( echo "$(uci -q get system.@system[0].hostname)"."$(/sbin/uci -q get dhcp.@dnsmasq[0].domain)" | awk '{print tolower($0)}')"_"$(date +%Y-%m-%d)".tar.gz"
  openwrtConfigurationBackup::print "Saving configuration to '${archivePath}' .." "INFO";
  /sbin/sysupgrade --create-backup "${archivePath}" &> /dev/null || {
    declare msg="Creating configuration backup to '${archivePath}' failed!";
    openwrtConfigurationBackup::print "${msg}" "ERROR";
    __MESSAGE="${msg}";
    return 3;
  };
  openwrtConfigurationBackup::print "Configuration successfully saved to '${archivePath}'" "INFO"

  return 0;
} #; function openwrtConfigurationBackup::create ( )

###
# function openwrtConfigurationBackup::send_email
#---
# Description:
#---
# Send an email to automatic@cron.email, first trying to use mail.pve.ext.scheib.me (VPN DNS), otherwise try using 
# cron.email on port 25 as SMTP server. The sender name is backup@<HOSTNAME>.<DOMAIN>
#---
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#  none
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __MESSAGE                                     | read        | --
#   02 | __HOSTNAME                                    | read        | --
#   03 | __SUBJECT                                     | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | If everything went fine
# (return)   1 | If unable to send email
#####
function openwrtConfigurationBackup::send_email () {
  openwrtConfigurationBackup::print "Sending notification mail .." "INFO"
  echo "${__MESSAGE}" | mailsend -smtp mail.pve.ext.scheib.me -port 25 -t automatic@cron.email -f backup@"${__HOSTNAME}" -sub "${__SUBJECT}" -starttls || {
    openwrtConfigurationBackup::print "Sending notificaiton mail via 'mail.pve.ext.scheib.me' (VPN) failed, trying public DNS name 'cron.email'" "WARNING";
    echo "${__MESSAGE}" | mailsend -smtp cron.email -port 25 -t automatic@cron.email -f backup@"${__HOSTNAME}" -sub "${__SUBJECT}" -starttls || {
      openwrtConfigurationBackup::print "Sending notification mail via 'cron.mail' failed!" "ERROR";
      return 1;
    };
  };
  openwrtConfigurationBackup::print "Successfully sent notification mail" "INFO"

  return 0;
} #; function openwrtConfigurationBackupsend_mail ( )

declare -i returnCode=-1
openwrtConfigurationBackup::print "Initializing the script .." "INFO"
openwrtConfigurationBackup::init
returnCode="${?}"
[[ "${returnCode}" -eq 0 ]] || {
  openwrtConfigurationBackup::print "Initialization failed!" "ERROR";
  __SUBJECT+="Configuration backup failed";
  openwrtConfigurationBackup::send_email;
  returnCode="${?}";
  [[ "${returnCode}" -eq 0 ]] || {
    openwrtConfigurationBackup::print "Sending status email failed!" "ERROR";
    exit 4;
  };
  exit 2;
};
openwrtConfigurationBackup::print "Initialization successful." "INFO"

openwrtConfigurationBackup::print "Creating backup .." "INFO"
openwrtConfigurationBackup::create
returnCode="${?}"
[[ "${returnCode}" -eq 0 ]] || {
  openwrtConfigurationBackup::print "Creating backup failed!" "ERROR";
  __SUBJECT+="Configuration backup failed";
  openwrtConfigurationBackup::send_email;
  returnCode="${?}";
  [[ "${returnCode}" -eq 0 ]] || {
    openwrtConfigurationBackup::print "Sending status email failed!" "ERROR";
    exit 4;
  };
  exit 3;
};
openwrtConfigurationBackup::print "Backup creation successful." "INFO"

__MESSAGE="Backup of configuration files was successful."
__SUBJECT+="Configuration backup successful"
openwrtConfigurationBackup::print "Sending status email .." "INFO"
openwrtConfigurationBackup::send_email
returnCode="${?}";
[[ "${returnCode}" -eq 0 ]] || {
  openwrtConfigurationBackup::print "Sending status email failed!" "ERROR";
  exit 4;
};
openwrtConfigurationBackup::print "Mail sending successful" "INFO"

exit 0;
#EOF
