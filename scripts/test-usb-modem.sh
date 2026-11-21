#!/usr/bin/env bash
set -euo pipefail

feed=$(realpath "${1:?Usage: test-usb-modem.sh PATCHED_QMODEM_FEED}")
qmodem="$feed/application/qmodem"
scripts="$qmodem/files/usr/share/qmodem"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

load_function() {
    local file=$1 name=$2
    eval "$(awk -v start="$name()" 'index($0, start) == 1 { active=1 }
        active { print } active && $0 == "}" { exit }' "$file")"
    declare -F "$name" >/dev/null
}

# Check the actual driver's precedence on composite USB devices.
bash "$qmodem/tests/test_modem_netdev.sh"
load_function "$scripts/generic.sh" get_driver
modem_config=slot0
modem_path="$work/usb"
SCRIPT_DIR="$scripts"
export QMODEM_SYSFS_ROOT="$work/sys" MODEM_FIXTURE="$work"
mkdir -p "$modem_path/control" "$modem_path/data/net/usb0" "$work/sys/class/net" "$work/bin"
for usb_driver in qmi_wwan cdc_mbim cdc_ncm huawei_cdc_ncm cdc_ether rndis_host; do
    mkdir -p "$work/drivers/$usb_driver"
done
ln -s "$work/drivers/qmi_wwan" "$modem_path/control/driver"
ln -s "$modem_path/data" "$modem_path/data/net/usb0/device"
ln -s "$modem_path/data/net/usb0" "$work/sys/class/net/usb0"
cat > "$work/bin/uci" <<'UCI'
#!/bin/sh
case "$*" in
    '-q get qmodem.slot0') echo modem-device ;;
    '-q get qmodem.slot0.path') printf '%s\n' "$MODEM_FIXTURE/usb" ;;
    '-q get network.cell0.modem_config') printf '%s\n' "${MODEM_FIXTURE_OWNER:-slot0}" ;;
    '-q get network.cell0.proto') echo qmodem_runtime ;;
    *) exit 1 ;;
esac
UCI
chmod +x "$work/bin/uci"
export PATH="$work/bin:$PATH"
for entry in qmi_wwan:qmi cdc_mbim:mbim cdc_ncm:ncm huawei_cdc_ncm:ncm cdc_ether:ecm rndis_host:rndis; do
    ln -sfn "$work/drivers/${entry%:*}" "$modem_path/data/driver"
    [ "$(get_driver)" = "${entry#*:}" ]
done

# Vendor AT activation uses the same CID on connect and disconnect.
for name in at_dial ecm_hang refresh_host_dhcp; do load_function "$scripts/modem_dial.sh" "$name"; done
cmd_dial_command() { printf '%s\n' "$2" >> "$work/at"; }
auto_dial_hang() { return 1; }
m_debug() { :; }
at_port=/dev/fixture manufacturer=huawei platform=hisilicon pdp_index=2 pdp_type=ip apn=''
driver=ncm username='' password='' auth='' delay=''
at_dial
ecm_hang || :  # The vendor helper returns the status of its optional delay.
diff -u <(printf '%s\n' 'AT+CGDCONT=2,"IP"' 'AT^NDISDUP=2,1' 'AT^NDISDUP=2,0') "$work/at"

# Renew only the routed DHCP interface owned by this modem.
ubus() {
    [ "$2" = network.interface.cell0 ] || return 1
    case "$3" in status) printf '%s\n' "$dhcp_status" ;; renew) echo renew >> "$work/dhcp" ;; *) return 1 ;; esac
}
jsonfilter() { jq -r "${2#@}"; }
ifup() { printf 'ifup %s\n' "$1" >> "$work/dhcp"; }
interface_name=cell0 bridge_enabled=0 env4=1 proto=dhcp
dhcp_status='{"up":true,"pending":false}'
for driver in ncm ecm rndis; do refresh_host_dhcp; done
dhcp_status='{"up":false,"pending":true}'
refresh_host_dhcp
dhcp_status='{"up":false,"pending":false}'
refresh_host_dhcp
MODEM_FIXTURE_OWNER=slot1 refresh_host_dhcp
bridge_enabled=1 refresh_host_dhcp
driver=mbim refresh_host_dhcp
diff -u <(printf '%s\n' renew renew renew 'ifup cell0') "$work/dhcp"

# Verify the event resulting from an MBIM /32 or a gatewayless point-to-point lease.
: > "$work/functions"
cat > "$work/proto" <<'PROTO'
proto_init_update() { printf 'link:%s\n' "$*"; }
proto_add_ipv4_address() { printf 'address:%s\n' "$*"; }
proto_add_ipv4_route() { printf 'route:%s\n' "$*"; }
proto_add_dns_server() { printf 'dns:%s\n' "$*"; }
proto_send_update() { printf 'notify:%s\n' "$*"; }
PROTO
export QMODEM_LIB_FUNCTIONS="$work/functions" QMODEM_NETIFD_PROTO="$work/proto"
export QMODEM_RUN="$work/run" QMODEM_HOME="$scripts"
export QMODEM_INTERFACE=cell0 QMODEM_INSTANCE=slot0 QMODEM_GENERATION=current
mkdir -p "$QMODEM_RUN/slot0_dir"
printf '%s\n' current > "$QMODEM_RUN/slot0_dir/generation"
printf '%s\n' cell0 > "$QMODEM_RUN/slot0_dir/netifd-enabled"
event="$qmodem/files/usr/libexec/qmodem-ipv4-event"
result=$("$event" up usb0 10.23.0.5 255.255.255.255 10.23.0.1 223.5.5.5 0.0.0.0 0)
grep -Fx 'route:10.23.0.1 32' <<< "$result"
grep -Fx 'route:0.0.0.0 0 10.23.0.1' <<< "$result"
result=$("$event" up usb0 10.23.0.9 255.255.255.255 0.0.0.0 0.0.0.0 0.0.0.0 0)
grep -Fx 'route:0.0.0.0 0' <<< "$result"
[ "$(jq -r '.address' "$QMODEM_RUN/slot0_dir/ipv4.json")" = 10.23.0.9 ]
if QMODEM_GENERATION=stale "$event" down usb0 0.0.0.0 0.0.0.0 0.0.0.0 0.0.0.0 0.0.0.0 0; then
    exit 1
fi
echo 'USB modem driver, AT activation, DHCP renewal and IP handoff regressions passed'
