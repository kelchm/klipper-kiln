#!/usr/bin/env bash
# Logs power/throttling/thermal state to journald every 5s.
# get_throttled bits: 0=undervolt now, 1=cap now, 2=throttled now, 3=soft_throttled,
#                    16=undervolt occurred, 17=cap occurred, 18=throttle occurred, 19=soft_throttle.
LAST=""
while true; do
    NOW=$(vcgencmd get_throttled | sed s/throttled=//)
    TEMP=$(vcgencmd measure_temp | sed s/temp=//)
    VOLT=$(vcgencmd measure_volts core | sed s/volt=//)
    LOAD=$(awk '{print $1}' /proc/loadavg)
    MEM=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    LINE="throttle=$NOW temp=$TEMP core=$VOLT load=$LOAD memfree=${MEM}kB"
    if [[ "$LINE" != "$LAST" ]]; then
        logger -t duncan-watchdog -p user.info "$LINE"
        LAST="$LINE"
    fi
    sleep 5
done
