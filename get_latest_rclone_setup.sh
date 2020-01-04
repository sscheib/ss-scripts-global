#!/bin/bash
# define the destination configuration file (usually within /etc/logrotate.d/ - suffix is irrelevant)
declare -r __DESTINATION_LOGROTATE_CONFIGURATION_FILE="/etc/logrotate.d/get_latest_rclone"

function setup_logrotate () {
  cat <<-EOF > "${__DESTINATION_LOGROTATE_CONFIGURATION_FILE}"
"/var/log/rclone_download.log"
"/var/log/rclone_download.debug"
{
  daily
  rotate 7
  dateext
  dateformat _%Y_%m_%d
  compresscmd /usr/bin/lzop
  compressoptions -U -9
  compressext .lzo
  compress
  delaycompress
  missingok
  notifempty
  create 644 root root
}
EOF
};

echo "INFO : Creating file '${__DESTINATION_LOGROTATE_CONFIGURATION_FILE}' .."
setup_logrotate || {
  echo "ERROR: Creating file '${__DESTINATION_LOGROTATE_CONFIGURATION_FILE}' failed!";
  exit 1;
};
echo "INFO : Created file '${__DESTINATION_LOGROTATE_CONFIGURATION_FILE}'"

echo "INFO : Testing the created file with logrotate -d .."
logrotate -d "${__DESTINATION_LOGROTATE_CONFIGURATION_FILE}" &> /dev/null || {
  echo "ERROR: logrotate -d "${__DESTINATION_LOGROTATE_CONFIGURATION_FILE}" failed!";
  exit 2;
};
echo "INFO : File successfully tested."

exit 0;
