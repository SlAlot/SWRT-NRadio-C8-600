#!/usr/bin/env bash
set -eu

project=$(cd "$(dirname "$0")/.." && pwd)
worker="$project/files/usr/sbin/swrt-leds"
sh -n "$worker"
sh -n "$project/files/etc/init.d/swrt-leds"
source <(sed '/^case "\$1" in$/,$d' "$worker")
source "$project/files/lib/functions/swrt-modem.sh"

scratch=$(mktemp -d)
trap 'rm -f "$LED_DIR/$LED_5G/brightness" "$LED_DIR/$LED_4G/brightness" "$LED_DIR/$LED_WIFI/brightness"; rmdir "$scratch/built" "$scratch/external" "$LED_DIR/$LED_5G" "$LED_DIR/$LED_4G" "$LED_DIR/$LED_WIFI" "$scratch"' EXIT
LED_DIR="$scratch"
QMODEM="$scratch"
LED_5G=indicator-5g
LED_4G=indicator-4g
LED_WIFI=indicator-wifi
for led in "$LED_5G" "$LED_4G" "$LED_WIFI"; do
    mkdir "$LED_DIR/$led"
    echo 0 > "$LED_DIR/$led/brightness"
done

assert_equal() {
    if [ "$1" != "$2" ]; then
        printf 'LED regression (%s): expected <%s>, got <%s>\n' "$3" "$1" "$2" >&2
        exit 1
    fi
}

at() {
    case "$2" in
        AT+CPIN\?) printf '%b\r\n' "$sim_reply" ;;
        AT+CEREG\?) printf '%b\r\n' "$eps_reply" ;;
        AT+C5GREG\?) printf '%b\r\n' "$nr_reply" ;;
        AT+COPS\?) printf '%b\r\n' "$operator_reply" ;;
        *) return 1 ;;
    esac
}

ubus() {
    [ "$*" = '-t 4 call qmodem cell_info {"config_section":"built_in"}' ] || return 1
    jq -n --arg mode "$MODE" '{modem_info: [{key: "network_mode", value: $mode}]}'
}

check_cellular() {
    MODE="$2"
    eps_reply="$3"
    nr_reply="$4"
    operator_reply="${5:-}"
    sim_reply="${6:-+CPIN: READY}"
    assert_equal "$1" "$(cellular_status built_in /dev/null)" "$MODE / $eps_reply / $nr_reply / $operator_reply"
}

check_cellular 5g 'NR5G-SA Mode' '+CEREG: 0,0' '+C5GREG: 2,1,"000123","045678",11'
check_cellular 5g 'EN-DC Mode' '+CEREG: 1\r\n+CEREG: 0,5' '+C5GREG: 0,0' '+COPS: 0,0,"Example",7'
check_cellular 4g 'LTE Mode' '+CEREG: 2,1,"0ABC","1234",7' '+C5GREG: 0,0'
check_cellular off 'LTE Mode' '+CEREG: 0,2' '+C5GREG: 0,0' '+COPS: 0,0,"Example",7'
check_cellular off 'NR5G-SA Mode' '+CEREG: 0,0' '+C5GREG: 0,3' '+COPS: 0,0,"Example",11'
check_cellular off 'LTE Mode' '+CEREG: 0,1' '' '' '+CME ERROR: 10'
check_cellular off 'LTE Mode' '+CEREG: 0,1' '' '' '+CPIN: SIM PIN'
check_cellular 5g 'NR5G-SA Mode' '' 'ERROR' '+COPS: 0,0,"Example, Inc.",11'
check_cellular 5g '' '+CEREG: 0,1' '' '+COPS: 0,2,"46000",13'
check_cellular 5g '' '+CEREG: 0,0' '+C5GREG: 0,5'
check_cellular 5g '' '+CEREG: 2,1,"0ABC","1234",13' ''
check_cellular 4g '' '+CEREG: 2,5,"0ABC","1234",7' ''
check_cellular 4g '' '+CEREG: 0,1' '' '+COPS: 0,2,"46000",7'
check_cellular off '' '' '' '+COPS: 0,2,"46000",8'
check_cellular unknown '' '+CEREG: 5' '' '+COPS: 0'

config_load() { [ "$1" = qmodem ]; }
uci() {
    case "$*" in
        '-q get network.built_in.modem_config') printf '%s\n' built_in ;;
        '-q get network.ext.modem_config') printf '%s\n' ext ;;
        *) return 1 ;;
    esac
}
swrt_net_up() { [ "$1" = "$online" ]; }
mkdir "$scratch/built" "$scratch/external"
config_foreach() {
    local section
    [ "$2" = modem-device ] || return 1
    for section in $sections; do "$1" "$section"; done
}
config_get() {
    local value=
    case "$2:$3" in
        built_in:path) value="$scratch/built" ;;
        ext:path) value="$scratch/external" ;;
        built_in:at_port) value=/dev/null ;;
        ext:at_port) value=/dev/zero ;;
        invalid:state) value=disabled ;;
        built_in:name) value=srm821 ;;
        ext:name) value=rm520n-gl ;;
        built_in:metric) value=11 ;;
        ext:metric) value=12 ;;
    esac
    printf -v "$1" '%s' "$value"
}
sections='ext built_in invalid'
online=
assert_equal 'built_in /dev/null' "$(swrt_selected_modem)" 'priority without a model name rule'
online=ext
assert_equal 'ext /dev/zero' "$(swrt_selected_modem)" 'active USB modem preferred automatically'
sections='ext invalid'
online=
assert_equal 'ext /dev/zero' "$(swrt_selected_modem)" 'single replacement modem'

timeout() { cellular_status "$4" "$5"; }
check_leds() {
    assert_equal "$1" "$(cat "$LED_DIR/$LED_5G/brightness"):$(cat "$LED_DIR/$LED_4G/brightness")" "$2"
}
last_modem=
misses=0
sections=built_in
MODE='EN-DC Mode'
eps_reply='+CEREG: 0,1'
nr_reply=
operator_reply=
update_cellular_leds
check_leds 1:0 'only 5G is lit'
MODE='LTE Mode'
update_cellular_leds
check_leds 0:1 'transition to 4G'
MODE=
eps_reply=
for ((i = 0; i < 10; i++)); do update_cellular_leds; done
check_leds 0:1 'brief AT failure retains the previous state'
update_cellular_leds
check_leds 0:0 'expired AT state clears the indicators'
MODE='LTE Mode'
eps_reply='+CEREG: 0,1'
update_cellular_leds
sections=
update_cellular_leds
check_leds 0:0 'removed modem clears indicators immediately'

iw() { [ "$1" = dev ] && printf '%b\n' "$wireless"; }
wireless='phy#1\n\tInterface phy1-ap0\n\t\tssid Test-5GHz\n\t\ttype AP'
update_wifi_led
assert_equal 1 "$(cat "$LED_DIR/$LED_WIFI/brightness")" '5 GHz only'
wireless='phy#0\n\tInterface phy0-ap0\n\t\tssid Test 2.4 GHz\n\t\ttype AP'
update_wifi_led
assert_equal 1 "$(cat "$LED_DIR/$LED_WIFI/brightness")" '2.4 GHz only'
wireless='phy#0\n\tInterface phy0-sta0\n\t\ttype managed'
update_wifi_led
assert_equal 0 "$(cat "$LED_DIR/$LED_WIFI/brightness")" 'no active SSID'
echo 'Front-panel LED regressions passed'
