'use strict';
'require view';
'require rpc';
'require uci';
'require poll';
'require ui';

const uplink = rpc.declare({ object: 'luci.swrt_advanced', method: 'uplink', reject: true });

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load() {
		return Promise.all([uci.load('swrt_uplink'), uplink().catch(() => null)]);
	},

	render(data) {
		const writable = L.hasViewPermission();
		const section = 'main';
		const cfg = 'swrt_uplink';
		const roleNames = { lan: 'LAN', wan: 'WAN', isolated: '等待识别' };
		const modeNames = { usb: 'USB', phy: '千兆 PHY' };
		const role = E('strong', {}, '读取中');
		const mode = E('strong', {}, '读取中');
		const links = E('div', { 'class': 'swrt-modems' });
		const note = E('p', { 'class': 'np-hint', role: 'status', 'aria-live': 'polite' });
		let pending = false;
		let saved = false;
		const select = (id, options) => E('select', { id, 'class': 'np-input' },
			options.map(([value, label]) => E('option', { value }, label)));
		const port = select('swrt-port', [['auto', '自动识别 LAN / WAN'], ['lan', '固定 LAN'], ['wan', '固定 WAN']]);
		const button = E('button', { type: 'button', 'class': 'np-btn primary', disabled: '' }, '保存设置');
		port.value = uci.get(cfg, section, 'port_mode') || 'wan';

		function update(status) {
			if (!status || !Array.isArray(status.modems)) {
				role.textContent = mode.textContent = '暂时无法读取';
				return;
			}
			role.textContent = status.role === 'isolated' && !status.carrier ? '未插线' : roleNames[status.role] || '等待识别';
			mode.textContent = modeNames[status.mode] || '未连接';
			links.replaceChildren(...status.modems.map(modem => {
				return E('div', { 'class': 'swrt-modem' }, [
					E('strong', {}, modem.name === '-' ? '蜂窝模组' : modem.name),
					E('span', { 'class': 'np-hint' }, modem.slot),
					E('span', { 'class': 'np-chip' }, 'USB AT 可用')
				]);
			}));
			links.hidden = status.modems.length === 0;
			note.textContent = saved ? '设置已保存。' : '';
		}

		function save() {
			if (pending || !writable) return;
			pending = true;
			button.disabled = true;
			uci.set(cfg, section, 'port_mode', port.value);
			return uci.save().then(() => uci.apply()).then(() => { saved = true; return uplink(); }).then(update)
				.catch(err => ui.addNotification(null, E('p', {}, String(err.message || err)), 'error'))
				.finally(() => { pending = false; button.disabled = false; });
		}

		button.addEventListener('click', save);
		button.disabled = port.disabled = !writable;
		const field = (title, content, id) => E('div', { 'class': 'np-info-field' }, [
			E(id ? 'label' : 'span', { 'class': 'np-info-label', ...(id ? { for: id } : {}) }, title), content
		]);
		const card = (title, body) => E('section', { 'class': 'np-native-card' }, [
			E('div', { 'class': 'np-native-card-head' }, E('strong', {}, title)),
			E('div', { 'class': 'np-native-card-body swrt-fields' }, body)
		]);
		const root = E('div', { 'class': 'np-root swrt-advanced', id: 'swrt-advanced' }, [
			E('link', { rel: 'stylesheet', href: L.resource('wlmb-server/panel.css') }),
			E('link', { rel: 'stylesheet', href: L.resource('swrt-advanced.css') }),
			E('div', { 'class': 'np-page-heading' }, [
				E('h2', { 'class': 'np-page-title' }, 'SWRT 高级设置'),
				E('a', { href: L.url('admin', 'system', 'swrt-upgrade'), 'class': 'np-btn' }, '在线更新')
			]),
			E('div', { 'class': 'swrt-main-grid' }, [
				card('第四个千兆口', [field('当前角色', role), field('工作方式', port, 'swrt-port'),
					E('p', { 'class': 'np-hint' }, '自动模式按上游 DHCP 响应识别 WAN。PPPoE、静态 IP 或纯 IPv6 上游请选择固定 WAN。')]),
				card('蜂窝上联', [field('当前模式', mode),
					E('p', { 'class': 'np-hint' }, '通过 QModem 按模组说明切换模式，切换后重启设备。'), links])
			]),
			E('div', { 'class': 'np-actions swrt-save' }, [button, note])
		]);
		update(data[1]);
		poll.add(() => !pending && root.isConnected ? uplink().then(update).catch(() => update(null)) : Promise.resolve(), 5);
		return root;
	}
});
