#!/usr/bin/env bash
# SUPER + SHIFT + N : do-not-disturb (a mako mode that hides notifications ; see mako.d/config).
# `status` prints JSON for the waybar module ; `toggle` pokes waybar (signal 8) to refresh it.

dnd_on() { makoctl mode | grep -qx do-not-disturb; }

case "${1:-toggle}" in
    toggle)
        if dnd_on; then
            makoctl mode -r do-not-disturb >/dev/null
        else
            makoctl mode -a do-not-disturb >/dev/null
        fi
        pkill -RTMIN+8 waybar
        ;;
    status)
        if dnd_on; then
            printf '{"text": "%s", "class": "on", "tooltip": "do not disturb"}\n' $''
        else
            printf '{"text": "%s", "class": "off", "tooltip": "notifications on"}\n' $''
        fi
        ;;
esac
