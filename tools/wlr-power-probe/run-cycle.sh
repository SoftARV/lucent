#!/bin/bash
# Drives one real DPMS cycle while probe watches. Always restores the panel.
cd "$(dirname "$0")"
trap 'hyprctl dispatch "hl.dsp.dpms({ action = \"enable\" })" >/dev/null 2>&1' EXIT

./probe 26 > probe.log 2>&1 &
PROBE=$!
sleep 6

echo "--- dispatching dpms disable"
hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' 2>&1 | head -2
sleep 7
echo "--- dpmsStatus while off: $(hyprctl monitors -j | grep -c '"dpmsStatus": true') on"
echo "--- dispatching dpms enable"
hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' 2>&1 | head -2
sleep 7
echo "--- dpmsStatus after: $(hyprctl monitors -j | grep -c '"dpmsStatus": true') on"

wait $PROBE
echo "=== probe log ==="
cat probe.log
