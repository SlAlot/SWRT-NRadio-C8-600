#!/usr/bin/env bash
set -eu

project=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
source <(sed '/^case "\$1" in$/,$d' "$project/files/usr/sbin/swrt-uplink")

PORT_SYS="$scratch/wan"
LAN_MEMBER="$scratch/lan-member"
log="$scratch/operations"
mkdir "$PORT_SYS"
trap 'rm -f "$PORT_SYS/carrier" "$PORT_SYS/carrier_changes" "$PORT_SYS/master" "$LAN_MEMBER" "$log"; rmdir "$PORT_SYS" "$scratch"' EXIT

fail() {
    echo "Uplink regression: $*" >&2
    cat "$log" >&2
    exit 1
}

record() { printf '%s\n' "$*" >> "$log"; }
logger() { :; }
ip() { :; }

uci() {
    return 1
}

ubus() { printf '%s\n' "$network_dump"; }

iface() {
    case "$1:$2" in
        cpephy:status|cpephy6:status) printf '{"autostart":%s}\n' "$phy_auto" ;;
        cpephy:up|cpephy:down|cpephy6:up|cpephy6:down) record "$1 $2" ;;
        wan:status) printf '{"autostart":%s}\n' "$wan_up" ;;
        wan6:status) printf '{"autostart":%s}\n' "$wan6_up" ;;
        lan:status) printf '{"device":"%s"}\n' "$lan_device" ;;
        wan:up|wan:down)
            [[ "$2" != up || ! -e "$LAN_MEMBER" ]] || fail "WAN started inside LAN"
            record "$1 $2"
            if [[ "$2" = up ]]; then wan_up=true; else wan_up=false; fi
            ;;
        wan6:up|wan6:down)
            record "$1 $2"
            if [[ "$2" = up ]]; then wan6_up=true; else wan6_up=false; fi
            ;;
        lan:add_device)
            [[ "$wan_up:$wan6_up" = false:false ]] || fail "WAN active during LAN attach"
            : > "$LAN_MEMBER"
            : > "$PORT_SYS/master"
            record "$1 $2"
            ;;
        lan:remove_device)
            rm -f "$LAN_MEMBER" "$PORT_SYS/master"
            record "$1 $2"
            ;;
        *) fail "unexpected netifd call $*" ;;
    esac
}

jsonfilter() {
    local json
    read -r json
    case "$json" in
        *br-lan*) echo br-lan ;;
        *'"autostart":true'*) echo true ;;
        *'"autostart":false'*) echo false ;;
    esac
}

udhcpc() {
    [[ "$wan_up:$wan6_up" = false:false && ! -e "$PORT_SYS/master" ]] || fail 'DHCP probe escaped isolation'
    [[ "$*" = '-i wan -n -q -t 4 -T 1 -s /bin/true' ]] || fail 'probe would run a DHCP configuration script'
    record probe
    if [[ "$scenario" = stale ]]; then echo 2 > "$PORT_SYS/carrier_changes"; fi
    [[ "$dhcp" = yes ]]
}

sleep() {
    tick=$((tick + 1))
    if [[ "$scenario" = replug ]]; then
        case "$tick" in
            2) echo 0 > "$PORT_SYS/carrier"; echo 2 > "$PORT_SYS/carrier_changes" ;;
            3) echo 1 > "$PORT_SYS/carrier"; echo 3 > "$PORT_SYS/carrier_changes"; dhcp=yes ;;
        esac
    fi
    [[ "$tick" -le "$limit" ]]
}

reset() {
    scenario="$1"
    limit="${2:-1}"
    tick=0
    wan_up=false
    wan6_up=false
    lan_device=br-lan
    dhcp=no
    rm -f "$PORT_SYS/master" "$LAN_MEMBER"
    echo 1 > "$PORT_SYS/carrier"
    echo 1 > "$PORT_SYS/carrier_changes"
    : > "$log"
}

reset upstream
dhcp=yes
watch_port auto
[[ "$(cat "$log")" = $'probe\nwan up\nwan6 up' ]] || fail 'DHCP upstream'

reset direct_client
watch_port auto
[[ "$(cat "$log")" = $'probe\nlan add_device' ]] || fail 'direct LAN client'

reset replug 3
watch_port auto
[[ "$(cat "$log")" = $'probe\nlan add_device\nlan remove_device\nprobe\nwan up\nwan6 up' ]] || fail 'LAN cable replaced with WAN'

reset stale
dhcp=yes
watch_port auto
[[ "$(cat "$log")" = probe ]] || fail 'carrier changed during DHCP probe'

reset fixed_lan
wan_up=true
wan6_up=true
watch_port lan
[[ "$(cat "$log")" = $'wan6 down\nwan down\nlan add_device' ]] || fail 'fixed LAN'

reset fixed_wan
: > "$PORT_SYS/master"
: > "$LAN_MEMBER"
watch_port wan
[[ "$(cat "$log")" = $'lan remove_device\nwan up\nwan6 up' ]] || fail 'fixed WAN'

reset unavailable_bridge
lan_device=''
watch_port auto
[[ "$(cat "$log")" = probe ]] || fail 'unavailable LAN bridge'

reset phy
phy_auto=false
network_dump='{"interface":[{"interface":"modem","device":"wwan0"},{"interface":"cpephy","device":"cpe"}]}'
apply_cellular
[[ "$(cat "$log")" = $'cpephy up\ncpephy6 up' ]] || fail 'board DHCP not started on unclaimed PHY'
reset owned_phy
phy_auto=true
network_dump='{"interface":[{"interface":"modem","device":"cpe"},{"interface":"cpephy","device":"cpe"}]}'
apply_cellular
[[ "$(cat "$log")" = $'cpephy6 down\ncpephy down' ]] || fail 'board DHCP competed with the owner of cpe'

echo 'Fourth port and PHY coexistence tests passed'
