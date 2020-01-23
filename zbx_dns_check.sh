#!/bin/bash
#!/bin/bash
###
# Description:
#   This script is inteded to look up a given DNS entry on a given DNS server and measure
#   the amount of time it took to respond.
# Exit codes:
#   0: DNS lookup was successful
#   1: DNS lookup was unsuccessful
#   2: 3rd parameter was given, but it was not usec
#
# log file                                      : none
# logrotate                                     : not necessary
# zabbix script monitoring integration
#  - exit and error codes                       : yes, zbx_script_monitoring.sh
#  - runtime errors                             : yes, included within this script
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
# 23.01.2019: - Fixed sending of value as exitCode, rather than runtimeMessage
#             ~ Added units to output
#             ~ Incremented version number to 1.5
# 14.01.2019: + Added support to measure latency in microseconds
#             + Added proper commenting
#             + Incremented version number to 1.4
#             + Added exit code 2 (if 3rd parameter is given, but it is not usec)
#             ~ Changed the output to show whether ms or usec are measured
# 14.01.2019: + Added proper exit codes
#             + Integrated zbx_script_monitoring
# 13.01.2019: . Initial script

#
# version: 1.5
declare VERSION="1.5"
source /usr/local/bin/zbx_script_monitoring.sh
zbx::scriptMonitoring::init::default

unset responseTime
units="ms"
# third parameter is given
[[ -z "${3}" ]] || {
  # however, it is not used
  [[ "${3}" =~ ^usec$ ]] ||{
    zbx::scriptMonitoring::send "${0}" "ERROR: 3rd parameter given (value: '${3}') with DNS server '${1}' to check domain '${2}', but value is not valid. Only usec is a valid value." "runtimeMessage"
    exit 2;
  };
  units="usec"
};

# enable pipefail, so that it doesn't matter which command is failing when using pipe commands, the first error code will be the final return code
set -o pipefail
zbx::scriptMonitoring::send "${0}" "INFO : Checking DNS server '${1}' for domain '${2}' in '${units}'" "runtimeMessage"
if [[ "${units}" =~ ^ms$ ]]; then
  responseTime="$(dig +noall +stats @"${1}" "${2}" 2> /dev/null | awk '/Query time:/ {print $4}')" || {
    zbx::scriptMonitoring::send "${0}" "ERROR: Failed checking '${1}' for domain '${2}'. dig exited with exit code: '${?}'" "runtimeMessage"
    exit 1;
  };
else
  responseTime="$(dig -u +noall +stats @"${1}" "${2}" 2> /dev/null | awk '/Query time:/ {print $4}')" || {
    zbx::scriptMonitoring::send "${0}" "ERROR: Failed checking '${1}' for domain '${2}'. dig exited with exit code: '${?}'" "runtimeMessage"
    exit 1;
  };
fi

zbx::scriptMonitoring::send "${0}" "INFO : Successfully queried DNS server '${1}' for domain '${2}'. Response time: ${responseTime}${units}" "runtimeMessage"
echo "${responseTime}"

exit 0;
# EOF
