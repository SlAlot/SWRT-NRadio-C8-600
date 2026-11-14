# 第三方来源与许可

版本和校验值见 [sources.lock.json](../sources.lock.json)。每个 GitHub Release 的源代码归档对应所发布的适配源码、构建脚本、包配置和板级设备树。上游 ImmortalWrt 的包、LuCI 和其他 feeds 的提交锁定在其 `feeds.conf.default`。

| 组件 | 源码与许可 |
| --- | --- |
| ImmortalWrt / OpenWrt | [ImmortalWrt 25.12.2](https://github.com/immortalwrt/immortalwrt/tree/4fc16f2985a358bd43bb522e43f05395fcbd6ed5)，主项目 GPL-2.0-only，各组件另有许可 |
| Linux | [Linux 6.12.103](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/?h=v6.12.103)，GPL-2.0-only，详见内核 COPYING 和 SPDX 标识 |
| QModem / TOM | [QModem 固定提交](https://github.com/FUjr/QModem/tree/1eae68976ad018af2bdde7204b01a2b0a19b7e69)，含 TOM 定制拨号核心的源码及其声明 |
| OpenClash / Mihomo | [OpenClash 固定提交](https://github.com/vernesong/OpenClash/tree/e553e82e01c697aefbe1555261a503f425e00ccd) 与 [Mihomo v1.19.34](https://github.com/MetaCubeX/mihomo/tree/v1.19.34)，各自保留原有许可。构建为 OpenClash 和 MWAN3 增加上联探测标记兼容处理 |
| 网络面板 / 首页 / 主题 | 基于 SlAlot 的网络面板（wlmb-server）。来源 [wlmb-server v1.1.7](https://github.com/SlAlot/wlmb-server/tree/a4cc6650336714ff2e32350f0ea1feabb7b396ea)、[网络面板首页](https://github.com/SlAlot/luci-app-wlmbstart/tree/fce222f945d0cd0391e4591dda84126356839dd2)、[Apollo 主题](https://github.com/SlAlot/luci-theme-apollo/tree/d27d4cb94d5523ad6b351652f2e34770a0d786ff)。使用公开上游版本，许可为各自仓库的非商业条款，保留版权和第三方声明 |
| iStore | [iStore 固定提交](https://github.com/istoreos/istore/tree/a97ace34f2da358a015b094d326bba2697697f2e)，MIT，界面与其他依赖见各自源码和许可 |

`scripts/prepare.sh` 记录第三方包的构建处理和上游修改，`scripts/apply-board.py` 记录板级集成。发布附件中的软件清单列出所装软件和版本。上游源与构建可通过标签下的源码归档、版本锁文件和构建脚本获取。
