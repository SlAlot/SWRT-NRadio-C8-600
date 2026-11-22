# USB modem transmit-stall diagnosis

An enumerated USB modem and an active QMI/MBIM session do not prove the data interface can transmit. Linux exposes its actual TX watchdog counter as `/sys/class/net/<netdev>/queues/tx-0/tx_timeout`. A timeout means the transmit queue stopped making progress, not that the modem necessarily rejected the PDP or that DNS failed.

## Observed case: 2026-11-22 (UTC+08:00)

The WT9106 router was booted into SWRT 1.2.6 with Linux 6.12.103. The RG520N-EB (RG520NEBDFR03A06M4G, USB `2c7c:0801`) used USB 3 and the stock `qmi_wwan` driver. The two route-bound MWAN probes failed at 19:05:08 and 19:05:11. At 19:05:15 the kernel recorded the first `wwan0: NETDEV WATCHDOG` timeout. MWAN marked the interface offline at 19:05:39. At 19:07:42 QModem began stopping the dial session, and the interface and MWAN tracking came back at 19:08:01. The kernel log showed no USB disconnect/re-enumeration there. After recovery the card still used raw IP, USB autosuspend was disabled, and the TX timeout counter was 19.

This is evidence of a USB data-path stall and a missing recovery trigger; it does not isolate the initial fault to the adapter, the modem firmware, the USB host/PHY or the kernel driver. It is different from a bad link-format negotiation that prevents traffic immediately after a fresh dial. The 1.2.8/1.2.9 negotiation changes do not themselves detect a stalled TX queue.

## Recovery and verification

The QModem package samples the kernel timeout and successful-transmit counters for routed, single-netdev USB QMI, MBIM, NCM, ECM and RNDIS. The first valid sample only sets a baseline. At least three new watchdog events with no successful transmit progress over at least ten seconds can request redial. Before stopping and dialing that one instance, QModem takes the same procd service lock used by manual dial/hang and rechecks the generation, device identity, interface ownership and administrative state. A five-minute cooldown bounds retries. No public target, modem reset, router reboot, DNS change, or USB speed downgrade is used. `qmodem.main.usb_tx_recovery=0` opts out. Bridge, multiplexed and PCIe devices are not subject to this policy.

The QModem `3.4.0_rc3-r5` firmware-build package targets the 1.2.9 baseline and later. Do not install it on 1.2.6: that release has a different dial implementation. The separate 1.2.6 test package and rollback package were built from the 1.2.6 image's QModem payload; neither changes the connection manager, kernel drivers, or UCI configuration. Use a maintenance window: the worker is supervised by `qmodem_init`, and the updated dial process must start once to register the live USB endpoint. The health worker must also run with the firmware's regex-free jq build.

Validate on hardware by reproducing the stall with the same SIM, modem firmware and link speed, then checking `logread -e qmodem_usb_health`, `ip -s link show dev <netdev>`, and whether bound IPv4/IPv6 traffic resumes. For a remaining stall, compare USB 3 and USB 2 in a controlled test and capture USB transfer status (for example by enabling usbmon in a diagnostic kernel); redact packet payloads and modem/subscriber identifiers before sharing. A successful redial validates recovery, not prevention of every underlying stall.
