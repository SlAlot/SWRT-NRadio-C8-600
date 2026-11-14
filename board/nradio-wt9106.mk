define Device/nradio_wt9106
  DEVICE_VENDOR := NRadio
  DEVICE_MODEL := C8-600 (WT9106, 512 MiB RAM, 128 MiB NAND)
  DEVICE_DTS := mt7981b-nradio-wt9106
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_OVERLAY := mt7981-nradio-wt9106
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 fitblk
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
    fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  IMAGE_SIZE := 100m
  IMAGES := sysupgrade.itb
  IMAGE/sysupgrade.itb := append-kernel | \
    fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | \
    pad-rootfs | append-metadata | check-size
endef
TARGET_DEVICES += nradio_wt9106
