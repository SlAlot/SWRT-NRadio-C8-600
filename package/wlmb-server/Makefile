include $(TOPDIR)/rules.mk

PKG_NAME:=wlmb-server
PKG_VERSION:=1.1.7
PKG_RELEASE:=1
PKG_LICENSE:=LicenseRef-WLMB-NonCommercial
PKG_MAINTAINER:=SlAlot

include $(INCLUDE_DIR)/package.mk

define Package/wlmb-server
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Network Panel by SlAlot
  DEPENDS:=@aarch64 +libgcc +ubus +rpcd +rpcd-mod-iwinfo +luci-base +uci
endef

define Package/wlmb-server/conffiles
/etc/config/network_panel
endef

define Build/Compile
endef

define Package/wlmb-server/install
	$(INSTALL_DIR) $(1)
	$(CP) ./payload/. $(1)/
endef

$(eval $(call BuildPackage,wlmb-server))
