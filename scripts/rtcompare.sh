#!/bin/bash
# Capture the same view with the layer off, on (defaults) and on (high), plus debug buffers.
# Usage: rtcompare.sh <name> "<console commands to set the view>"
NAME="$1"; VIEW="$2"; OUT="$HOME/Half-Life-2-arm64/compare"
S="$HOME/Half-Life-2-arm64/scripts"
OFF="rt_enable 0"
DEF="rt_enable 1;rt_ao_strength 0.8;rt_ao_radius 64;rt_ao_rays 2;rt_divisor 0;rt_budget 8;rt_reflection_strength 0.7;rt_shadows 1;rt_dynamic 2;rt_reflections 1"
HIGH="rt_enable 1;rt_ao_strength 1;rt_ao_radius 128;rt_ao_rays 4;rt_divisor 2;rt_budget 0;rt_reflection_strength 1;rt_shadows 2;rt_shadow_strength 0.5;rt_dynamic 2;rt_reflections 1"
RTSHOT_SETTLE=2 "$S/rtcmd.sh" /tmp/x.png "$VIEW;ai_disable;cl_showfps 0;$OFF" >/dev/null
sleep 5; screencapture -x -D 2 "$OUT/${NAME}_off.png"
RTSHOT_SETTLE=1 "$S/rtcmd.sh" /tmp/x.png "$DEF" >/dev/null; sleep 5; screencapture -x -D 2 "$OUT/${NAME}_on.png"
RTSHOT_SETTLE=1 "$S/rtcmd.sh" /tmp/x.png "$HIGH" >/dev/null; sleep 5; screencapture -x -D 2 "$OUT/${NAME}_high.png"
RTSHOT_SETTLE=1 "$S/rtcmd.sh" /tmp/x.png "rt_debug 1" >/dev/null; sleep 3; screencapture -x -D 2 "$OUT/${NAME}_ao.png"
RTSHOT_SETTLE=1 "$S/rtcmd.sh" /tmp/x.png "rt_debug 0;$DEF" >/dev/null
echo "$NAME done"
