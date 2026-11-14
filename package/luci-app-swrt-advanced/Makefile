include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-swrt-advanced
PKG_VERSION:=1.2.3
PKG_RELEASE:=1
PKG_LICENSE:=AGPL-3.0-only
PKG_MAINTAINER:=SlAlot

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-swrt-advanced
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=SWRT advanced settings and online firmware updates
  DEPENDS:=+luci-base +wlmb-server +rpcd +curl +ca-bundle +jq +flock +coreutils-stat +openssl-util +fwtool
endef

define Package/luci-app-swrt-advanced/conffiles
/etc/config/swrt_upgrade
endef

define Build/Compile
endef

define Package/luci-app-swrt-advanced/install
	$(INSTALL_DIR) $(1)
	$(CP) ./root/. $(1)/
	chmod 755 $(1)/usr/libexec/swrt-upgrade $(1)/usr/libexec/rpcd/luci.swrt_advanced
endef

$(eval $(call BuildPackage,luci-app-swrt-advanced))
