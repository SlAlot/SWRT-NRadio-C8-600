# SWRT · 鲲鹏 C8-600 / C8-601

基于 ImmortalWrt 25.12.2 的 5G CPE 固件，适用于采用 **WT9106** 板卡且已扩容至 **512 MiB RAM / 128 MiB SPI-NAND** 的 NRadio 鲲鹏 C8-600 和 C8-601。内核为 Linux 6.12.103，包管理使用 APK。

[下载固件](https://github.com/SlAlot/SWRT-NRadio-C8-600/releases/latest) · [安装与升级](docs/INSTALL.md) · [在线更新](docs/OTA.md) · [版本记录](CHANGELOG.md)

## 功能

- 三个固定千兆 LAN，第四口默认用作 WAN，可在「系统 → SWRT 高级设置」切换为 LAN 或 WAN/LAN 自适应。
- QModem 使用 TOM 拨号核心。支持 USB 3.0 蜂窝数据，也支持单模组在启用以太网数据模式后经千兆 PHY 联网。USB 可继续用于 AT 和读取信号。
- 使用 ImmortalWrt 原生 MT7981 PPE/WED。MWAN3 默认优先蜂窝，有线备用。面板电源、4G、5G 和 Wi-Fi 指示灯各自显示对应状态。
- 简体中文 LuCI，集成 Apollo、网络面板、iStore、OpenClash（含 Mihomo）和 ttyd。

| 默认设置 | 值 |
| --- | --- |
| 管理地址 | `192.168.17.1` |
| 主机名 | `S-C8-600` |
| 管理账户 | `root`，初始密码为空 |
| Wi-Fi | `SWRT-660` 和 `SWRT-660-5G`，初始无密码，中国大陆信道 |

原厂 16 MiB SPI-NOR 机型采用不同布局。首刷或恢复请按 [安装说明](docs/INSTALL.md) 核对扩容规格、引导和 UBI 分区。已使用 1.2.1 或更早版本的同布局设备，先手动刷入 1.2.3 一次，后续在「系统 → SWRT 在线更新」下载并验签。

## 构建

在 Ubuntu 24.04 或 WSL2 的 Linux 文件系统下检出本仓库，以普通用户执行：

```sh
bash scripts/install-build-deps.sh
bash scripts/build-local.sh
```

通过 `SWRT_BUILD_JOBS=8` 可限制并行数。GitHub Actions 可手动运行 **Build firmware**，构建产物包含两种 FIT 镜像、软件清单、校验和与离线 APK 包。[sources.lock.json](sources.lock.json) 提供构建使用的上游版本及下载摘要。

## 源码与许可

本仓库的固件适配与构建脚本默认采用 [GPL-2.0-only](LICENSE)。带单独 SPDX 标识的文件按标识授权，SWRT 高级设置组件采用 [AGPL-3.0-only](LICENSES/AGPL-3.0-only.txt)。固件内随附的组件按各自许可证分发。

固件基于 SlAlot 的网络面板（wlmb-server），来源见 [网络面板项目](https://github.com/SlAlot/wlmb-server)。[网络面板首页](https://github.com/SlAlot/luci-app-wlmbstart) 与 [Apollo 主题](https://github.com/SlAlot/luci-theme-apollo) 也按其各自的非商业许可分发。构建直接使用这些组件的公开版本。[第三方来源与许可](docs/SOURCES.md)
