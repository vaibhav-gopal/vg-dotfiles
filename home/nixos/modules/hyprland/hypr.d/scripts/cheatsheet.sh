#!/usr/bin/env bash
# SUPER + / : every `bindd` (bind with a description) in the live config, fuzzy-searchable.
# Generated from `hyprctl binds`, so it can never drift from binds.conf.

hyprctl binds -j | jq -r '
  def mod($bit): ((.modmask / $bit) | floor) % 2 == 1;
  def pretty: {"grave": "`", "slash": "/", "Return": "Enter", "mouse_down": "Scroll down", "mouse_up": "Scroll up"}[.] // .;
  .[]
  | select(.has_description)
  | [ (if mod(64) then "SUPER" else empty end),
      (if mod(4)  then "CTRL"  else empty end),
      (if mod(8)  then "ALT"   else empty end),
      (if mod(1)  then "SHIFT" else empty end),
      (.key | pretty) ] as $combo
  | "\($combo | join(" + "))\t\(.description)"
' | column -t -s $'\t' | fuzzel --dmenu --prompt 'keys ❯ ' --width 64 --lines 20 >/dev/null
