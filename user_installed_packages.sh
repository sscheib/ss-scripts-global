#!/bin/sh
###
# Description:
#  Simple script to get the user installed packages. These are the packages, which have been installed,
#  since the oldest installed package (which is the flash time).
#  
#   Usage:
#   /bin/sh <scriptname>.sh
#
# Exit codes:
#   0: Will always exit with 0
#
# log file                                      : not necessary
# logrotate                                     : not necessary
# zabbix script monitoring integration
#  - exit and error codes                       : not necessary
#  - runtime errors                             : not necessary
# log file monitoring                           : not necessary
#
# Author:
# Eric Anderson
#
# Source: https://gist.github.com/devkid/8d4c2a5ab62e690772f3d9de5ad2d978#gistcomment-2223412
# Maintainer:
# Steffen Scheib (steffen@scheib.me)
#
# Legend:
# + New
# - Bugfix
# ~ Change
# . Various
#
# Changelog:
# 06.07.2020: . Initial commit
#

# version 1.0
VERSION=1.0

FLASH_TIME="$(awk '
$1 == "Installed-Time:" && ($2 < OLDEST || OLDEST=="") {
  OLDEST=$2
}
END {
  print OLDEST
}
' /usr/lib/opkg/status)"

awk -v FT="$FLASH_TIME" '
$1 == "Package:" {
  PKG=$2
  USR=""
}
$1 == "Status:" && $3 ~ "user" {
  USR=1
}
$1 == "Installed-Time:" && USR && $2 != FT {
  print PKG
}
' /usr/lib/opkg/status | sort
