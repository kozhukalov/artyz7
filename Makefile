# Path to the sources.
# Default value: directory with Makefile
SOURCE_DIR?=$(dir $(lastword $(MAKEFILE_LIST)))
SOURCE_DIR:=$(abspath $(SOURCE_DIR))
# Base path for build and mirror directories.
# Default value: current directory
TOP_DIR?=$(PWD)
TOP_DIR:=$(abspath $(TOP_DIR))
# Working build directory
BUILD_DIR?=$(TOP_DIR)/build
BUILD_DIR:=$(abspath $(BUILD_DIR))
include $(SOURCE_DIR)/rules.mk

CROSS_COMPILE_URL?=https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/
CROSS_COMPILE_TXZ?=arm-gnu-toolchain-13.3.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
CROSS_COMPILE?=$(BUILD_DIR)/arm-gnu-toolchain-13.3.rel1-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-
ROOTFS_URL?=https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release
ROOTFS_TGZ?=ubuntu-base-22.04-base-armhf.tar.gz
BUSYBOX_URL?=https://busybox.net/downloads
BUSYBOX_BASE?=busybox-1.36.1
BUSYBOX_TBZ2?=$(BUSYBOX_BASE).tar.bz2
ARCH:=arm
DEVICE_TREE:=artyz7
UBOOT_DEFCONFIG:=uboot_defconfig
LINUX_DEFCONFIG:=linux_defconfig
BUSYBOX_DEFCONFIG:=busybox_defconfig
SUDO:=sudo
SD_DEVICE_BOOT?=/dev/disk/by-uuid/4F5C-19B0
UBOOT_SOURCE_DIR?=$(SOURCE_DIR)/u-boot
UBOOT_BUILD_DIR?=$(BUILD_DIR)/u-boot
LINUX_SOURCE_DIR?=$(SOURCE_DIR)/linux-xlnx
LINUX_BUILD_DIR?=$(BUILD_DIR)/linux


.PHONY: all clean

all: $(BUILD_DIR)/boot.done
all: $(BUILD_DIR)/linux.done
clean: clean-u-boot clean-linux clean-bootfs clean-rootfs clean-busybox clean-initramfs

### SD card targets
.PHONY: bootsd
bootsd: $(BUILD_DIR)/boot.done
bootsd: export SD_DEVICE_BOOT = $(SD_DEVICE_BOOT)
bootsd: export SD_SCRIPT = \
	$(SUDO) mount ${SD_DEVICE_BOOT} $(BUILD_DIR)/mnt_boot && \
	$(SUDO) cp $(BUILD_DIR)/boot/* $(BUILD_DIR)/mnt_boot && \
	$(SUDO) chown root:root $(BUILD_DIR)/mnt_boot/* && \
	$(SUDO) umount ${SD_DEVICE_BOOT}
bootsd:
	@mkdir -p $(BUILD_DIR)/mnt_boot
	@echo "We are about to run the following command: $${SD_SCRIPT}"
	@echo "Are you sure you want to continue (y/n)?"; \
		read answer; \
		if [[ $${answer} != $${answer#[Yy]} ]]; then bash -c "$${SD_SCRIPT}"; fi

### Cross-compile targets
$(BUILD_DIR)/$(CROSS_COMPILE_TXZ):
	mkdir -p $(BUILD_DIR)
	wget $(CROSS_COMPILE_URL)/$(CROSS_COMPILE_TXZ) \
		-O $(BUILD_DIR)/$(CROSS_COMPILE_TXZ)

$(BUILD_DIR)/cross-compile.done: $(BUILD_DIR)/$(CROSS_COMPILE_TXZ)
	tar Jxf $(BUILD_DIR)/$(CROSS_COMPILE_TXZ) -C $(BUILD_DIR)
	$(ACTION.TOUCH)

### U-boot targets
.PHONY: u-boot
u-boot: $(BUILD_DIR)/u-boot.done

$(UBOOT_SOURCE_DIR)/configs/$(UBOOT_DEFCONFIG): $(SOURCE_DIR)/$(UBOOT_DEFCONFIG)
	$(ACTION.COPY)

$(UBOOT_BUILD_DIR)/.config: $(UBOOT_SOURCE_DIR)/configs/$(UBOOT_DEFCONFIG)
	mkdir -p $(UBOOT_BUILD_DIR)
	$(MAKE) -j4 -C $(UBOOT_SOURCE_DIR) O=$(UBOOT_BUILD_DIR) ARCH=$(ARCH) $(UBOOT_DEFCONFIG)

$(UBOOT_SOURCE_DIR)/arch/arm/dts/artyz7.dts: $(SOURCE_DIR)/artyz7.dts
	$(ACTION.COPY)

$(UBOOT_BUILD_DIR)/u-boot.elf $(UBOOT_BUILD_DIR)/arch/arm/dts/artyz7.dtb: \
		$(BUILD_DIR)/cross-compile.done \
		$(UBOOT_BUILD_DIR)/.config \
		$(UBOOT_SOURCE_DIR)/arch/arm/dts/artyz7.dts
	$(MAKE) -j4 -C $(UBOOT_SOURCE_DIR) O=$(UBOOT_BUILD_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) DEVICE_TREE=$(DEVICE_TREE)

$(BUILD_DIR)/u-boot.done: \
		$(UBOOT_BUILD_DIR)/u-boot.elf \
		$(UBOOT_BUILD_DIR)/arch/arm/dts/artyz7.dtb
	$(ACTION.TOUCH)

.PHONY: clean-u-boot
clean-u-boot:
	$(MAKE) -C $(SOURCE_DIR)/u-boot O=$(UBOOT_BUILD_DIR) distclean
	rm $(SOURCE_DIR)/u-boot/configs/$(UBOOT_DEFCONFIG)
	rm $(SOURCE_DIR)/u-boot/arch/arm/dts/artyz7.dts
	rm -rf $(UBOOT_BUILD_DIR)

### Linux targets
.PHONY: linux linux-modules
linux: $(BUILD_DIR)/linux.done
linux-modules: $(BUILD_DIR)/linux_modules.done

$(LINUX_SOURCE_DIR)/arch/arm/configs/$(LINUX_DEFCONFIG): $(SOURCE_DIR)/$(LINUX_DEFCONFIG)
	$(ACTION.COPY)

$(LINUX_BUILD_DIR)/.config: $(LINUX_SOURCE_DIR)/arch/arm/configs/$(LINUX_DEFCONFIG)
	mkdir -p $(LINUX_BUILD_DIR)
	$(MAKE) -C $(LINUX_SOURCE_DIR) O=$(LINUX_BUILD_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(LINUX_DEFCONFIG)

$(LINUX_BUILD_DIR)/arch/arm/boot/uImage: \
		$(BUILD_DIR)/cross-compile.done \
		$(LINUX_BUILD_DIR)/.config
	$(MAKE) -j4 -C $(LINUX_SOURCE_DIR) O=$(LINUX_BUILD_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) UIMAGE_LOADADDR=0x3000000 uImage
	$(ACTION.TOUCH)

$(BUILD_DIR)/linux.done: $(LINUX_BUILD_DIR)/arch/arm/boot/uImage

$(BUILD_DIR)/linux_modules.done: \
		$(BUILD_DIR)/cross-compile.done \
		$(LINUX_BUILD_DIR)/.config
	$(MAKE) -j4 -C $(LINUX_SOURCE_DIR) O=$(LINUX_BUILD_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	$(ACTION.TOUCH)

.PHONY: clean-linux
clean-linux:
	$(MAKE) -C $(LINUX_SOURCE_DIR) O=$(LINUX_BUILD_DIR) ARCH=$(ARCH) mproper
	rm -rf $(LINUX_BUILD_DIR)

### Bootfs targets
.PHONY: bootfs
bootfs: $(BUILD_DIR)/bootfs.done

$(BUILD_DIR)/bootfs/boot.bif: $(SOURCE_DIR)/sd/boot.bif
	$(ACTION.COPY)

$(BUILD_DIR)/bootfs/fsbl.elf: $(SOURCE_DIR)/sd/zynq_fsbl.elf
	$(ACTION.COPY)

$(BUILD_DIR)/bootfs/u-boot.elf: $(UBOOT_BUILD_DIR)/u-boot.elf
	$(ACTION.COPY)

$(BUILD_DIR)/bootfs/system.dtb: $(UBOOT_BUILD_DIR)/arch/arm/dts/artyz7.dtb
	$(ACTION.COPY)

$(BUILD_DIR)/bootfs/initramfs.cpio.gz: \
		$(BUILD_DIR)/initramfs.done
	cd $(BUILD_DIR)/initramfs && find . -print0 | cpio --null -ov --format=newc | gzip -9 > $@

$(BUILD_DIR)/bootfs/BOOT.BIN: \
		$(BUILD_DIR)/bootfs/u-boot.elf \
		$(BUILD_DIR)/bootfs/system.dtb \
		$(BUILD_DIR)/bootfs/fsbl.elf \
		$(BUILD_DIR)/bootfs/boot.bif
	cd $(BUILD_DIR)/bootfs && bootgen -image boot.bif -w -o BOOT.BIN

$(BUILD_DIR)/bootfs.done: \
		$(BUILD_DIR)/bootfs/u-boot.elf \
		$(BUILD_DIR)/bootfs/system.dtb \
		$(BUILD_DIR)/bootfs/fsbl.elf \
		$(BUILD_DIR)/bootfs/boot.bif \
		$(BUILD_DIR)/bootfs/BOOT.BIN \
		$(BUILD_DIR)/bootfs/initramfs.cpio.gz
	$(ACTION.TOUCH)

.PHONY: clean-bootfs
clean-bootfs:
	rm -rf $(BUILD_DIR)/bootfs

### Rootfs targets
.PHONY: rootfs
rootfs: $(BUILD_DIR)/rootfs.done

$(BUILD_DIR)/$(ROOTFS_TGZ):
	mkdir -p $(BUILD_DIR)
	wget $(ROOTFS_URL)/$(ROOTFS_TGZ) -O $(BUILD_DIR)/$(ROOTFS_TGZ)

$(BUILD_DIR)/rootfs_untar.done: $(BUILD_DIR)/$(ROOTFS_TGZ)
	mkdir -p $(BUILD_DIR)/rootfs
	tar zxf $(BUILD_DIR)/$(ROOTFS_TGZ) -C $(BUILD_DIR)/rootfs
	$(ACTION.TOUCH)

$(BUILD_DIR)/rootfs_passwd.done: $(BUILD_DIR)/rootfs_untar.done
	echo "root:root" | sudo chpasswd -R $(BUILD_DIR)/rootfs
	$(ACTION.TOUCH)

$(BUILD_DIR)/rootfs_modules.done: \
		$(BUILD_DIR)/rootfs_untar.done \
		$(BUILD_DIR)/linux_modules.done
	$(MAKE) -C $(LINUX_SOURCE_DIR) O=$(LINUX_BUILD_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules_install INSTALL_MOD_PATH=$(BUILD_DIR)/rootfs
	$(ACTION.TOUCH)

$(BUILD_DIR)/rootfs.done: \
		$(BUILD_DIR)/rootfs_passwd.done \
		$(BUILD_DIR)/rootfs_modules.done
	$(ACTION.TOUCH)

.PHONY: clean-rootfs
clean-rootfs:
	$(BUILD_DIR)/rootfs_untar.done
	rm -rf $(BUILD_DIR)/rootfs

### Initramfs targets
.PHONY: initramfs busybox
initramfs: $(BUILD_DIR)/initramfs.done
busybox: $(BUILD_DIR)/$(BUSYBOX_BASE)/busybox

$(BUILD_DIR)/$(BUSYBOX_TBZ2):
	mkdir -p $(BUILD_DIR)
	wget $(BUSYBOX_URL)/$(BUSYBOX_TBZ2) -O $(BUILD_DIR)/$(BUSYBOX_TBZ2)

$(BUILD_DIR)/busybox_untar.done: $(BUILD_DIR)/$(BUSYBOX_TBZ2)
	tar jxf $(BUILD_DIR)/$(BUSYBOX_TBZ2) -C $(BUILD_DIR)
	$(ACTION.TOUCH)

$(BUILD_DIR)/$(BUSYBOX_BASE)/configs/$(BUSYBOX_DEFCONFIG): $(SOURCE_DIR)/$(BUSYBOX_DEFCONFIG)
	$(ACTION.COPY)

$(BUILD_DIR)/$(BUSYBOX_BASE)/.config: \
		$(BUILD_DIR)/busybox_untar.done \
		$(BUILD_DIR)/$(BUSYBOX_BASE)/configs/$(BUSYBOX_DEFCONFIG)
	$(MAKE) -j4 -C $(BUILD_DIR)/$(BUSYBOX_BASE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(BUSYBOX_DEFCONFIG)

$(BUILD_DIR)/$(BUSYBOX_BASE)/busybox: \
		$(BUILD_DIR)/cross-compile.done \
		$(BUILD_DIR)/busybox_untar.done \
		$(BUILD_DIR)/$(BUSYBOX_BASE)/.config
	$(MAKE) -j4 -C $(BUILD_DIR)/$(BUSYBOX_BASE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE)
	$(ACTION.TOUCH)

$(BUILD_DIR)/initramfs/init: $(SOURCE_DIR)/initramfs.init
	$(ACTION.COPY)

$(BUILD_DIR)/initramfs/bin/busybox: $(BUILD_DIR)/$(BUSYBOX_BASE)/busybox
	$(ACTION.COPY)

$(BUILD_DIR)/initramfs.done: \
		$(BUILD_DIR)/initramfs/bin/busybox \
		$(BUILD_DIR)/initramfs/init
	mkdir -p $(BUILD_DIR)/initramfs/{bin,sbin,dev,etc,home,mnt,proc,sys,usr,tmp}
	mkdir -p $(BUILD_DIR)/usr/{bin,sbin}
	mkdir -p $(BUILD_DIR)/proc/sys/kernel
	cd $(BUILD_DIR)/initramfs/dev && sudo mknod sda b 8 0 && sudo mknod console c 5 1
	$(ACTION.TOUCH)

.PHONY: clean-busybox clean-initramfs
clean-busybox:
	rm $(BUILD_DIR)/busybox_untar.done
	rm -rf $(BUILD_DIR)/$(BUSYBOX_BASE)
clean-initramfs:
	rm -rf $(BUILD_DIR)/initramfs
