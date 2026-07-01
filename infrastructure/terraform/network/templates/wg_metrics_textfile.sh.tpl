#!/bin/bash
# WireGuard tunnel-health metrics, written in Prometheus textfile-collector
# format for prometheus.exporter.unix's textfile block to pick up. Run on a
# timer (see the wg-metrics.timer unit installed alongside this script).
set -euo pipefail

readonly OUT_DIR="${TEXTFILE_DIR}"
readonly OUT_FILE="$OUT_DIR/wg.prom"
readonly TMP_FILE="$OUT_FILE.$$"

mkdir -p "$OUT_DIR"

{
  if wg show wg0 >/dev/null 2>&1; then
    echo "# HELP wg_interface_up Whether the wg0 WireGuard interface exists and is queryable (1) or not (0)."
    echo "# TYPE wg_interface_up gauge"
    echo 'wg_interface_up{interface="wg0"} 1'

    echo "# HELP wg_peer_latest_handshake_seconds Unix timestamp of the peer's last successful handshake (0 = never)."
    echo "# TYPE wg_peer_latest_handshake_seconds gauge"
    echo "# HELP wg_peer_rx_bytes_total Bytes received from the peer."
    echo "# TYPE wg_peer_rx_bytes_total counter"
    echo "# HELP wg_peer_tx_bytes_total Bytes sent to the peer."
    echo "# TYPE wg_peer_tx_bytes_total counter"

    # `wg show wg0 dump` line 1 is interface info; subsequent lines are one per
    # peer: pubkey, psk, endpoint, allowed-ips, latest-handshake, rx, tx, keepalive.
    tail -n +2 <(wg show wg0 dump) | while IFS=$'\t' read -r pubkey _psk _endpoint _allowed handshake rx tx _keepalive; do
      # Label by a short prefix of the public key, not the full key, so the
      # metric doesn't carry the complete WireGuard public key as a label value.
      peer="$${pubkey:0:8}"
      echo "wg_peer_latest_handshake_seconds{peer=\"$${peer}\"} $${handshake:-0}"
      echo "wg_peer_rx_bytes_total{peer=\"$${peer}\"} $${rx:-0}"
      echo "wg_peer_tx_bytes_total{peer=\"$${peer}\"} $${tx:-0}"
    done
  else
    echo "# HELP wg_interface_up Whether the wg0 WireGuard interface exists and is queryable (1) or not (0)."
    echo "# TYPE wg_interface_up gauge"
    echo 'wg_interface_up{interface="wg0"} 0'
  fi
} >"$TMP_FILE"

mv "$TMP_FILE" "$OUT_FILE"
