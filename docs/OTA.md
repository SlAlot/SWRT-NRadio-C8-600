# C8-600 在线更新

设备通过 [公开 GitHub Releases](https://github.com/SlAlot/SWRT-NRadio-C8-600/releases) 查询正式版本。打开「系统 → SWRT 在线更新」，可选 GitHub 直连或 `gh-proxy.com` 国内加速。1.2.1 固件内置的 jq 缺少正则支持，无法解析发布信息。1.2.1 或更早版本用户请按照 [安装说明](INSTALL.md) 手动升级到最新版本。

## 更新包

正式标签使用 `SWRT-C8-600-X.Y.Z`。发布附件是对应版本的 `*-squashfs-sysupgrade.itb`、`ota.json` 和 `ota.json.sig`。设备校验签名、设备标识、128 MiB NAND 布局、版本、文件名、大小及 SHA256，最后调用 OpenWrt 自带的镜像检查。下载完成后由用户选择是否保留配置并确认刷写。

维护者在 `SHA256SUMS` 校验通过后用本地 Ed25519 签名私钥生成清单。命令可用 `--openssl` 指定 OpenSSL 路径。

```sh
python3 scripts/sign-ota.py /path/to/build/*-squashfs-sysupgrade.itb --key /path/to/ota-ed25519.pem
```

脚本在镜像旁生成 `ota.json` 和 `ota.json.sig`，并用固件内置公钥回验。维护者将同一版本的两个签名附件、升级镜像及其校验和上传到 GitHub Release 草稿，核对齐备后发布。签名私钥保存在仓库外。
