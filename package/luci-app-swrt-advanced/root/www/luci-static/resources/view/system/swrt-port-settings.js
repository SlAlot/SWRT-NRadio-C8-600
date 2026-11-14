'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

const uplink = rpc.declare({ object: 'luci.swrt_advanced', method: 'uplink', reject: true });
const setPortMode = rpc.declare({
	object: 'luci.swrt_advanced', method: 'set_port_mode', params: ['mode'], reject: true
});

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load() {
		return uplink().catch(() => null);
	},

	render(data) {
		const writable = L.hasViewPermission();
		const roleNames = { lan: 'LAN', wan: 'WAN', isolated: '等待识别' };
		const modeNames = { usb: 'USB', phy: '千兆 PHY' };
		const role = E('strong', {}, '读取中');
		const mode = E('strong', {}, '读取中');
		const links = E('div', { 'class': 'swrt-modems' });
		const note = E('p', { 'class': 'np-hint', role: 'status', 'aria-live': 'polite' });
		let pending = false;
		let selectionChanged = false;
		const select = (id, options) => E('select', { id, 'class': 'np-input' },
			options.map(([value, label]) => E('option', { value }, label)));
		const port = select('swrt-port', [['auto', '自动识别 LAN / WAN'], ['lan', '固定 LAN'], ['wan', '固定 WAN']]);
		const button = E('button', { type: 'button', 'class': 'np-btn primary', disabled: '' }, '保存并应用');
		port.value = data?.port_mode || 'wan';
		port.addEventListener('change', () => { selectionChanged = true; note.textContent = ''; });

		function update(status) {
			if (!status || !Array.isArray(status.modems)) {
				role.textContent = mode.textContent = '暂时无法读取';
				return;
			}
			if (!pending && !selectionChanged)
				port.value = status.port_mode || 'wan';
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
		}

		async function save() {
			if (pending || !writable) return;
			const selected = port.value;
			pending = true;
			button.disabled = port.disabled = true;
			button.classList.add('spinning');
			button.textContent = '正在应用…';
			note.textContent = '正在切换第四个千兆口…';
			try {
				const result = await setPortMode(selected);
				if (!result?.ok)
					throw new Error(result?.message || '无法保存第四口设置。');

				// Refresh Apollo's change counter from LuCI, preserving unrelated staged edits.
				ui.changes.init()?.catch(() => {});
				const deadline = Date.now() + 12000;
				do {
					const status = await uplink().catch(() => null);
					update(status);
					if (status?.port_mode === selected && status.running_port_mode === selected &&
					    (selected === 'auto' || status.role === selected)) {
						selectionChanged = false;
						note.textContent = selected === 'auto'
							? '已启用自动识别，插线后根据 DHCP 响应判断角色。'
							: '已切换为固定 ' + roleNames[selected] + '。';
						return;
					}
					await new Promise(resolve => window.setTimeout(resolve, 750));
				} while (Date.now() < deadline);
				note.textContent = '配置已保存，暂未确认第四口的运行状态。可重试应用。';
			} catch (err) {
				note.textContent = err.message || '应用失败，请重试。';
			} finally {
				pending = false;
				button.disabled = port.disabled = false;
				button.classList.remove('spinning');
				button.textContent = '保存并应用';
			}
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
					E('p', { 'class': 'np-hint' }, '切换前请通过其他 LAN 口或 Wi-Fi 管理设备。自动模式按上游 DHCP 响应识别 WAN。PPPoE、静态 IP 或纯 IPv6 上游请选择固定 WAN。')]),
				card('蜂窝上联', [field('当前模式', mode),
					E('p', { 'class': 'np-hint' }, '通过 QModem 按模组说明切换模式，切换后重启设备。'), links])
			]),
			E('div', { 'class': 'np-actions swrt-save' }, [button, note])
		]);
		update(data);
		poll.add(async () => {
			if (pending || !root.isConnected) return;
			const status = await uplink().catch(() => null);
			if (!pending) update(status);
		}, 5);
		return root;
	}
});
