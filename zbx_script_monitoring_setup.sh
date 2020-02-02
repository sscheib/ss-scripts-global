#!/bin/bash
# define the destination configuration file (usually within /etc/logrotate.d/ - suffix is irrelevant)
declare -r __DESTINATION_LOGROTATE_CONFIGURATION_FILE="/etc/logrotate.d/zabbix_notification"

function setup_logrotate () {
  if [[ -e "/usr/bin/lzop" ]]; then
    echo "INFO : Found lzop, will use lzop as compression command"
    cat <<-EOF > "${__DESTINATION_LOGROTATE_CONFIGURATION_FILE}"
"/var/log/zabbix_notification.log"
{
  size 3M
  rotate 7
  dateext
  dateformat -%Y-%m-%d-%H%M
  extension .log
  compresscmd /usr/bin/lzop
  compressoptions -U -9
  compressext .lzo
  compress
  delaycompress
  missingok
  notifempty
  create 644 zabbix zabbix
}
EOF
  else
    echo "INFO : lzop not found, will fall back to gzip as compression command"
    cat <<-EOF > "${__DESTINATION_LOGROTATE_CONFIGURATION_FILE}"
"/var/log/zabbix_notification.log"
{
  size 3M
  rotate 7
  dateext
  dateformat -%Y-%m-%d-%H%M
  extension .log
  compress
  delaycompress
  missingok
  notifempty
  create 644 zabbix zabbix
}
EOF
  fi
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
