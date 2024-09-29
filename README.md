## Prerequisites
*!!! CAUTION !!!* If you are not experienced Linux user it probably better to run the build procedure on a VM because at some point while preparing the root file system it mounts recursively /sys and /dev filesystems from the host to this root file system being built. If something goes wrong then you have to be able to umount the manually. Moreover some GUI enviroments like Gnome can expose all these /dev and /sys subdirectories in GUI utilities which can be confusing.

### Sudo
The procedure assumes the user running the script is able to mount/umount filesystems. This usually means the user must be able to run some commands with root permissions using sudo.

### If you use Fedora 39+
```bash
dnf install uboot-tools dtc libuuid-devel libuuid
dnf install kernel-modules-extra
modprobe ftdi_sio
```

### Bootgen
Xilinx bootgen command line tool must be installed (provided by Vitis) and it must be available in one of the directories listed in `$PATH`.

## Prepare repository
```bash
git clone https://github.com/kozhukalov/artyz7.git
cd artyz7
git submodule init
git submodule update
```

## Build boot file system
This will create a directory `./build/bootfs` that will contain FSBL, BOOT.BIN, U-boot binary, U-boot script, Linux kernel binary and busybox based initramfs.
```bash
make bootfs
```

## Build root file system
This will create a directory `./build/rootfs` that contains Ubuntu Base Jammy with kernel modules system installed into it.
```bash
make rootfs
```

## Prepare SD
### Partitioning and formatting
Insert an SD card (32GB) in a card reader and figure out the device name. E.g. if the SD device name is /dev/sdb then run the following
```bash
#!!! CAUTION !!! DESTROYS ALL THE DATA ON THE DEVICE
./sd/format_sd.sh /dev/sdb
```
Once the SD card is formatted, check that it is NOT mounted to any point and follow next steps

### Sync bootfs on SD
This will mount the SD boot partition (e.g. `/dev/sdb1`) to `./build/mnt_boot` and copy all the files from `./build/bootfs` to this mount point and then unmounts it.
```bash
make bootsd _SD_DEVICE_BOOT=/dev/sdb1
```

### Sync rootfs on SD
This will mount the SD root partition (e.g. `/dev/sdb2`) to `./build/mnt_root` and copy all the files from `./build/rootfs` to this mount point and then unmounts it.
```bash
make rootsd _SD_DEVICE_ROOT=/dev/sdb2
```

## Boot ArtyZ7
Now insert the SD to the ArtyZ7 SD slot and set JP4 to boot from SD. To connect to the serial console via USB use the following command:
```bash
sudo screen /dev/ttyUSB1 115200
```
Once the OS is booted you can log in using username `root` and password `root` (it is set during build time).
