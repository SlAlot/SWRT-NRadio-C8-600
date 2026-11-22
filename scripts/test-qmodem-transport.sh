#!/usr/bin/env bash
set -euo pipefail

feed=$(realpath "${1:?Usage: test-qmodem-transport.sh PREPARED_QMODEM_FEED}")
qmodem="$feed/application/qmodem/files"
helper="$qmodem/usr/libexec/qmodem-usb-health"
test -x "$helper"
for script in "$helper" "$qmodem/etc/init.d/"{qmodem_init,qmodem_network} "$qmodem/usr/share/qmodem/modem_dial.sh"; do
    sh -n "$script"
done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export QMODEM_RUN="$work/run" QMODEM_SYSFS_ROOT="$work/sys" QMODEM_UPTIME="$work/uptime"
# Exercise the installed implementation against fake sysfs and native redial.
. "$helper" ''
service=mock_service
usb="$work/usb/2-1"
net="$sys/class/net/cell0"
dir="$run/slot0_dir"
mkdir -p "$net/queues/tx-0" "$net/statistics" "$usb/2-1:1.4" "$work/subsystem/usb" "$dir" "$work/drivers"
ln -s "$usb/2-1:1.4" "$net/device"
ln -s "$work/subsystem/usb" "$net/device/subsystem"

# Do not let the development host's full jq hide a dependency on the optional
# regex functions, which are omitted from the actual router build.
jq() {
    local arg
    for arg do
        case "$arg" in *'test('*|*'match('*|*'capture('*|*'scan('*|*'splits('*|*'sub('*)
            printf 'jq: regex functions are not available on the target\n' >&2; return 1 ;;
        esac
    done
    command jq "$@"
}

uci() {
    [ "$1 $2" = '-q get' ] || return 1
    case "$3" in
        qmodem.slot0) echo modem-device ;;
        qmodem.slot0.data_interface) echo "${physical_type:-usb}" ;;
        qmodem.slot0.path) echo "${usb_owner:-$usb}" ;;
        qmodem.slot0.enable_dial) echo "${dial_enabled:-1}" ;;
        qmodem.slot0.en_bridge) echo "${uci_bridge:-0}" ;;
        qmodem.main.usb_tx_recovery) echo "${recovery_enabled:-1}" ;;
        network.wan0.modem_config|network.wan0v6.modem_config) echo "${logical_owner:-slot0}" ;;
        network.wan0.device) echo cell0 ;;
        network.wan0v6.device) echo "${v6_device:-@wan0}" ;;
        *) return 1 ;;
    esac
}
ubus() {
    case "$2" in network.interface.wan0|network.interface.wan0v6) ;; *) return 1 ;; esac
    [ "$1 $3" = 'call status' ] || return 1
    printf '{"up":%s,"autostart":%s,"dynamic":false,"l3_device":"%s"}\n' \
        "${net_up:-true}" "${net_autostart:-true}" "${live_device:-cell0}"
    if [ "${race:-}" = during-checks ]; then echo 501 > "$net/statistics/tx_packets"; fi
}
logger() { printf '%s\n' "$*" >> "$work/log"; }
mock_service() {
    [ "$1" = recover_usb ] || return 2
    shift
    case "${race:-}" in
        tx-progress) echo 501 > "$net/statistics/tx_packets" ;;
        unplug) echo 16 > "$net/ifindex" ;;
        manual-redial) echo next > "$dir/generation" ;;
        stale) echo '1200.00 0.00' > "$uptime" ;;
    esac
    claim "$@" && printf '%s\n' "$1" >> "$work/recovered"
}

fixture() {
    local protocol=$1 driver=$2 generation=${3:-dial1} v4=${4-wan0} v6=${5-wan0v6} routed=${6:-true}
    mkdir -p "$work/drivers/$driver"
    ln -sfn "$work/drivers/$driver" "$net/device/driver"
    printf '%s\n' "$generation" > "$dir/generation"
    jq -n --arg driver "$protocol" --arg generation "$generation" --arg v4 "$v4" --arg v6 "$v6" --argjson routed "$routed" \
        '{driver:$driver, generation:$generation, usb_routed:$routed, data_device:"cell0", network4:$v4, network6:$v6}' > "$dir/backend.json"
    echo 1 > "$net/carrier"
    echo 15 > "$net/ifindex"
}
tick() {
    local now
    printf '%s.00 0.00\n' "$1" > "$uptime"
    printf '%s\n' "$2" > "$net/queues/tx-0/tx_timeout"
    printf '%s\n' "${3:-500}" > "$net/statistics/tx_packets"
    monotonic_now
    watch_step slot0 || :
}
reset_samples() { rm -f "$dir/usb-recovery.sample" "$dir/usb-recovery.last"; : > "$work/recovered"; }
stall() { tick 1000 19; tick 1005 20; tick 1010 21; tick 1015 22; }
no_recovery() { test ! -s "$work/recovered" && test ! -e "$dir/usb-recovery.last"; }

for entry in qmi:qmi_wwan mbim:cdc_mbim ncm:cdc_ncm ncm:huawei_cdc_ncm ecm:cdc_ether rndis:rndis_host; do
    fixture "${entry%:*}" "${entry#*:}"
    reset_samples
    stall
    test "$(cat "$work/recovered")" = slot0
    test "$(cat "$dir/usb-recovery.last")" = 1015
    tick 1020 23
    test "$(wc -l < "$work/recovered")" -eq 1
done

# IPv6-only routes bind the data device; dual-stack preserves the netifd alias.
reset_samples; fixture qmi qmi_wwan dial1 - wan0v6
v6_device=cell0 stall
test "$(cat "$work/recovered")" = slot0

# Old timeouts, a single transient stall, TX that is still making progress,
# replacing the adapter/generation, and missed samples must not trigger redial.
reset_samples; fixture qmi qmi_wwan
tick 1000 19; tick 1005 19; tick 1010 20; tick 1015 20; tick 1020 20
tick 1025 21 501; tick 1030 22 502; tick 1035 23 503
tick 1040 24 503
echo 16 > "$net/ifindex"
tick 1045 25 503; tick 1050 26 503
fixture qmi qmi_wwan dial2
tick 1055 27 503; tick 1060 28 503; tick 1080 29 503
no_recovery

# Verify state/topology again at action time, not just in the polling pass.
for race in tx-progress during-checks unplug manual-redial stale; do
    reset_samples; fixture qmi qmi_wwan
    stall
    no_recovery
done
unset race
reset_samples; fixture qmi qmi_wwan; dial_enabled=0 stall; no_recovery
reset_samples; fixture qmi qmi_wwan; recovery_enabled=0 stall; no_recovery
reset_samples; fixture qmi qmi_wwan; logical_owner=slot1 stall; no_recovery
reset_samples; fixture qmi qmi_wwan; net_autostart=false stall; no_recovery
reset_samples; fixture qmi qmi_wwan; net_up=false stall; no_recovery
reset_samples; fixture qmi qmi_wwan; live_device=eth0 stall; no_recovery
reset_samples; fixture qmi qmi_wwan; physical_type=pcie stall; no_recovery
reset_samples; fixture qmi qmi_wwan; uci_bridge=1 stall; no_recovery
reset_samples; fixture qmi qmi_wwan dial1 wan0 wan0v6 false; stall; no_recovery
reset_samples; fixture qmi qmi_wwan dial1 'wan0 wan1' wan0v6; stall; no_recovery
reset_samples; fixture qmi qmi_wwan dial1 '' wan0v6; stall; no_recovery
reset_samples; fixture qmi qmi_wwan; ln -s "$work" "$net/upper_vlan7"; stall; no_recovery
rm "$net/upper_vlan7"
reset_samples; fixture qmi qmi_wwan_q; stall; no_recovery
reset_samples; fixture qmi qmi_wwan; echo 0 > "$net/carrier"; stall; no_recovery

# Exercise the real init-script dispatch with the hardware actions stubbed out.
# Manual and automatic paths must take the same lock before touching a session.
(
    initscript=/etc/init.d/qmodem_network
    extra_command() { :; }
    qmodem_valid_instance() { [ "$1" = slot0 ]; }
    procd_lock() { lock_held=1; }
    claim_usb() {
        test "${lock_held:-0}" = 1 && test "${reject:-0}" = 0 || return 1
        printf 'claim %s\n' "$*"
    }
    . <(sed '/^\. "\$SCRIPT_DIR\/instance.sh"$/d; s|/usr/libexec/qmodem-usb-health claim |claim_usb |' \
        "$qmodem/etc/init.d/qmodem_network")
    _hang() { test "${lock_held:-0}" = 1 && printf 'hang %s\n' "$*"; }
    rc_procd() { test "${lock_held:-0}" = 1 && printf 'dial %s\n' "$*"; }
    test "$(hang slot0)" = 'hang slot0'
    test "$(dial slot0)" = 'dial _dial slot0'
    test "$(recover_usb slot0 dial1 cell0 15 500)" = $'claim slot0 dial1 cell0 15 500\nhang slot0\ndial _dial slot0'
    if rejected=$(reject=1 recover_usb slot0 dial1 cell0 15 500); then
        exit 1
    fi
    test -z "$rejected"
)
grep -Fq '/usr/libexec/qmodem-usb-health watch' "$qmodem/etc/init.d/qmodem_init"
grep -Fq 'usb_routed:$usb,data_device:$device,network4:$net4,network6:$net6' "$qmodem/usr/share/qmodem/modem_dial.sh"
echo 'QModem USB TX watchdog recovery, cooldown, ownership and session-race regressions passed'
