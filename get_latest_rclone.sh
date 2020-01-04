#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
declare -r __RCLONE_DOWNLOAD_URL="https://downloads.rclone.org/rclone-current-linux-arm.deb"
declare -r __RCLONE_CURRENT_VERSION_NAME="rclone-old.deb"
declare -r __RCLONE_DOWNLOADED_NAME="rclone-downloaded.deb"
declare -r __DOWNLOAD_PATH="/tmp"
declare -r __LOG_FILE="/var/log/rclone_download.log"
declare -r __DEBUG_FILE="/var/log/rclone_download.debug"

source "/root/sources/ss-scripts-global/zbx_script_monitoring.sh"

function write_output () {
  declare message="${1}"
  printf "${message}\n"
  printf "${message}\n" >> "${__LOG_FILE}" 
} #; function write_output ( <message> )

declare -i returnCode=-1
write_output "Downloading rclone from '${__RCLONE_DOWNLOAD_URL}' to '${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}' .."
curl "${__RCLONE_DOWNLOAD_URL}" -o "${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}" &>> "${__DEBUG_FILE}" || {
  returnCode="${?}";
  write_output "Failed to download rclone from '${__RCLONE_DOWNLOAD_URL}' to '${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}'!";
  write_output "curl exited with return code '${returnCode}'";
  exit 1;
};
write_output "Successfully downloaded '${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}'."


write_output "Comparing downloaded .deb with current installed .deb .."
! cmp -s "${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}" "${__DOWNLOAD_PATH}/${__RCLONE_CURRENT_VERSION_NAME}" || {
  write_output "No difference found! ('${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}') vs. '${__DOWNLOAD_PATH}/${__RCLONE_CURRENT_VERSION_NAME}')";
  exit 0;
};
write_output "New rclone version found!"
write_output "Current version: '"$(rclone --version | awk 'NR==1 {print $2}')"'"


write_output "Installing new version of rclone .. "
dpkg --log="${__DEBUG_FILE}" -i "${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}" &>> "${__DEBUG_FILE}" || {
  returnCode="${?}";
  write_output "Installing new rclone version failed!";
  write_output "dpkg exited with return code '${returnCode}'";
  exit 2;
};
write_output "Successfully installed following new version of rclone: '"$(rclone --version | awk 'NR==1 {print $2}')"'"


mv -v "${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}" "${__DOWNLOAD_PATH}/${__RCLONE_CURRENT_VERSION_NAME}" &>> "${__DEBUG_FILE}" || {
  returnCode="${?}";
  write_output "Renaming '${__DOWNLOAD_PATH}/${__RCLONE_DOWNLOADED_NAME}' to '${__DOWNLOAD_PATH}/${__RCLONE_CURRENT_VERSION_NAME}' failed!";
  write_output "mv exited with return code '${returnCode}'";
  exit 3;
};
write_output "Successfully renamed!"

exit 0;
