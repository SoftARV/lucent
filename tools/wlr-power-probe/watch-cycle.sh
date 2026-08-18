#!/bin/bash
# Longer, announced cycle with independent backlight evidence.
cd "$(dirname "$0")"
trap 'hyprctl dispatch "hl.dsp.dpms({ action = \"enable\" })" >/dev/null 2>&1' EXIT

BL=/sys/class/backlight/amdgpu_bl2
sample(){ echo "  $(date +%H:%M:%S)  actual_brightness=$(cat $BL/actual_brightness) bl_power=$(cat $BL/bl_power) dpms_on=$(hyprctl monitors -j | grep -c '"dpmsStatus": true')"; }

./probe 45 > probe.log 2>&1 &
PROBE=$!

echo "=== lead-in: 20 s, panel should stay lit ==="
for i in 1 2 3 4; do sample; sleep 5; done

echo "=== BLANKING NOW for 10 s ==="
hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null
for i in 1 2 3 4 5; do sleep 2; sample; done

echo "=== WAKING ==="
hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null
for i in 1 2 3; do sleep 2; sample; done

wait $PROBE
echo "=== probe log ==="
cat probe.log
