#!/bin/bash
if [ -z $1 ]; then
    echo "Usage: $0 <device>"
    echo "!!! CAUTION !!! The device must be indeed the actual SD device name."
    echo "!!! CAUTION !!! All data on the device will be lost."
    exit 1
fi

if [ ! -b $1 ]; then
    echo "Device $1 does not exist."
    exit 1
fi

SD_DEVICE=$1
fdisk $SD_DEVICE <<EOF
o
n
p
1

+512M
t
b
n
p
2


w
EOF
fdisk -lu $SD_DEVICE
mkfs.vfat -F 32 ${SD_DEVICE}1
mkfs.ext4 ${SD_DEVICE}2
sync
