#!/bin/bash
D=amdgpu_bl2
BL=/sys/class/backlight/$D
DRM=/sys/class/drm/card2-eDP-2
ORIG=$(cat $BL/brightness)
trap 'hyprctl dispatch "hl.dsp.dpms({ action = \"enable\" })" >/dev/null 2>&1; brightnessctl -d '"$D"' -q set '"$ORIG"' 2>/dev/null' EXIT

sample(){ echo "  $1  brightness=$(cat $BL/brightness) actual=$(cat $BL/actual_brightness) bl_power=$(cat $BL/bl_power) drm_dpms=$(cat $DRM/dpms) drm_enabled=$(cat $DRM/enabled)"; }

# Deliberately NOT the previous value: if actual falls back to the stored
# perceptual value, it must read 240000 here, not 160000.
brightnessctl -d $D -q set 240000
sleep 1
echo "=== lit, brightness deliberately set to 240000 ==="
sample "before"

hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null
sleep 2
echo "=== blanked ==="
for i in 1 2 3; do sample "during"; sleep 2; done

hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null
sleep 3
echo "=== woken ==="
sample "after "

brightnessctl -d $D -q set $ORIG
sleep 1
echo "=== restored ==="
sample "final "
