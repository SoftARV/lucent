#!/bin/bash
# Stage 3 of docs/screen-follow-portability.md: the four save-and-restore
# guards, re-run against whichever backend is live.
#
# They were built and tested when Mutter was the only source of edges. Nothing
# in daemon-service.vala is backend-specific, but the delivery is: the wlr
# backend publishes from a Wayland fd rather than a D-Bus signal, so the
# guards are re-measured rather than assumed to carry over.
#
# Drives the panel through Hyprland and always puts it back.

set -u

B=dev.miguel.Lucent.Daemon
P=/dev/miguel/Lucent/Daemon

get(){ busctl --user get-property $B $P $B "$1" 2>/dev/null | awk '{print $2}'; }
call(){ busctl --user call $B $P $B "$@" >/dev/null 2>&1; }
refresh(){ call RefreshLighting; }

blank(){ hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null; sleep 3; }
wake(){  hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'  >/dev/null; sleep 3; }

PASS=0
FAIL=0
check(){ # check <what> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "    PASS  $1: $3"
        PASS=$((PASS + 1))
    else
        echo "    FAIL  $1: expected $2, got $3"
        FAIL=$((FAIL + 1))
    fi
}

ORIG_BRIGHT=$(get Brightness)
ORIG_LOGO=$(get LogoActive)

restore(){
    hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1
    sleep 1
    call ApplyFollowScreen b true
    call ApplyBrightness u "$ORIG_BRIGHT"
    call ApplyLogo b "$ORIG_LOGO"
}
trap restore EXIT

echo "baseline: brightness=$ORIG_BRIGHT logo=$ORIG_LOGO follow=$(get FollowScreen)"
echo

# The logo has to be lit for two of these to mean anything: it is only ever
# taken down when it was up.
call ApplyBrightness u 75
call ApplyLogo b true
sleep 1

echo "1. an explicit ApplyBrightness during a blank cancels that restore"
blank
check "dark" 0 "$(get Brightness)"
call ApplyBrightness u 40
wake
refresh
check "wake keeps the deliberate 40, not the saved 75" 40 "$(get Brightness)"
echo

echo "2. brightness and logo are on separate flags"
call ApplyBrightness u 75
call ApplyLogo b true
sleep 1
blank
check "logo down with the keyboard" false "$(get LogoActive)"
call ApplyBrightness u 40
wake
refresh
check "brightness keeps the deliberate 40" 40 "$(get Brightness)"
check "logo still restored, not stranded off" true "$(get LogoActive)"
echo

echo "3. a second blank does not overwrite the saved values with our own dark ones"
call ApplyBrightness u 75
call ApplyLogo b true
sleep 1
blank
check "dark" 0 "$(get Brightness)"
# The backend swallows a repeated OFF edge, so re-enter the blanked branch the
# only other way a client can: ask to follow the screen while already dark.
call ApplyFollowScreen b true
sleep 1
check "still dark after a second sync" 0 "$(get Brightness)"
wake
refresh
check "restores 75, not the 0 we wrote ourselves" 75 "$(get Brightness)"
echo

echo "4. turning the toggle off while dark hands both straight back"
call ApplyBrightness u 75
call ApplyLogo b true
sleep 1
blank
check "dark" 0 "$(get Brightness)"
check "logo down" false "$(get LogoActive)"
call ApplyFollowScreen b false
sleep 1
refresh
check "brightness handed back while still dark" 75 "$(get Brightness)"
check "logo handed back while still dark" true "$(get LogoActive)"
call ApplyFollowScreen b true
wake
echo

echo "----"
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
