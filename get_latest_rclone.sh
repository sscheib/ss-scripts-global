#!/bin/bash
###
# Description:
#   This script is intended to download and install the latest stable rclone version.
#   The download URL is changed based on the architecture of the system. Currently
#   supported are x86_x64 and arm.
# Exit codes:
#   0: If no new version is found
#   0: If new version was installed successfully
#   1: If architecture determined via 'arch' is not supported
#   2: If the download of __RCLONE_DOWNLOAD_URL failed
#   3: If the dpkg command to install the downloaded .deb failed
#   4: If the mv command to rename the downloaded .deb after the 
#      installation to __RCLONE_CURRENT_VERSION_NAME  within the directory __DOWNLOAD_PATH failed
#
# log file                                      : yes, /var/log/rclone_download.log and /var/log/rclone_download.debug
# logrotate                                     : yes, provided with the _setup script
# zabbix script monitoring integration
#  - exit and error codes                       : yes, zbx_script_monitoring.sh
#  - runtime errors                             : yes, included within this script
# log file monitoring                           : yes, both debug and log file are monitored from Zabbix   
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
# 06.01.2010: + Added call to zbx::scriptMonitoring::init::default
#             + Incremented VERSION to 1.2
#             + Added Legend and adjusted previous entries of the changelog
# 05.01.2020: + Added support for multiple architectures (arm and x86_x64)
#             + Integrated zbx_script_monitoring into the script 
#             + Added proper header
#             + Added log file monitoring within Zabbix for both debug and log files
#             ~ Changed the output formatting of write_output along with the parameters
#             ~ write_output will only print the message if in an interactive session
# xx.xx.2019: . Initial script

#
# version: 1.2
declare VERSION="1.2"


PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
declare -r __RCLONE_CURRENT_VERSION_NAME="rclone-old.deb"
declare -r __RCLONE_DOWNLOADED_NAME="rclone-downloaded.deb"
declare -r __DOWNLOAD_PATH="/tmp"
declare -r __LOG_FILE="/var/log/rclone_download.log"
declare -r __DEBUG_FILE="/var/log/rclone_download.debug"


source "/root/sources/ss-scripts-global/zbx_script_monitoring.sh"
zbx::scriptMonitoring::init::default

# Writes a message to stdout if we are in an interactive session
# It also writes to the defined _LOG_FILE as well as notify Zabbix
function write_output () {
  declare message="${1}"

  declare formattedMsg="$(printf "[%s] %s: %-36s: %-7s> %s\n" "$(date +'%d.%m.%y - %H:%M:%S')" "$(basename "${0}")" "${FUNCNAME[1]}" "${level}" "${message}")"
  # only print the message if we are in an interactive session
  [[ ! -t 1 ]] || {
    printf "${formattedMsg}\n";
  };

  zbx::scriptMonitoring::send "${0}" "${formattedMsg}" "runtimeMessage"
  printf "${formattedMsg}\n" >> "${__LOG_FILE}" 
} #; function write_output ( <message> <level> )

declare __RCLONE_DOWNLOAD_URL=""
case "$(arch)" in
  x86_x64)
    __RCLONE_DOWNLOAD_URL="https://downloads.rclone.org/rclone-current-linux-amd64.deb" 
  ;;
  armv*)
    __RCLONE_DOWNLOAD_URL="https://downloads.rclone.org/rclone-current-linux-arm.deb"
  ;;
  *)
    write_output "ERROR: Architecture '$(arch)' not supported!"
    exit 1;
  ;;
esac

declare -i returnCode=-1
write_output "Downloading rclone from '${__RCLONE_DOWNLOAD_URL}' to '${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}' .." "INFO"
curl "${__RCLONE_DOWNLOAD_URL}" -o "${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}" &>> "${__DEBUG_FILE}" || {
  returnCode="${?}";
  write_output "Failed to download rclone from '${__RCLONE_DOWNLOAD_URL}' to '${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}'!" "ERROR";
  write_output "curl exited with return code '${returnCode}'" "ERROR";
  exit 2;
};
write_output "Successfully downloaded '${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}'." "INFO"


write_output "Comparing downloaded .deb with current installed .deb .." "INFO"
! cmp -s "${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}" "${__DOWNLOAD_PATH}/${__RCLONE_CURRENT_VERSION_NAME}" || {
  write_output "No difference found! ('${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}') vs. '${__DOWNLOAD_PATH}/${__RCLONE_CURRENT_VERSION_NAME}')" "INFO";
  exit 0;
};
write_output "New rclone version found!" "INFO"
write_output "Current version: '"$(rclone --version | awk 'NR==1 {print $2}')"'" "INFO"


write_output "Installing new version of rclone .. " "INFO"
dpkg --log="${__DEBUG_FILE}" -i "${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}" &>> "${__DEBUG_FILE}" || {
  returnCode="${?}";
  write_output "Installing new rclone version failed!" "ERROR";
  write_output "dpkg exited with return code '${returnCode}'" "ERROR";
  exit 3;
};
write_output "Successfully installed following new version of rclone: '"$(rclone --version | awk 'NR==1 {print $2}')"'" "ERROR"


mv -v "${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}" "${__DOWNLOAD_PATH}/${__RCLONE_CURRENT_VERSION_NAME}" &>> "${__DEBUG_FILE}" || {
  returnCode="${?}";
  write_output "Renaming '${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}' to '${__DOWNLOAD_PATH}/${__RCLONE_CURRENT_VERSION_NAME}' failed!" "ERROR";
  write_output "mv exited with return code '${returnCode}'" "ERROR";
  exit 4;
};
write_output "Successfully renamed!"

exit 0;
