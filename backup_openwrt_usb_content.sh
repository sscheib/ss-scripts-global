#!/bin/bash
declare -r __USB_DEVICE_NAME="sda"
declare -r __REMOTE_PATH="/backup"
declare -r __USB_DATA_FOLDER_NAME="usb-data"
declare -r __FLASH_DATA_FOLDER_NAME="flash-data"
declare -r __FLASH_MOUNT="/rwm" 

for directory in "${__USB_DATA_FOLDER_NAME}" "${__FLASH_DATA_FOLDER_NAME}"; do
  [[ -e "${__REMOTE_PATH}/${directory}" ]] || {
    mkdir -vp "${__REMOTE_PATH}/${directory}" || {
      echo "ERROR: Failed creating '${__REMOTE_PATH}'";
      exit 1;
    };
  };
done

while read -r line; do
  IFS=" " read -ra mountOptions <<<"${line}"
  mountPoint="${mountOptions[0]}"
  IFS="," read -ra attributes <<<"${mountOptions[1]}"
  echo "mp: ${mountPoint}"
  declare -i writable=1
  for option in "${attributes[@]}"; do
    [[ "${option}" =~ ^rw$ ]] || {
      continue;
    };
    writable=0
  done
  [[ "${writable}" -eq 0 ]] || {
    echo "ERROR: Filesystem at '${mountPoint}' is not writable!";
  };
  rsync -av --progress "${mountPoint}/" "${__REMOTE_PATH}/${__USB_DATA_FOLDER_NAME}${mountPoint}/" --delete
done < <(mount | grep "^\/dev\/${__USB_DEVICE_NAME}" | awk '{print $3" "$6}' | sed -e 's/(//' -e 's/)//')

if [[ "${1}" =~ ^--backup-rwm$ ]]; then
  rsync -av --progress "${__FLASH_MOUNT}/" "${__REMOTE_PATH}/${__FLASH_DATA_FOLDER_NAME}/" --delete
fi
