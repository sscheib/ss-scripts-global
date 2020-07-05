#!/bin/bash

###
# Description:
#   This script is used to setup the log files and logrotate configurations for backup_openwrt_config.sh
#  
# Exit codes:
#   0: Setup of log files and logrotate configuration files has been done successfully
#   1: Setup of the log files could not be completed
#   2: Setup of the logrotate files could not be completed
#   3: logrotate configuration check (via logrotate -d) failed
#
# log file                                      : not necessary
# logrotate                                     : not necessary
# zabbix script monitoring integration
#  - exit and error codes                       : not necessary
#  - runtime errors                             : not necessary
# log file monitoring                           : not necessary
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
# 05.07.2020: . Initial

# version: 1.0
VERSION=1.0

# log files with permissions and owners to create and add to the logrotate file
# format:
# ["<logFilePath>"]="<user>:<group>,<chmod>,[logrotateConfigurationFilePath]"
# example:
# ["/var/log/openwrt_configuration_backup.log"]="root:root,0644,/etc/logrotate.d/openwrt_configuration_backup"
# ["/var/log/openwrt_access.log"]="root:root,0644"
# ^ in the last case no log rotate configuration is created - only the log file itself
# NOTE: If there are multiple entries with different log files, but the same logrotate configuration file defined
#       the last one processed will "win" - but will contain all logfiles. It is assumed, that if the same logrotate
#       configuration is defined, permissions and owner should be the same for all log files.
declare -Ar __DESTINATION_LOG_FILES=(
  ["/var/log/openwrt_configuration_backup.log"]="root:root,0644,/etc/logrotate.d/openwrt_configuration_backup"
)

###
# function write_output
#---
# Description:
#---
# Writes the given message to stdout.
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
# none
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | Will always return 0
#####
function write_output () {
  declare message="${1}"

  # if no message level is given, UNDEF will be used instead
  declare level="UNDEF"
  [[ -z "${2}" ]] || {
    level="${2}"
  };

  printf "[%s] %s: %-36s: %-7s> %s\n" "$(date +'%d.%m.%y - %H:%M:%S')" "$(basename "${0}")" "${FUNCNAME[1]}" "${level}" "${message}"

  return 0;
}; # function write_output ( <message> [level=UNDEF] )

###
# function setup_log_files
#---
# Description:
#---
# Creates the defined log files and sets the proper permissions
#---
# Arguments:
#---
#   #   | name                                   | type        | description
#-------+----------------------------------------+-------------+-------------------------------------------------------< 
#  none
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __DESTINATION_LOG_FILES                       | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | If everything went fine
# (return)   1 | If unable to touch the log file
# (return)   2 | If string in __DESTINATION_LOG_FILES malformatted
# (return)   3 | If invalid format for log file owner and group in __DESTINATION_LOG_FILES
# (return)   4 | If invalid format for log file permissions in __DESTINATION_LOG_FILES
# (return)   5 | If unable to chown the created log file to defined log file owner and group as defined in __DESTINATION_LOG_FILES
# (return)   6 | If unable to set the correct permissions to the log file as defined in __DESTINATION_LOG_FILES
#####
function setup_log_files () {
  for logFile in "${!__DESTINATION_LOG_FILES[@]}"; do
    write_output "Creating log file '${logFile}' .." "INFO";
    touch "${logFile}" &> /dev/null || {
      write_output "Unable to create log file '${logFile}'" "ERROR";
      return 1;
    };
    write_output "Created log file '${logFile}'" "INFO";

    write_output "Checking format for owner and permissions for '${logFile}' .."
    IFS="," read -ra logFileAttributes <<< "${__DESTINATION_LOG_FILES["${logFile}"]}"
    ( [[ "${#logFileAttributes[@]}" -eq 2 ]] || 
      [[ "${#logFileAttributes[@]}" -eq 3 ]] 
    ) || {
      write_output "Invalid format: '"${__DESTINATION_LOG_FILES["${logFile}"]}"'!" "ERROR";
      write_output "Supported format: <user>:<group>,<chmod octal permissions with 3 or 4 digits>,[optional path for the creation of a log rotate file]" "ERROR";
      write_output "Supported format: <user>.<group>,<chmod octal permissions with 3 or 4 digits>,[optional path for the creation of a log rotate file]" "ERROR";
      return 2;
    };

    logFileOwner="${logFileAttributes[0]}"
    logFilePermissions="${logFileAttributes[1]}"
    
    [[ "${logFileOwner}" =~ ^[[:alnum:]]+[:\.][[:alnum:]]+$ ]] || {
      write_output "Invalid format for log file owner: '${logFileOwner}'!" "ERROR";
      write_output "Supported formats: <user>:<group> and <user>.<group>" "ERROR";
      return 3;
    };

    [[ "${logFilePermissions}" =~ ^[0-7]{3,4}$ ]] || {
      write_output "Invalid format for log file permissions: '${logFilePermissions}'!" "ERROR";
      write_output "Supported formats: 3 digits (example 644) or 4 digits (example 0644)" "ERROR";
      return 4;
    };

    chown "${logFileOwner}" "${logFile}" &> /dev/null || {
      write_output "Unable to set owner to '${logFileOwner}' for log file '${logFile}'!" "ERROR";
      return 5;
    };

    chmod "${logFilePermissions}" "${logFile}" &> /dev/null || {
      write_output "Unable to set permissions to '${logFilePermissions}' for log file '${logFile}'!" "ERROR";
      return 6;
    };
    
    write_output "Successfully created log file '${logFile}', set owner to '${logFileOwner}' and set permissions to '${logFilePermissions}'." "INFO"
  done

  return 0;
}; # function setup_log_files ( )

###
# function find_log_files_with_identical_logrotate_configuration_file
#---
# Description:
#---
# Returns the log files, which have identical logrotate configuration files set in __DESTINATION_LOG_FILES
#---
# Arguments:
#---
#   #   | name                                   | type        | description
#-------+----------------------------------------+-------------+-------------------------------------------------------< 
#<  $1> | logrotateConfigurationFile             | string      | Logrotate configuration file to search for
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __DESTINATION_LOG_FILES                       | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | If everything went fine
# (return)   1 | If no argument given
# (print )   - | Log files, which have the same logrotate configuration file defined as given
#####
function find_log_files_with_identical_logrotate_configuration_file () {
  declare logrotateConfigurationFile="${1}"
  [[ -n "${logrotateConfigurationFile}" ]] || {
    write_output "Did not receive any argument!" "ERROR";
    return 1;
  };

  declare -a identicalLogrotateFiles
  for logFile in "${!__DESTINATION_LOG_FILES[@]}"; do
    IFS="," read -ra logFileAttributes <<< "${__DESTINATION_LOG_FILES["${logFile}"]}"
    [[ "${logrotateConfigurationFile}" =~ ^${logFileAttributes[2]}$ ]] || {
      continue;
    };
    identicalLogrotateFiles+=("${logFile}")
  done
  echo "${identicalLogrotateFiles[@]}"
  return 0;
}; # function find_log_files_with_identical_logrotate_configuration_file ( <logrotateConfigurationFile> )

###
# function setup_logrotate_configuration_files 
#---
# Description:
#---
# Creates the logrotate configuration files as defined in __DESTINATION_LOG_FILES
#---
# Arguments:
#---
#   #   | name                                   | type        | description
#-------+----------------------------------------+-------------+-------------------------------------------------------< 
#  none
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __DESTINATION_LOG_FILES                       | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | If everything went fine
# (return)   1 | If malformed log owner and group is set
# (return)   2 | If unable to check for identical logrotate configuration files
# (print )   - | Log files, which have the same logrotate configuration file defined as given
#####
function setup_logrotate_configuration_files () {
  for logFile in "${!__DESTINATION_LOG_FILES[@]}"; do
    write_output "Processing '${logFile}'" "INFO";

    # read the log file attributes to an array
    IFS="," read -ra logFileAttributes <<< "${__DESTINATION_LOG_FILES["${logFile}"]}"
    [[ "${#logFileAttributes[@]}" -eq 3 ]] || {
      write_output "Skipping setup of logrotate for logFile '${logFile}' as no log rotate configuration files is given" "INFO";
      continue;
    };

    logFilePermisisons="${logFileAttributes[1]}"
    logrotateConfigurationFile="${logFileAttributes[2]}"

    # we further need to split up owner and group
    IFS=":" read -ra logFileOwnerAndGroup <<< "${logFileAttributes[0]}"
    
    # we expect to have 2 indices
    [[ "${#logFileOwnerAndGroup[@]}" -eq 2 ]] || {
      write_output "Malformed owner and group (value: '${logFileAttributes[0]}'), cannot process entry!" "ERROR";
      return 1;
    };
   
    logFileOwner="${logFileOwnerAndGroup[0]}"
    logFileGroup="${logFileOwnerAndGroup[1]}"

    IFS=" " read -ra identicalLogFiles <<< "$(find_log_files_with_identical_logrotate_configuration_file "${logrotateConfigurationFile}")"
    returnCode="${?}"
    [[ "${returnCode}" -eq 0 ]] || {
      write_output "Failed to check for identical log rotate configuration files" "ERROR";
      return 2;
    };

    # empty configuration file
    echo "" > "${logrotateConfigurationFile}"

    write_output "Creating logrotate file '${logrotateConfigurationFile} ..'" "INFO";
    # first add all log files to the logrotate file ..
    for identicalLogFile in "${identicalLogFiles[@]}"; do
      write_output "Adding '${identicalLogFile}' to '${logrotateConfigurationFile}' ..";
      cat <<-EOF >> "${logrotateConfigurationFile}"
"${identicalLogFile}"
EOF
    done

    # .. and then add the options
    cat <<-EOF >> "${logrotateConfigurationFile}"
{
  daily
  rotate 30
  dateext
  dateformat _%Y_%m_%d
  compress
  delaycompress
  missingok
  create ${logFilePermissions} ${logFileOwner} ${logFileGroup}
}
EOF
    
    # unset to prevent bash from keeping it
    unset identicalLogrotateConfigurationFiles
  done

  return 0;
}; # setup_logrotate_configuration_files ( )

write_output "Creating log files .." "INFO";
setup_log_files || {
  write_output "ERROR: Failed to create log files!" "ERROR";
  exit 1;
};

write_output "Creating logrotate files .." "INFO";
setup_logrotate_configuration_files || {
  write_output "ERROR: Creating logrotate files!" "ERROR";
  exit 2;
};

write_output "Testing the created files with logrotate -d .." "INFO";
for logFile in "${!__DESTINATION_LOG_FILES[@]}"; do
  # read the attributes for the log files   
  IFS="," read -ra logFileAttributes <<< "${__DESTINATION_LOG_FILES["${logFile}"]}"
  logrotateConfigurationFile="${logFileAttributes[2]}"

  # test the configuration file
  write_output "Testing '${logrotateConfigurationFile}' .." "INFO";
  logrotate -d "${logrotateConfigurationFile}" &> /dev/null || {
    write_output "logrotate -d "${logrotateConfigurationFile}" failed!" "ERROR";
    exit 3;
  };
  write_output "Sucessfully tested '${logrotateConfigurationFile}'." "INFO";
done

exit 0;
#EOF
