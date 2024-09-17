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

CROSS_COMPILE_URL?=https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/13.3.0
CROSS_COMPILE_TGZ?=x86_64-gcc-13.3.0-nolibc-arm-linux-gnueabi.tar.gz
CROSS_COMPILE?=$(BUILD_DIR)/gcc-13.3.0-nolibc/arm-linux-gnueabi/bin/arm-linux-gnueabi-
ROOTFS_URL?=https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release
ROOTFS_TGZ?=ubuntu-base-22.04-base-armhf.tar.gz
ARCH:=arm
DEVICE_TREE:=artyz7
DEFCONFIG:=artyz7_defconfig
SUDO:=sudo
SD_DEVICE_BOOT?=/dev/disk/by-uuid/4F5C-19B0
UBOOT_SOURCE_DIR?=$(SOURCE_DIR)/u-boot
UBOOT_BUILD_DIR?=$(BUILD_DIR)/u-boot
LINUX_SOURCE_DIR?=$(SOURCE_DIR)/linux-xlnx
LINUX_BUILD_DIR?=$(BUILD_DIR)/linux


.PHONY: all clean

all: $(BUILD_DIR)/boot.done
all: $(BUILD_DIR)/linux.done
clean: clean-u-boot clean-linux clean-boot

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
$(BUILD_DIR)/$(CROSS_COMPILE_TGZ):
	mkdir -p $(BUILD_DIR)
	wget $(CROSS_COMPILE_URL)/$(CROSS_COMPILE_TGZ) \
		-O $(BUILD_DIR)/$(CROSS_COMPILE_TGZ)

$(BUILD_DIR)/cross-compile.done: $(BUILD_DIR)/$(CROSS_COMPILE_TGZ)
	tar zxf $(BUILD_DIR)/$(CROSS_COMPILE_TGZ) -C $(BUILD_DIR)
	$(ACTION.TOUCH)

### U-boot targets
.PHONY: u-boot
u-boot: $(BUILD_DIR)/u-boot.done

$(UBOOT_SOURCE_DIR)/configs/artyz7_defconfig: $(SOURCE_DIR)/artyz7_defconfig
	$(ACTION.COPY)

$(UBOOT_BUILD_DIR)/.config: $(UBOOT_SOURCE_DIR)/configs/artyz7_defconfig
	mkdir -p $(UBOOT_BUILD_DIR)
	$(MAKE) -j4 -C $(UBOOT_SOURCE_DIR) O=$(UBOOT_BUILD_DIR) ARCH=$(ARCH) artyz7_defconfig

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
	rm $(SOURCE_DIR)/u-boot/configs/artyz7_defconfig
	rm $(SOURCE_DIR)/u-boot/arch/arm/dts/artyz7.dts
	rm -rf $(UBOOT_BUILD_DIR)

### Linux targets
.PHONY: linux linux-modules
linux: $(BUILD_DIR)/linux.done
linux-modules: $(BUILD_DIR)/linux_modules.done

$(LINUX_SOURCE_DIR)/arch/arm/configs/xilinx_zynq_defconfig: $(SOURCE_DIR)/xilinx_zynq_defconfig
	$(ACTION.COPY)

$(LINUX_BUILD_DIR)/.config: $(LINUX_SOURCE_DIR)/arch/arm/configs/xilinx_zynq_defconfig
	mkdir -p $(LINUX_BUILD_DIR)
	$(MAKE) -C $(LINUX_SOURCE_DIR) O=$(LINUX_BUILD_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) xilinx_zynq_defconfig

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
.PHONY: boot
boot: $(BUILD_DIR)/boot.done

$(BUILD_DIR)/boot/boot.bif: $(SOURCE_DIR)/sd/boot.bif
	$(ACTION.COPY)

$(BUILD_DIR)/boot/fsbl.elf: $(SOURCE_DIR)/sd/zynq_fsbl.elf
	$(ACTION.COPY)

$(BUILD_DIR)/boot/u-boot.elf: $(UBOOT_BUILD_DIR)/u-boot.elf
	$(ACTION.COPY)

$(BUILD_DIR)/boot/system.dtb: $(UBOOT_BUILD_DIR)/arch/arm/dts/artyz7.dtb
	$(ACTION.COPY)

$(BUILD_DIR)/boot/BOOT.BIN: \
		$(BUILD_DIR)/boot/u-boot.elf \
		$(BUILD_DIR)/boot/system.dtb \
		$(BUILD_DIR)/boot/fsbl.elf \
		$(BUILD_DIR)/boot/boot.bif
	cd $(BUILD_DIR)/boot && bootgen -image boot.bif -w -o BOOT.BIN

$(BUILD_DIR)/boot.done: \
		$(BUILD_DIR)/boot/u-boot.elf \
		$(BUILD_DIR)/boot/system.dtb \
		$(BUILD_DIR)/boot/fsbl.elf \
		$(BUILD_DIR)/boot/boot.bif \
		$(BUILD_DIR)/boot/BOOT.BIN
	$(ACTION.TOUCH)

.PHONY: clean-boot
clean-boot:
	rm -rf $(BUILD_DIR)/boot

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

