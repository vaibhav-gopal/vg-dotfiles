#!/usr/bin/env bash
# SUPER + N : warm the screen for the evening (hyprsunset).
# `status` prints JSON for the waybar module ; `toggle` pokes waybar (signal 9) to refresh it.

TEMPERATURE=4000

running() { pgrep -x hyprsunset >/dev/null; }

case "${1:-toggle}" in
    toggle)
        if running; then
            pkill -x hyprsunset
        else
            setsid -f hyprsunset --temperature "$TEMPERATURE" >/dev/null 2>&1
        fi
        sleep 0.2
        pkill -RTMIN+9 waybar
        ;;
    status)
        if running; then
            printf '{"text": "%s", "class": "on", "tooltip": "night light on (%sK)"}\n' $'' "$TEMPERATURE"
        else
            printf '{"text": "%s", "class": "off", "tooltip": "night light off"}\n' $''
        fi
        ;;
esac
