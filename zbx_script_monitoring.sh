#!/bin/bash

##
# general global variables
###
# binaries, which are required by this script
declare -ar __REQUIRED_BINARIES=(
  "zabbix_get"
  "logger"
)

# directories, which contain scripts, which low level discovery from zabbix should create items from
declare -r __SCRIPTS_DIRECTORIES=(
  "/root/sources/ss-scripts-"$(hostname -f)""
)

# additional scripts (in other folders) to "discover" for LLD
declare -ar __ADDITIONAL_SCRIPTS=(
  "/tmp/zabbix_test/test.sh"
)

# scripts to exclude from LLD (if they are in the defined directories)
# this script needs to be sourced (via 'source scriptname.sh') as FIRST script in the script sourcing this script
declare -ar __EXCLUDED_SCRIPTS=(
  "/root/sources/ss-scripts-"$(hostname -f)"/zbx_script_monitoring_setup.sh"
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

function zbx::scriptMonitoring::print () {
  declare message="${1}"

  # if no message level is given, UNDEF will be used instead
  declare level="UNDEF"
  [[ -z "${2}" ]] || {
    level="${2}"
  };

  declare formattedMsg="$(printf "[%s] %s: %-25s: %-7s> %s\n" "$(date +'%d.%m.%y - %H:%M:%S')" "$(basename "${0}")" "${FUNCNAME[1]}" "${level}" "${message}")"
  # looks like: [02.01.20 - 17:52:51] upload_logs_gdrive.sh: main                     : INFO   > my message here

  # if we are in an interactive session, or if we have no access 
  # to the __NOTIFICATION_LOG file, we print the message to stdout
  ( [[ ! -t 1 ]] || 
    [[ ! -w "${__NOTIFICATION_LOG}" ]]
  ) || {
    echo "${formattedMsg}";
  };
  echo "${formattedMsg}" >> "${__NOTIFICATION_LOG}"
}; # function zbx::scriptMonitoring::print ( <message> [level] )

function zbx::scriptMonitoring::init::default () {
  zbx::scriptMonitoring::print "${FUNCNAME}: Values: ${@}" "DEBUG"
  zbx::scriptMonitoring::init "${__DEFAULT_ZABBIX_AGENT_CONFIGURATION_FILE}" "${__DEFAULT_EXIT_ON_ERROR}" "${__DEFAULT_NOTIFICATION_LOG}"
}; # function zbx::scriptMonitoring::init::default

function zbx::scriptMonitoring::init () {
  zbx::scriptMonitoring::print "${FUNCNAME}: Values: ${@}" "DEBUG"
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
    [[ -w "${2}" ]] || {
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
}; # function zbx::scriptMonitoring::init ( <zabbixAgentConfigurationFile> [notificationLog, default: __DEFAULT_NOTIFICATION_LOG] ) 

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
  };
}; # function zbx::scriptMonitoring::send ( <scriptName> <value> [valueType, default: runtime_return_value] )

function zbx::scriptMonitoring::lowLevelDiscovery () {
  zbx::scriptMonitoring::print "${FUNCNAME}: Values: ${@}" "DEBUG"
  declare -a scripts=()
  for directory in "${__SCRIPTS_DIRECTORIES[@]}"; do
    for file in "${directory}/"*; do
      for excludedFile in "${__EXCLUDED_SCRIPTS[@]}"; do
        [[ ! "${file}" =~ ${excludedFile} ]] || {
          zbx::scriptMonitoring::print "'${file}' from directory is set to be excluded in '__EXCLUDED_SCRIPTS', skipping it." "INFO";
          continue;
        };
      done

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
    output+=" { \"{#SCRIPTNAME}\": \""$(basename "${file}")"\",\"{#EXITCODE}\": \"-1\",\"{#EXITLINE}\": \"-1\",\"{#EXITERROR}\": \"-1\",\"{#ERRORLINE}\": \"-1\",\"{#RUNTIMEMESSAGES}\": \"UNDEF\" },"
    # looks like: 
  done
  # we need to remove the trailing , and the prefixed spaces
  output="$(echo "${output}" | sed -e 's/,$//' -e 's/^ //g')"

  # finally we need to suffix this
  output+="]}"
  printf "${output}\n" | jq || {
    zbx::scriptMonitoring::send "lowLevelDiscovery failed - invalid JSON!" "RUNTIMEMESSAGE";
    exit 1;
  };

  exit 0;
}; # function zbx::scriptMonitoring::lowLevelDiscovery ( )

function zbx::scriptMonitoring::exit_trap () {
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
}; # zbx::scriptMonitoring::exit_trap ( )

function zbx::scriptMonitoring::error_trap () {
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
}; # zbx::scriptMonitoring::error_trap

if [[ "${1}" =~ lowLevelDiscovery ]]; then
  zbx::scriptMonitoring::lowLevelDiscovery
fi

trap 'zbx::scriptMonitoring::exit_trap ${LINENO}' EXIT
trap 'zbx::scriptMonitoring::error_trap ${LINENO}' ERR
