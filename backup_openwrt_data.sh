#!/bin/bash

###
# Description:
#   This script is used to create a backup of both the mounted USB and flash partitions. The data will be 
#   synchronized with the remote, means everything which is deleted locally, will be deleted on the remote
#   as well.
#   However, if a USB partition is mounted read-only, processing will stop, as this usually indicates a
#   broken/faulty (thus read-only) USB device. This way replacing the USB device is as easy as copying
#   the contents from the backup to a new USB device.
#  
# Exit codes:
#   0: Backup of either flash or USB partitions was successful
#   1: Unable to source zbx_script_monitoring.sh
#   2: Backing up one or more mounted USB partitions failed
#   3: Backing up the flash partition failed
#
# log file                                      : yes, by default as the script name (/logs/backup_openwrt_data.log)
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
# 11.01.2021: - Fixed a typo
#             - Removed unsupported long names for getops
# 25.12.2020: + Added function openwrtDataBackup::init 
#             ~ Bumped version to 1.3
# 25.12.2020: - Refactoring of the script
#           : ~ Bumped version to 1.1
# 24.12.2020: . Initial
#
# version: 1.3
VERSION=1.3
# name of the usb dev name
declare __USB_DEVICE_NAME="sda"
# path where the remote (e.g. NFS) is mounted on the local file system
declare -r __REMOTE_PATH="/backup"
# regex to check if the share path is available
declare -r __REMOTE_PATH_REGEX="synology-ds918\.(home|office)\.int\.scheib\.me.*${__REMOTE_PATH}"
# name of the folder for the usb data
declare -r __USB_DATA_FOLDER_NAME="usb-data"
# name of the folder for the flash data
declare -r __FLASH_DATA_FOLDER_NAME="flash-data"
# path where the flash is mounted on the local file system
declare -r __FLASH_MOUNT="/rwm"
# log file for this script
declare -r __LOG_FILE="/logs/$(basename "${0}" | sed 's/\.sh$//').log"


# source Zabbix script monitoring 
source zbx_script_monitoring.sh &> /dev/null || {
  source /usr/local/sbin/zbx_script_monitoring.sh &> /dev/null || {
    echo "ERROR: Unable to source zbx_script_monitoring.sh";
    exit 1;
  };
};

zbx::scriptMonitoring::init::default

# exit immediatly if a command fails
set -e
# let the whole pipe fail (exit with != 0) if a command in it fails
set -o pipefail

# required binaries by this script
declare -ar __REQUIRED_BINARIES=(
  "rsync"
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
function openwrtDataBackup::print () {
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
}; # function openwrtDataBackup::print ( <message> [level] )

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
# (return)   2 | If the remote is not mounted
#####
function openwrtDataBackup::init () {
  openwrtDataBackup::print "Checking if all required binaries are installed .." "DEBUG";
  for binary in "${__REQUIRED_BINARIES[@]}"; do
    command -v "${binary}" &> /dev/null || {
      openwrtDataBackup::print "Binary '${binary}' is not installed, but required by this script!" "ERROR"; 
      return 1; 
    };
  done
  openwrtDataBackup::print "All required binaries are installed, continuing." "INFO";

  openwrtDataBackup::print "Checking if share is mounted .." "DEBUG";
  mount | grep -Eq "${__REMOTE_PATH_REGEX}" &> /dev/null || {
    openwrtDataBackup::print "Remote share at '${__REMOTE_PATH}' is not mounted!" "ERROR";
    return 2;
  };
  openwrtDataBackup::print "Remote share is mounted at '${__REMOTE_PATH}', continuing." "INFO";

  return 0;
}; # function openwrtDataBackup::init ( )


###
# function openwrtConfigurationBackup::backup_data
#---
# Description:
#---
# Backups either all mounted partitions from the defined usb device (__USB_DEVICE_NAME) or the (mounted) flash partition
# to the defined remote using rsync.
#---
# Arguments:
#---
#   #   | name                                   | type        | description
#-------+----------------------------------------+-------------+-------------------------------------------------------< 
#  None
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __REMOTE_PATH                                 | read        | --
#   02 | __USB_DATA_FOLDER_NAME                        | read        | --
#   02 | __FLASH_DATA_FOLDER_NAM                       | read        | --
#   03 | __USB_DEVICE_NAME                             | read        | --
#   04 | __LOG_FILE                                    | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | The backup was performed successfully
# (return)   1 | Function did not receive any arguments
# (return)   2 | Function did receive an argument, but it was neither 'usb' or 'flash'
# (return)   3 | This error should never happen (second check for 'usb' and 'flash')
# (return)   4 | Unable to create destination folder (__REMOTE_PATH + __USB_DATA_FOLDER_NAME or 
#              | __FLASH_DATA_FOLDER_NAME)
# (return)   5 | Destination path (__REMOTE_PATH + __USB_DATA_FOLDER_NAME or __FLASH_DATA_FOLDER_NAME) exists, but 
#              | is not a folder
# (return)   6 | Destination folder (__REMOTE_PATH + __USB_DATA_FOLDER_NAME or __FLASH_DATA_FOLDER_NAME) is not writable
# (return)   7 | Unable to create destination folder (__REMOTE_PATH + __USB_DATA_FOLDER_NAME + mountPoint)
# (return)   8 | Destination path (__REMOTE_PATH + __USB_DATA_FOLDER_NAME + mountPoint) exists, but is not a folder
# (return)   9 | Destination path (__REMOTE_PATH + __USB_DATA_FOLDER_NAME + mountPoint) is not writable
# (return)  10 | rsync command to backup a mount point failed
# (return)  11 | rsync command to backup the flash data failed
# (return)  12 | This error should never happen (third check for 'usb' and 'flash')
#####
function openwrtDataBackup::backup_data () {
  declare backupType=""
  [[ -n "${1}" ]] || {
    openwrtDataBackup::print "Function openwrtDataBackup::backup_data did not receive any arguments!" "ERROR";
    return 1;
  };
  backupType="${1}"


  [[ "${backupType}" =~ ^usb|flash$ ]] || {
    openwrtDataBackup::print "Function openwrtDataBackup::backup_data received an invalid argument! Value: '${backupType}' - Allowed: 'usb', 'flash'" "ERROR";
    return 2;
  };

  declare destination="${__REMOTE_PATH}/"
  case "${backupType}" in
    usb)
      destination+="${__USB_DATA_FOLDER_NAME}"
    ;;
    flash)
      destination+="${__FLASH_DATA_FOLDER_NAME}"
    ;;
    *)
      openwrtDataBackup::print "This error should never happen, but catching it anyway" "ERROR";
      return 3;
  esac
  
  # try to create the destination folder, if it does not exist
  openwrtDataBackup::print "Checking if folder '${destination}' exists .." "DEBUG";
  [[ -e "${destination}" ]] || {
    openwrtDataBackup::print "Folder '${destination}' does not exist, trying to create it .." "DEBUG";
    mkdir -vp "${destination}" || {
      openwrtDataBackup::print "Unable to create folder '${destination}'!" "ERROR";
      return 4;
    };
    openwrtDataBackup::print "Folder '${destination}' has successfully been created." "DEBUG";
  };
  openwrtDataBackup::print "Folder '${destination}' existed already or has successfully been created." "INFO";
  
  # we need to make sure destination is actually a folder
  [[ -d "${destination}" ]] || {
    openwrtDataBackup::print "Destination path '${destination}' exists, but is not a folder!" "ERROR";
    return 5;
  };
  
  # finally, we need to check if we can actually write into the folder
  [[ -w "${destination}" ]] || {
    openwrtDataBackup::print "Destination folder '${destination}' is not writable!" "ERROR";
    return 6;
  };
  
  if [[ "${backupType}" =~ ^usb$ ]]; then
    openwrtDataBackup::print "It was asked to backup USB data .." "INFO";
    openwrtDataBackup::print "Going to process all mounted partitions of '/dev/${USB_DEVICE_NAME}' .." "INFO";
    while read -r line; do
      IFS=" " read -ra mountOptions <<<"${line}"
      mountPoint="${mountOptions[0]}"
      IFS="," read -ra attributes <<<"${mountOptions[1]}"
      openwrtDataBackup::print "Processing mount point '${mountPoint}' with options '${mountOptions[1]}' .." "DEBUG";
      declare -i writable=1
      for option in "${attributes[@]}"; do
        [[ "${option}" =~ ^rw$ ]] || {
          continue;
        };
        writable=0
      done
   
      # if the file system is mounted read-only or we have no permissions to read from it, we try to process the other partitions
      [[ "${writable}" -eq 0 ]] || {
        openwrtDataBackup::print "Filesystem at '${mountPoint}' is not writable!" "ERROR";
        continue;
      };
      openwrtDataBackup::print "Filesystem at '${mountPoint}' is mounted writable, continuing." "INFO";

      [[ -r "${mountPoint}" ]] || {
        openwrtDataBackup::print "Mount point '${mountPoint}' is not readable from the current USER ('${USER}')!" "ERROR";
        continue;
      };
      openwrtDataBackup::print "Mount point '${mountPoint}' is readable for the current user, continuing." "INFO";

      # remove first slash of the mount point
      mountPoint="${mountPoint/\//}"

      destination="${__REMOTE_PATH}/${__USB_DATA_FOLDER_NAME}/${mountPoint}"
      openwrtDataBackup::print "Checking if destination folder '${destination}' exists .." "DEBUG";
      [[ -e "${destination}" ]] || {
        openwrtDataBackup::print "Trying to create destination folder '${destination} ..'" "DEBUG";
        mkdir -p "${destination}" || {
          openwrtDataBackup::print "Unable to create destination folder '${destination}'!" "ERROR";
          return 7;
        };
        openwrtDataBackup::print "Folder '${destination}' has successfully been created." "DEBUG";
      };

      openwrtDataBackup::print "Destination folder '${destination}' existed or was created successfully." "INFO";
      # we need to make sure destination is actually a folder
      [[ -d "${destination}" ]] || {
        openwrtDataBackup::print "Destination path '${destination}' exists, but is not a folder!" "ERROR";
        return 8;
      };
      
      # finally, we need to check if we can actually write into the folder
      [[ -w "${destination}" ]] || {
        openwrtDataBackup::print "Destination folder '${destination}' is not writable!" "ERROR";
        return 9;
      };

      # we need to add the appending / again, as it was removed beforehand :3
      openwrtDataBackup::print "Going to execute following command:" "DEBUG";
      openwrtDataBackup::print "'rsync -av --progress "/${mountPoint}/" "${destination}/" --delete >> "${__LOG_FILE}"'" "DEBUG";
      rsync -av --progress "/${mountPoint}/" "${destination}/" --delete >> "${__LOG_FILE}" || {
        openwrtDataBackup::print "The rsync command to backup mountpoint '/${mountPoint}' failed!" "ERROR";
        return 10;
      };
      openwrtDataBackup::print "Successfully backed up mountpoint '/${mountPoint}' to '${destination}'." "INFO";
    done < <(mount | grep "^\/dev\/${__USB_DEVICE_NAME}" | awk '{print $3" "$6}' | sed -e 's/(//' -e 's/)//')
  elif [[ "${backupType}" =~ ^flash$ ]]; then
    openwrtDataBackup::print "It was asked to backup flash data .." "INFO";
    openwrtDataBackup::print "Checking if flash is mounted ('${__FLASH_MOUNT}')" "DEBUG";
    mounted=1
    while read -r line; do
      [[ "${line}" =~ ^${__FLASH_MOUNT}$ ]] || {
        continue;
      };

      # found a match
      mounted=0
    done < <(mount | grep "${__FLASH_MOUNT}" | awk '{print $3}')
    [[ "${mounted}" -eq 0 ]] || {
      openwrtDataBackup::print "Flash mount ('${__FLASH_MOUNT}') is not mounted, cannot backup flash!" "ERROR";
      return 11;
    };
    
    [[ -r "${__FLASH_MOUNT}" ]] || {
      openwrtDataBackup::print "Flash mount ('${__FLASH_MOUNT}') is not readable for the current user ('${USER}')!" "ERROR";
      return 12;
    };

    openwrtDataBackup::print "Going to execute the following command:" "DEBUG";
    openwrtDataBackup::print "'rsync -av --progress "${__FLASH_MOUNT}/" "${destination}/" --delete >> "${__LOG_FILE}"'" "DEBUG";
    rsync -av --progress "${__FLASH_MOUNT}/" "${destination}/" --delete >> "${__LOG_FILE}" || {
      openwrtDataBackup::print "The rsync command to backup the flash data failed!" "ERROR";
      return 11;
    };
    openwrtDataBackup::print "Successfully backed up the flash storage ('${__FLASH_MOUNT}') to '${destination}'." "INFO";
  else
    openwrtDataBackup::print "This error should also never happen, but catching it anyways." "ERROR";
    return 12;
  fi
  
  openwrtDataBackup::print "Successfully finished the backup job of type '${backupType}'!" "INFO";
  return 0;
} #; openwrtDataBackup::backup_data ( <backupType> )

function openwrtDataBackup::usage ( ) {
  echo "Usage of "$(basename "${0}")""
  echo "Available command line options:"
  echo "-u: Will backup all mounted partions of the defined USB device"
  echo "-f: Will backup the flash data"
  echo "-h: Print this message"

  return 0;
} #; openwrtDataBackup::usage

# no arguments supplied
[[ "${#@}" -ne 0 ]] || {
  openwrtDataBackup::usage
  exit 0;
};

# parse command line options
while getopts ":fuh" arg; do
  case "${arg}" in
    # USB or flash backup requested
    u|f)
      # initialization only needed if we actually perform a backup
      openwrtDataBackup::init || {
        openwrtDataBackup::print "Initialization of this script has failed!" "ERROR";
        exit 2;
      };

      # once the initialization completed, we need to destinct between USB and flash backup
      case "${arg}" in
        # USB backup
        u)
          openwrtDataBackup::backup_data "usb" || {
            openwrtDataBackup::print "Backing up USB data failed!" "ERROR";
            exit 2;
          };
        ;;
        # flash backup
        f)
          openwrtDataBackup::backup_data "flash" || {
            openwrtDataBackup::print "Backing up USB data failed!" "ERROR";
            exit 3;
          };
        ;;
      esac
    ;;
    # unknown command line argument given
    \?)
      openwrtDataBackup::print "Invalid command line option '-${OPTARG}'!" "ERROR";
      continue;
    ;;
    # help requested
    h)
      openwrtDataBackup::usage
      exit 0;
    ;;
  esac
done

exit 0;

#EOF
