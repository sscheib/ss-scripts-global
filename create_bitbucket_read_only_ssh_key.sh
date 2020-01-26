#!/bin/bash
#
# Description:
#   Simple script to create a password-less ECDSA ssh key to use with BitBucket
# 
VERSION=1.0

if command -v hostname &> /dev/null; then 
  __hostname="$(hostname -f)" 
elif command -v uci &> /dev/null; then 
  __hostname="$(echo $(uci -q get system.@system[0].hostname).$(uci -q get dhcp.@dnsmasq[0].domain) | awk '{ print tolower($0) }')"
else 
  echo "ERROR: Neither hostname nor uci binary found!"; 
  exit 1;
fi 
ssh-keygen -t ecdsa -b 521 -C "root@${__hostname}: BitBucket read-only key" -P "" -f /root/.ssh/bitbucket_read_only
cat /root/.ssh/bitbucket_read_only.pub
