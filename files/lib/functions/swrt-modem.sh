#!/bin/sh

swrt_modem_list() {
	config_load qmodem || return 0
	config_foreach swrt_modem_row modem-device
}

swrt_modem_row() {
	local section="$1" path slot port override state name alias metric
	config_get state "$section" state
	[ "$state" != disabled ] || return 0
	config_get path "$section" path
	[ -n "$path" ] && [ -e "$path" ] || return 0
	path=${path%/}
	slot=${path##*/}
	case "$slot" in ''|*[!A-Za-z0-9_.:-]*) return 0 ;; esac
	config_get port "$section" at_port
	config_get override "$section" override_at_port
	if [ -n "$override" ]; then
		qmodem_port_owned "$section" "$override" || return 0
		port="$override"
	fi
	case "$port" in /dev/*) ;; *) return 0 ;; esac
	[ -c "$port" ] || return 0
	config_get name "$section" name
	config_get alias "$section" alias
	case "$alias" in ''|-|*[!A-Za-z0-9_]*) alias="$section" ;; esac
	config_get metric "$section" metric
	case "$metric" in ''|*[!0-9]*) metric=999 ;; esac
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$section" "$slot" "$port" "$alias" "$metric" "${name:--}"
}

swrt_net_up() {
	ubus -t 2 call "network.interface.$1" status 2>/dev/null | jq -e '
		.up == true and (.l3_device | type == "string") and
		(((.["ipv4-address"] // []) + (.["ipv6-address"] // [])) | length > 0)' >/dev/null
}

swrt_modem_usb_up() {
	[ "$(uci -q get "network.$2.modem_config")" = "$1" ] || return 1
	[ "$(uci -q get "network.$2.device")" != cpe ] && swrt_net_up "$2"
}

swrt_selected_modem() {
	local section slot port alias metric name priority
	swrt_modem_list | while IFS="$(printf '\t')" read -r section slot port alias metric name; do
		priority=1
		if swrt_modem_usb_up "$section" "$alias"; then priority=0; fi
		printf '%s\t%s\t%s\t%s\n' "$priority" "$metric" "$section" "$port"
	done | sort -k1,1n -k2,2n -k3,3 | awk 'NR == 1 {print $3, $4}'
}

swrt_phy_up() {
	ubus -t 2 call network.interface dump 2>/dev/null | jq -e '
		any(.interface[]; .up == true and .l3_device == "cpe" and
			(((.["ipv4-address"] // []) + (.["ipv6-address"] // [])) | length > 0))' >/dev/null
}
