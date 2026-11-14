'use strict';
'require network';

return network.registerProtocol('qmodem_runtime', {
	getI18n() {
		return 'QModem 蜂窝拨号';
	},

	isCreateable() {
		return Promise.reject('请在 QModem 中配置模组。拨号接口由 QModem 自动创建。');
	}
});
