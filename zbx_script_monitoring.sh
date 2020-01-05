#!/bin/bash

###
# Description:
#   This script is used for two things:
#     1: Low Level Discovery of scripts for Zabbix
#     2: "Monitoring" of said scripts, using EXIT und ERR BASH traps
#   To use the Low Level Discovery, the script has to be called via "LowLevelDiscovery" as command line parameter.
#   In order to use the monitoring, one needs to at least source this script. Sourcing this script will trigger
#   the traps on any error or exit of the sourcing script.
#   Furthermore one can send messages to Zabbix via zbx::scriptMonitoring::send "${0}" <message> [messageType]
#   Messagetype can be one of runtimeMessage, exitCode, exitLine, errorCode or errorLine.
#  
#   Usage:
#   1. LowLevelDiscovery:
#     - Define settings regarding the scripts to discover
#     - source this script as the first source command in your script
#     - a: call either zbx::scriptMonitoring::init::default to initialize the script with default settings or
#     - b: call zbx::scriptMonitoring:init <zabbixAgentConfigurationFile> <exitOnError> [notificationLog] 
# Exit codes:
#   0: If called via command line argument "LowLevelDiscovery", LLD was successful
#   0: If sourced, sourcing was successful
#   1: LowLevelDiscovery generated an invalid JSON
#   2: LowLevelDiscovery failed
#   NOTE: exit 2 should in usual circumstances never happen, as exit 1 should trigger before, but for the sake
#         of completeness it is mentioned here.
#
# log file                                      : yes, /var/log/zabbix_notification.log
# logrotate                                     : yes, provided with the _setup script
# zabbix script monitoring integration
#  - exit and error codes                       : yes, traps in zbx_script_monitoring.sh
#  - runtime errors                             : yes, included within this script
# log file monitoring                           : yes, monitored from Zabbix   
#
# Author:
# Steffen Scheib (steffen@scheib.me)
#
# Changelog:
# 05.01.2020: - Proper commenting
#             - Refactored a few things
# 04.01.2020: - Initial script

#
# version: 1.1
declare VERSION="1.1"

##
# general global variables
###
# binaries, which are required by this script
declare -ar __REQUIRED_BINARIES=(
  "zabbix_get"
  "jq"
)

# directories, which contain scripts, which low level discovery from zabbix should create items from
declare -r __SCRIPTS_DIRECTORIES=(
  "/root/sources/ss-scripts-"$(hostname -f)""
  "/root/sources/ss-scripts-global"
)

# additional scripts (in other folders) to "discover" for LLD
declare -ar __ADDITIONAL_SCRIPTS=(
)

# scripts to exclude from LLD (if they are in the defined directories)
# this script needs to be sourced (via 'source scriptname.sh') as FIRST script in the script sourcing this script
declare -ar __EXCLUDED_SCRIPTS=(
  ".*_setup.sh$"
)

##
# default global variables
###
# absolute path to the default zabbix agent configuration file
declare -r __DEFAULT_ZABBIX_AGENT_CONFIGURATION_FILE="/etc/zabbix/zabbix_agentd.conf"
# absolute path to the default notification log file this script will write to
declare -r __DEFAULT_NOTIFICATION_LOG="/var/log/zabbix_notification.log"
# determines, whether to exit on error (with the original return code)
declare -ir __DEFAULT_EXIT_ON_ERROR=1

##
# runtime global variables - initially set to the default values
###
declare __ZABBIX_AGENT_CONFIGURATION_FILE="${__DEFAULT_ZABBIX_AGENT_CONFIGURATION_FILE}"
declare __NOTIFICATION_LOG="${__DEFAULT_NOTIFICATION_LOG}"
declare __EXIT_ON_ERROR="${__DEFAULT_EXIT_ON_ERROR}"

###
# function zbx::scriptMonitoring::print
#---
# Description:
#---
# Writes the given message to stdout if in an interactive shell. The messages is additionally written to 
# __NOTIFICATION_LOG in any case.
#---
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#<  $1> | message                                | string      | Message to print/write
#[  $2] | level                                  | string      | Message-"Level" - simple prefix (ERROR, WARNING, INFO, 
#       |                                        |             | DEBUG, etc)
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | NOTIFICATION_LOG                              | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | Will always return 0
#####
function zbx::scriptMonitoring::print () {
  declare message="${1}"

  # if no message level is given, UNDEF will be used instead
  declare level="UNDEF"
  [[ -z "${2}" ]] || {
    level="${2}"
  };

  declare formattedMsg="$(printf "[%s] %s: %-36s: %-7s> %s\n" "$(date +'%d.%m.%y - %H:%M:%S')" "$(basename "${0}")" "${FUNCNAME[1]}" "${level}" "${message}")"
  # looks like: [02.01.20 - 17:52:51] upload_logs_gdrive.sh: main                     : INFO   > my message here

  # if we are in an interactive session, or if we have no access 
  # to the __NOTIFICATION_LOG file, we print the message to stdout
  ( [[ ! -t 1 ]] || 
    [[ ! -w "${__NOTIFICATION_LOG}" ]]
  ) || {
    echo "${formattedMsg}";
  };
  echo "${formattedMsg}" >> "${__NOTIFICATION_LOG}"

  return 0;
}; # function zbx::scriptMonitoring::print ( <message> [level] )

###
# function zbx::scriptMonitoring::init:default
#---
# Description:
#---
# Calls zbx::scriptMonitoring::init with default values
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
#   01 | __DEFAULT_ZABBIX_AGENT_CONFIGURATION_FILE     | read        | --
#   02 | __DEFAULT_EXIT_ON_ERROR                       | read        | --
#   03 | __DEFAULT_NOTIFICATION_LOG                    | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | Initialization with default values successful
# (return)   1 | Initialization with default values failed
#####
function zbx::scriptMonitoring::init::default () {
  zbx::scriptMonitoring::print "Values: '${*}'" "DEBUG"
  zbx::scriptMonitoring::init "${__DEFAULT_ZABBIX_AGENT_CONFIGURATION_FILE}" "${__DEFAULT_EXIT_ON_ERROR}" "${__DEFAULT_NOTIFICATION_LOG}"
  returnCode="${?}"
  [[ "${returnCode}" -eq 0 ]] || {
    zbx::scriptMonitoring::print "Initialization of this script with default values failed! Function returned with '${returnCode}'" "ERROR";
    return 1;
  };

  # initialization went fine
  return 0;
}; # function zbx::scriptMonitoring::init::default

###
# function zbx::scriptMonitoring::init
#---
# Description:
#---
# Initializes the script:
# - Checks the zabbixAgentConfigurationFile for a) existence, b) if it is a file c) readable for the current user
# - If notificationLog is given as argument it is checked, whether it exists and is writeable for the current user, 
#   unless we are root (uid=0). If the file does not exist, it is tried to create it
# - In case notificationLog is not given, the default of __DEFAULT_NOTIFICATION_LOG is used
#---
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#<  $1> | zabbixAgentConfigurationFile          | string      | Configuration file of the Zabbix agent
#<  $2> | exitOnError                           | boolean     | Determines whether the script exits if an error from
#                                               |             | the sourcing script is received via the error trap
#[  $3] | notificationLog                       | string      | File which is used as log file from this script. If not
#       |                                       |             | given __DEFAULT_NOTIFICATION_LOG is used as log file 
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __DEFAULT_NOTIFICATION_LOG                    | read        | --
#   02 | __ZABBIX_AGENT_CONFIGURATION_FILE             | write       | --
#   03 | __EXIT_ON_ERROR                               | write       | --
#   04 | __NOTIFICATION_LOG                            | write       | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | Initialization with the given values successful
# (return)   1 | Given value for zabbixAgentConfigurationFile (first parameter) does not exist
# (return)   2 | Given value for zabbixAgentConfigurationFile (first parameter) is not a file
# (return)   3 | Given value for zabbixAgentConfigurationFile (first parameter) is not readable for the current user
# (return)   4 | Given value for exitOnError (second parameter) is not a boolean
# (return)   5 | notificationLog (third parameter) was given, which did not exist and the creation of it failed
# (return)   6 | notificationLog (third parameter) was given and the file existed, but not readable for the current user
#####
function zbx::scriptMonitoring::init () {
  zbx::scriptMonitoring::print "Values: '${*}'" "DEBUG"
  declare zabbixAgentConfigurationFile="${1}"
  [[ -e "${zabbixAgentConfigurationFile}" ]] || {
    zbx::scriptMonitoring::print "zabbixAgentConfigurationFile '${zabbixAgentConfigurationFile}' does not exist!" "ERROR";
    return 1;
  };

  [[ -f "${zabbixAgentConfigurationFile}" ]] || {
    zbx::scriptMonitoring::print "zabbixAgentConfigurationFile '${zabbixAgentConfigurationFile}' is not a file!" "ERROR";
    return 2;
  };

  [[ -r "${zabbixAgentConfigurationFile}" ]] || {
    zbx::scriptMonitoring::print "zabbixAgentConfigurationFile '${zabbixAgentConfigurationFile}' is not readable from the current user ('${USER}') file!" "ERROR";
    return 3;
  };

  
  declare exitOnError="${2}"
  [[ "${exitOnError}" =~ ^0|1$ ]] || {
    zbx::scriptMonitoring::print "exitOnError has an invalid value: '${exitOnError}'. Valid values: 0,1." "ERROR";
    return 4;
  };

  declare notificationLog="${__DEFAULT_NOTIFICATION_LOG}"
  [[ -z "${3}" ]] || {
    # notificationLog is given, let's see if the file exists
    ( [[ -e "${3}" ]] &&
      [[ -f "${3}" ]]
    ) || {
      # file does not exist, let's try to create it
      touch "${3}" || {
        zbx::scriptMonitoring::print "notificationLog was specified (value: '${3}'), but it does not exist and trying to create it failed!" "ERROR";
        return 5;
      };
    };

    # file exists, lets check if we can write to it
    ( [[ -w "${3}" ]] || 
      [[ "$(id)" =~ ^uid=0 ]]
    ) || {
      zbx::scriptMonitoring::print "notificationLog was specified (value: '${3}') and exists, but it is not writeable for the current user ('${USER}')!" "ERROR";
      return 6;
    };

    # all checks passed
    notificationLog="${3}"
  };


  for binary in "${__REQUIRED_BINARIES[@]}"; do
    command -v "${binary}" &> /dev/null || {
      zbx::scriptMonitoring::print "Binary '${binary}' is missing, although required from this script!" "ERROR";
      return 7;
    };
  done

  # everything alright, let's assign the given values to the global variables
  __ZABBIX_AGENT_CONFIGURATION_FILE="${zabbixAgentConfigurationFile}"
  __NOTIFICATION_LOG="${notificationLog}"
  __EXIT_ON_ERROR="${exitOnError}"

  return 0;
}; # function zbx::scriptMonitoring::init ( <zabbixAgentConfigurationFile>, <exitOnError>, [notificationLog, default: __DEFAULT_NOTIFICATION_LOG] ) 

###
# function zbx::scriptMonitoring::send
#---
# Description:
#---
# Used to send values to the Zabbix instance via zabbix_sender.
# The key is constructed from the three parameters:
# 1. basename (name without path) of the calling script (it should be called via the full path however)
# 2. value to send
# 3. type of the value
# 
# Example #1:
# $1: /path/to/my_script.sh
# $2: exitCode
# $3: 12
# -> generated key, value pair: my_script.sh[exitCode, 12]
# 
# Example #2:
# $1: /root/my_script.sh
# $2: runtimeMessage
# $3: my message here
# -> generated key, value pair: my_script.sh[runtimeMessage, my message here]
#
# NOTE:
# Currently implemented value types are:
# - exitCode
# - exitLine
# - errorCode
# - errorLine
# - runtimeMessage
#---
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#<  $1> | scriptName                            | string      | Full path of the script, which called the function
#       |                                       |             | The name of the script is used as key for zabbix_sender
#<  $2> | value                                 | <any type>  | Value to send
#[  $3] | valueType                             | string      | Type of the value, defaults to exitCode - see NOTE above
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __ZABBIX_AGENT_CONFIGURATION_FILE             | read        | --
#   02 | __NOTIFICATION_LOG                            | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | Value was sent to Zabbix
# (return)   1 | Unable to send value to Zabbix
#####
function zbx::scriptMonitoring::send () {
  declare scriptName="$(basename "${1}")"
  declare value="${2}"
  declare valueType="exitCode"
  [[ -z "${3}" ]] || {
    valueType="${3}"
  };
  zbx::scriptMonitoring::print "Values: scriptName: '${scriptName}' value: '${value}' valueType: '${valueType}'" "DEBUG"

  zbx::scriptMonitoring::print "Sending '- script_execution["${scriptName}","${valueType}"] ${value}'" "DEBUG"
  echo "- script_execution["${scriptName}","${valueType}"] ${value}" | zabbix_sender -vv -i - -c "${__ZABBIX_AGENT_CONFIGURATION_FILE}" &>> "${__NOTIFICATION_LOG}" || {
    zbx::scriptMonitoring::print "Failed sending data!" "ERROR";
    return 1;
  };

  return 0;
}; # function zbx::scriptMonitoring::send ( <scriptName> <value> [valueType, default: exitCode] )

###
# function zbx::scriptMonitoring::lowLevelDiscovery
#---
# Description:
#---
# Used to create the JSON data for the low level discovery (LLD) of the scripts found.
# The folders to look for scripts can be defined in __SCRIPTS_DIRECTORIES - all files, which are not excluded via
# __EXCLUDED_SCRIPTS are treated as scripts and will be "discovered" from Zabbix.
# Additional scripts can be provided via __ADDITIONAL_SCRIPTS - full path to the script is expected.
# 
# NOTE: No sub-directories will be processed. Only files on the first level of the directories specified will be
#       processed.
#--
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
#   01 | __SCRIPTS_DIRECTORIES                         | read        | --
#   02 | __NOTIFICATION_LOG                            | read        | --
#   03 | __ADDITIONAL_SCRIPTS                          | read        | --
#   04 | __EXCLUDED_SCRIPTS                            | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (printf)   - | The generated JSON for Zabbix
# (exit)     0 | Valid JSON generated -> LLD successful
# (exit)     1 | Invalid JSON generated -> LLD failed
#####
function zbx::scriptMonitoring::lowLevelDiscovery () {
  zbx::scriptMonitoring::print "Values: '${@}'" "DEBUG"

  declare -a scripts=()
  declare -i isExcluded=1

  for directory in "${__SCRIPTS_DIRECTORIES[@]}"; do
    for file in "${directory}/"*; do
      isExcluded=1
      for excludedFile in "${__EXCLUDED_SCRIPTS[@]}"; do
        [[ ! "${file}" =~ ${excludedFile} ]] || {
          isExcluded=0;
          break;
        };
      done

      [[ "${isExcluded}" -ne 0 ]] || {
        zbx::scriptMonitoring::print "'${file}' from directory is set to be excluded in '__EXCLUDED_SCRIPTS', skipping it." "INFO";
        continue;
      };

      [[ -f "${file}" ]] || {
        zbx::scriptMonitoring::print "'${file}' from directory is not a file, skipping it." "WARNING";
        continue;
      };

      [[ ! "$(basename "${file}")" =~ [[:space:]] ]] || {
        zbx::scriptMonitoring::print "File '${file}' from directory is contains spaces, which is not supported, skipping it." "WARNING";
        continue;
      };
      scripts+=("${file}")
    done
  done

  for file in "${__ADDITIONAL_SCRIPTS[@]}"; do
    [[ -f "${file}" ]] || {
      zbx::scriptMonitoring::print "'${file}' defined in '__ADDITIONAL_SCRIPTS' is not a file, skipping it." "WARNING";
      continue;
    };
    scripts+=("${file}")
  done

  # we need to prefix this
  output='{ "data": ['
  for file in "${scripts[@]}"; do
    # for every script we have we add this to our output
    output+=" { \"{#SCRIPTNAME}\": \""$(basename "${file}")"\",\"{#EXITCODE}\": \"-1\",\"{#EXITLINE}\": \"-1\",\"{#ERRORCODE}\": \"-1\",\"{#ERRORLINE}\": \"-1\",\"{#RUNTIMEMESSAGE}\": \"UNDEF\" },"
  done
  # we need to remove the trailing , and the prefixed spaces
  output="$(echo "${output}" | sed -e 's/,$//' -e 's/^ //g')"

  # finally we need to suffix this
  output+="]}"
  printf "${output}\n" | jq . || {
    zbx::scriptMonitoring::send "lowLevelDiscovery failed - invalid JSON!" "runtimeMessage";
    exit 1;
  };

  exit 0;
}; # function zbx::scriptMonitoring::lowLevelDiscovery ( )

###
# function zbx::scriptMonitoring::exitTrap
#---
# Description:
#---
# This function will be called on exit of any type of the sourcing script.
# The retrieved values (exitCode, scriptName, lineNumber) will be send to Zabbix.
# If the sourcing script is in __EXCLUDED_SCRIPTS we exit with the given exit code, but we don't notify Zabbix
#--
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#  $1  | lineNumber                             | integer     | Line of the sourcing script, where the exit occured
#  $?  | exitCode                               | integer     | Exit code of the sourcing script
#  $0  | scriptName                             | integer     | Full name of the sourcing script 
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __EXCLUDED_SCRIPTS                            | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (exit)     ? | Exit code depends on the exit code of the sourcing script
#####
function zbx::scriptMonitoring::exitTrap () {
  declare -i exitCode="${?}"
  declare scriptName="${0}"
  declare -i lineNumber="${1}"
  zbx::scriptMonitoring::print "'Values: exitCode: '${exitCode}' scriptName: '${scriptName}' lineNumber: '${lineNumber}''" "DEBUG"

  for excludedScript in "${__EXCLUDED_SCRIPTS[@]}"; do
    [[ ! "${excludedScript}" =~ ${scriptName} ]] || {
      zbx::scriptMonitoring::print "Trap was triggered from excluded script '${excludedScript}' - silently exiting with given exitCode '${exitCode}'" "DEBUG";
      exit "${exitCode}"; 
    };
  done

  zbx::scriptMonitoring::send "${scriptName}" "${exitCode}" "exitCode"
  zbx::scriptMonitoring::send "${scriptName}" "${lineNumber}" "exitLine"

  # exit with the exit code of the sourcing script
  exit "${exitCode}";
}; # zbx::scriptMonitoring::exitTrap ( )

###
# function zbx::scriptMonitoring::errorTrap
#---
# Description:
#---
# This function will be called on an error of any type of the sourcing script.
# The retrieved values (errorCode, scriptName, lineNumber) will be send to Zabbix.
# If the sourcing script is in __EXCLUDED_SCRIPTS we exit with the given exit code, but we don't notify Zabbix
#--
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#  $1  | lineNumber                             | integer     | Line of the sourcing script, where the error occured
#  $?  | exitCode                               | integer     | Error (return, exit) code of the sourcing script
#  $0  | scriptName                             | integer     | Full name of the sourcing script 
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __EXCLUDED_SCRIPTS                            | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (exit)     ? | Exit code depends on the exit code of the sourcing script
#####
function zbx::scriptMonitoring::errorTrap () {
  declare -i errorCode="${?}"
  declare scriptName="${0}"
  declare -i lineNumber="${1}"
  zbx::scriptMonitoring::print "Values: errorCode: '${errorCode}' scriptName: '${scriptName}' lineNumber: '${lineNumber}'" "DEBUG"

  for excludedScript in "${__EXCLUDED_SCRIPTS[@]}"; do
    [[ ! "${excludedScript}" =~ ${scriptName} ]] || {
      zbx::scriptMonitoring::print "Trap was triggered from excluded script '${excludedScript}' - silently exiting with given errorCode '${errorCode}'" "DEBUG";
      exit "${exitCode}"; 
    };
  done

  zbx::scriptMonitoring::send "${scriptName}" "${errorCode}" "errorCode"
  zbx::scriptMonitoring::send "${scriptName}" "${lineNumber}" "errorLine"

  # exit with the exit code of the sourcing script
  [[ "${__EXIT_ON_ERROR}" -eq 0 ]] || {
    exit "${errorCode}";
  };
}; # zbx::scriptMonitoring::errorTrap

# define the traps
trap 'zbx::scriptMonitoring::exitTrap ${LINENO}' EXIT
trap 'zbx::scriptMoonitoring::errorTrap ${LINENO}' ERR


# lowLevelDiscovery is the only accepted command line argument - the script is meant to be source'd
if [[ "${1}" =~ ^lowLevelDiscovery$ ]]; then
  zbx::scriptMonitoring::lowLevelDiscovery || {
    zbx::scriptMonitoring::print "lowLevelDiscovery failed!" "ERROR";
    zbx::scriptMonitoring::send "${0}" "ERROR: lowLevelDiscovery failed!" "RuntimeMessage";
    exit 2;
  };
fi

exit 0;
#EOF
