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
ARCH:=arm
DEVICE_TREE:=artyz7
DEFCONFIG:=artyz7_defconfig
SUDO:=sudo
SD_DEVICE_BOOT?=/dev/disk/by-uuid/4F5C-19B0

.PHONY: all sd clean clean-u-boot clean-sd

all: $(BUILD_DIR)/boot.done

sd: $(BUILD_DIR)/boot.done
sd: export SD_DEVICE_BOOT = $(SD_DEVICE_BOOT)
sd: export SD_SCRIPT = \
	$(SUDO) mount ${SD_DEVICE_BOOT} $(BUILD_DIR)/mnt_boot && \
	$(SUDO) cp $(BUILD_DIR)/boot/* $(BUILD_DIR)/mnt_boot && \
	$(SUDO) chown root:root $(BUILD_DIR)/mnt_boot/* && \
	$(SUDO) umount ${SD_DEVICE_BOOT}
sd:
	@mkdir -p $(BUILD_DIR)/mnt_boot
	@echo "We are about to run the following command: $${SD_SCRIPT}"
	@echo "Are you sure you want to continue (y/n)?"; \
		read answer; \
		if [[ $${answer} != $${answer#[Yy]} ]]; then bash -c "$${SD_SCRIPT}"; fi

clean: clean-u-boot clean-boot
clean-u-boot:
	$(MAKE) -C $(SOURCE_DIR)/u-boot O=$(BUILD_DIR)/u-boot distclean
	rm $(SOURCE_DIR)/u-boot/configs/artyz7_defconfig
	rm $(SOURCE_DIR)/u-boot/arch/arm/dts/artyz7.dts
clean-boot:
	rm -rf $(BUILD_DIR)/boot

$(BUILD_DIR)/$(CROSS_COMPILE_TGZ):
	mkdir -p $(BUILD_DIR)
	wget $(CROSS_COMPILE_URL)/$(CROSS_COMPILE_TGZ) \
		-O $(BUILD_DIR)/$(CROSS_COMPILE_TGZ)

$(BUILD_DIR)/cross-compile.done: $(BUILD_DIR)/$(CROSS_COMPILE_TGZ)
	tar zxf $(BUILD_DIR)/$(CROSS_COMPILE_TGZ) -C $(BUILD_DIR)
	$(ACTION.TOUCH)

$(SOURCE_DIR)/u-boot/configs/artyz7_defconfig: $(SOURCE_DIR)/artyz7_defconfig
	$(ACTION.COPY)

$(BUILD_DIR)/u-boot/.config: $(SOURCE_DIR)/u-boot/configs/artyz7_defconfig
	mkdir -p $(BUILD_DIR)/u-boot
	$(MAKE) -C $(SOURCE_DIR)/u-boot O=$(BUILD_DIR)/u-boot artyz7_defconfig

$(SOURCE_DIR)/u-boot/arch/arm/dts/artyz7.dts: $(SOURCE_DIR)/artyz7.dts
	$(ACTION.COPY)

$(BUILD_DIR)/u-boot/u-boot.elf $(BUILD_DIR)/u-boot/arch/arm/dts/artyz7.dtb: \
		$(BUILD_DIR)/cross-compile.done \
		$(BUILD_DIR)/u-boot/.config \
		$(SOURCE_DIR)/u-boot/arch/arm/dts/artyz7.dts
	$(MAKE) -C $(SOURCE_DIR)/u-boot ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) DEVICE_TREE=$(DEVICE_TREE) O=$(BUILD_DIR)/u-boot

$(BUILD_DIR)/u-boot.done: \
		$(BUILD_DIR)/u-boot/u-boot.elf \
		$(BUILD_DIR)/u-boot/arch/arm/dts/artyz7.dtb
	$(ACTION.TOUCH)

$(BUILD_DIR)/boot/boot.bif: $(SOURCE_DIR)/sd/boot.bif
	$(ACTION.COPY)

$(BUILD_DIR)/boot/fsbl.elf: $(SOURCE_DIR)/sd/zynq_fsbl.elf
	$(ACTION.COPY)

$(BUILD_DIR)/boot/u-boot.elf: $(BUILD_DIR)/u-boot/u-boot.elf
	$(ACTION.COPY)

$(BUILD_DIR)/boot/system.dtb: $(BUILD_DIR)/u-boot/arch/arm/dts/artyz7.dtb
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

