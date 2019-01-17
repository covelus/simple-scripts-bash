#!/bin/bash
#
# Script for old Debian VMs without Open-Nebula contextualization packages
#   avaliable, such as old ones.
# - It mounts the CDROM, reads the context file available there and sets the configuration
#    items there.
# - It supports 0 to 9 network interfaces.
# -REQUIREMENTS:
#  * Linux distribution using the old network interface eth<N> naming convention, common
#   in distributions using SysVinit, Upstart or a systemd version older than v197
#  * Assuming that the order of the Network Interfaces in context.sh is the same than the one in 
#  * the system, specifically, in /sys/class/net
#   * For example:
#    * if in /sys/class/net/ we have eth0 and eth1
#    * and if in the context file we have ETH0 and ETH1,
#   * this script will match:
#    * ETH0 to eth0
#    * ETH1 to eth1
#
# -AUTOR: Breogan Costa @ RHEA Group
#
# -TESTED: in Metasploitable 8.0.4 hardy (based on Ubuntu 8.0.4) and OpenNebula 5.6.1
#
UNIT="/dev/sr0"
MOUNT_DIR="/mnt/newdisk"
#
CON_DNS_RESOLVER_FILE="/etc/resolv.conf"
CONF_SSH_KEY_USER="env-admin"
CONF_SSH_PUB_KEY_DIR="/home/${CONF_SSH_PUB_KEY_USER}/.ssh/"
CONF_SSH_PUB_KEY_FILE="id_rsa.pub"
CONF_SSH_PUB_KEY_PATH=$CONF_SSH_PUB_KEY_DIR$CONF_SSH_PUB_KEY_FILE
#
LOG_DEBUG="debug"
LOG_DISABLED="-"
LOG_LEVEL=$LOG_DEBUG # $LOG_DEBUG | $LOG_DISABLED
#
# isNotEmpty() checks if a variable is set to some value or empty
#  - Parameter $1: a variable that can set to any value or ""
#  - Returns $? set to the number of errors, therefore, 0 meaning no empty parameter or "success"
function isNotEmpty(){
  param=$1
  if [ "${param}" != "" ]; then 
    return 0 # $param is not empty, no error
  else
    return 1 # $param is "", error
  fi
}
#
# empty function, created for the case when reading some value from the context file, but
#  the usage of this value in the VM settings is not yet implemented/necessary
function pass(){
    echo "">/dev/null # empty instruction, required by the if when no other instructions  
}
#
# Mask to CIDR converter
# taken from:
#  - https://forum.archive.openwrt.org/viewtopic.php?id=47986&p=1#p220781
#  - https://stackoverflow.com/questions/20762575/explanation-of-convertor-of-cidr-to-netmask-in-linux-shell-netmask2cdir-and-cdir/20767392#20767392
mask2cidr(){
   # Assumes there's no "255." after a non-255 byte in the mask
   local x=${1##*255.}
   set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) ${x%%.*}
   x=${1%%$3*}
   return $(( $2 + (${#x}/4) ))
}
#
function logStatus(){
  echo "Running script to manually contextualize unsupported Open-Nebula Debian distros"
  if [ "$LOG_LEVEL" == "$LOG_DEBUG" ]; then
    echo -e "\tFound ${number_interfaces_cntxt} network interfaces in the context file\n"
  fi
}
#
function logValuesGlobal(){
  if [ "$LOG_LEVEL" == "$LOG_DEBUG" ]; then
    echo "--- CONTEXT IMPORTED VALUES --- " $i
    echo " Network: \"${network}\""
    echo " Public key: \"${ssh_public_key}\""
    echo " Startup script: \"${start_script}\""
  fi
}
#
function logValuesByNIC(){
  if [ "$LOG_LEVEL" == "$LOG_DEBUG" ]; then
    echo " Loded values for the ETH${i} vNIC"
    echo -e "\t ETH${i} DNS:" $ethx_dns
    echo -e "\t ETH${i} GW:" $ethx_gateway
    echo -e "\t ETH${i} IP:" $ethx_ip
    echo -e "\t ETH${i} Mask:" $ethx_mask
    echo -e "\t ETH${i} Network:" $ethx_network
    echo -e "\t ETH${i} Search domain:" $ethx_search_domain
    echo -e "\t ETH${i} VLAN ID:" $ethx_vlan_id
    echo -e "\t ETH${i} Router IP:" $ethx_vrouter_ip
  fi
}
#
function setValuesGlobal(){
  isNotEmpty $network
  res=$?
  if [ $res == 0 ]; then
    # TODO if required: This parameter will say if the network is enabled or not
    pass
    #
  fi
  isNotEmpty $ssh_public_key
  res=$?
  if [ $res == 0 ]; then
    mkdir CONF_SSH_PUB_KEY_DIR  # just by the case it doesn't exist yet
    echo $ssh_public_key>>$CONF_SSH_PUB_KEY_PATH
  fi
  isNotEmpty $start_script
  res=$?
  if [ $res == 0 ]; then
    eval $start_script
  fi
}
#
function setValuesByNIC(){
  isNotEmpty $ethx_dns
  res=$?
  if [ $res == 0 ]; then
    echo "nameserver ${ethx_dns}" > $CON_DNS_RESOLVER_FILE
  fi
  isNotEmpty $ethx_gateway
  res=$?
  if [ $res == 0 ]; then
    route add default gw $ethx_gateway
  fi
  isNotEmpty $ethx_mask
  res=$?
  if [ $res == 0 ]; then
    mask2cidr $ethx_mask
    cidr_mask=$?
    ip addr add eth${i} $ethx_ip/$cidr_mask up
  else
    isNotEmpty $ethx_ip
    res=$?
    if [ $res == 0 ]; then
      ip addr add eth${i} $ethx_ip up
    fi
  fi
  isNotEmpty $ethx_network
  res=$?
  if [ $res == 0 ]; then
    # TODO if required: anyhing to be done with $ethx_network ?
    pass
    #
  fi
  isNotEmpty $ethx_search_domain
  res=$?
  if [ $res == 0 ]; then
    echo "search ${ethx_search_domain}" > $CON_DNS_RESOLVER_FILE
  fi
  isNotEmpty $ethx_vlan_id
  res=$?
  if [ $res == 0 ]; then
    # TODO if required something with $ethx_vlan_id
    pass
    #
  fi
  isNotEmpty $ethx_vrouter_ip
  res=$?
  if [ $res == 0 ]; then
    # TODO if required something with $ethx_vrouter_ip
    pass
    #
  fi
}
#
# IMPORT (VIRTUAL) MACHINE VALUES
#  Not necessary for this case
#
# SET UP CONTEXT FILE
#
sudo mkdir $MOUNT_DIR
sudo mount $UNIT $MOUNT_DIR
cd $MOUNT_DIR
#
# IMPORT CONTEXT FILE VALUES
#
number_interfaces_cntxt=$(grep -E "^ETH[0-9]+_IP" context.sh | sed 's/_.*$//' | uniq -c | wc -l)
logStatus
let number_interfaces_cntxt--
#
start_script=$(grep -w START_SCRIPT context.sh | awk -F"'" '{print $2}')
network=$(grep -w NETWORK context.sh | awk -F"'" '{print $2}')
ssh_public_key=$(grep -w SSH_PUBLIC_KEY context.sh | awk -F"'" '{print $2}')
#
logValuesGlobal
setValuesGlobal
#
for i in $(seq 0 $number_interfaces_cntxt);
do
  ethx_dns=$(grep -w ETH[$i]_DNS context.sh | awk -F"'" '{print $2}')
  ethx_gateway=$(grep -w ETH[$i]_GATEWAY context.sh | awk -F"'" '{print $2}')
  ethx_ip=$(grep -w ETH[$i]_IP context.sh | awk -F"'" '{print $2}')
  ethx_mask=$(grep -w ETH[$i]_MASK context.sh | awk -F"'" '{print $2}')
  ethx_network=$(grep -w ETH[$i]_NETWORK context.sh | awk -F"'" '{print $2}')
  ethx_search_domain=$(grep -w ETH[$i]_SEARCH_DOMAIN context.sh | awk -F"'" '{print $2}')
  ethx_vlan_id=$(grep -w ETH[$i]_VLAN_ID context.sh | awk -F"'" '{print $2}')
  ethx_vrouter_ip=$(grep -w ETH[$i]_VROUTER_IP context.sh | awk -F"'" '{print $2}')
  #
  logValuesByNIC
  setValuesByNIC
done
#
# CLEANUP
#
sudo umount $MOUNT_DIR
sudo rm -Rf $MOUNT_DIR
