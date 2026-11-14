# 安装与升级

适用设备为鲲鹏 C8-600 和 C8-601，板卡标识 WT9106，扩容规格为 512 MiB RAM 和 128 MiB SPI-NAND，使用匹配的 BL2、FIP 及 NMBM/UBI 布局。原厂 16 MiB SPI-NOR 和 C8-660 的固件布局不同。

## 已运行 SWRT

1. 在 [Releases](https://github.com/SlAlot/SWRT-NRadio-C8-600/releases/latest) 下载 `*-squashfs-sysupgrade.itb` 和 `SHA256SUMS`。核对 SHA256 后，在「系统 → 备份与升级」备份当前配置。
2. 上传 `sysupgrade.itb` 并确认镜像检查通过。保留配置前，留意旧版 LAN1/LAN3 标签互换对单口 VLAN 的影响。
3. 安装 1.2.1 后，可在「系统 → SWRT 在线更新」检查后续正式版本。若网络无法直连 GitHub，可以在同一页面切换至国内加速。

## 首刷或恢复

需要串口和适配扩容布局的引导环境。保存本机 NAND、Factory 校准数据和引导分区备份。串口参数为 115200 8N1。通过 U-Boot 的 RAM/TFTP 启动入口加载发布附件 `*-initramfs-recovery.itb`。使用扩容 FIP 时按设备环境选择 `config-1#mt7981-nradio-wt9106`。

RAM 系统启动后检查 `ubus call system board`、`/proc/meminfo`、`/proc/mtd` 和 `ubinfo -a`。设备标识应为 `nradio,wt9106`，逻辑 UBI 分区大小为 `0x07280000`，擦除块为 `0x20000`。从 RAM 系统对升级镜像执行 `sysupgrade -T <镜像>`。确认布局和镜像检查都通过后，用 `sysupgrade -n <镜像>` 安装。匹配扩容规格的引导和校准数据由设备所有者准备。

首次登录地址为 `192.168.17.1`，账号 `root`，初始密码为空。登录后设置管理密码和 Wi-Fi 密码。
