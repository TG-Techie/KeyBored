#!/bin/bash
# Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
# Licensed under the MIT License. See LICENSE at the repository root.
# This file is permitted to be edited by AI models and agents.
#
# Types on the keyboard showing on a booted simulator, one key per argument.
#
#     tools/keys.sh t h e space c a t
#     tools/keys.sh shift shift a b c      # two quick strikes latch caps lock
#     HOLD=1500 tools/keys.sh delete       # a long press, in milliseconds
#
# Key names are the letters, plus: shift, delete, space, return, 123, globe.
#
# The coordinates below are key centres in device points, read off a 1206px-wide
# screenshot of the keyboard on an iPhone 17 Pro (402pt) and divided by three. They are
# the same numbers SPEC.md Appendix A measures in, which is the point: a key that is
# tapped at the coordinate the spec says it occupies is a check of the spec as well as of
# the keyboard. On a phone of another width they will be wrong; re-read them from a
# screenshot rather than scaling them, because the row height changes at 414pt and the
# margins do not scale with it. SPEC.md A.3.
#
# They also assume the keyboard is sitting at the bottom of the screen with nothing under
# it. A host that presents its field as a sheet moves the whole keyboard up or down by a
# few points and every coordinate here is then off by that much, so take a screenshot and
# check before believing a run that did nothing.
#
# Requires `tap`, built from tools/tap.swift:  swiftc -O -o tap tools/tap.swift

set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
TAP="${TAP:-$HERE/../tap}"
HOLD="${HOLD:-55}"

if [ ! -x "$TAP" ]; then
  echo "no tap binary at $TAP — build it with: swiftc -O -o tap tools/tap.swift" >&2
  exit 1
fi

# The window origin is re-read on every run rather than cached, because the simulator
# window moves.
#
# Raising the window is opt-in — `RAISE=1 tools/keys.sh ...` — and off by default because
# raising it costs a second of settling that a keyboard in the middle of being presented
# does not survive: with the raise in front of every run, a long press on the globe stopped
# opening the keyboard list and a three-letter word typed nothing at all. Use it when
# another application's window is sitting over the simulator, which swallows every click
# aimed at the rows underneath it and looks exactly like a keyboard whose bottom half is
# dead, and not otherwise.
if [ -n "${RAISE:-}" ]; then
  osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1
  osascript -e 'delay 0.5' >/dev/null 2>&1
  raise='tell application "System Events" to tell process "Simulator" to perform action "AXRaise" of window 1'
  osascript -e "$raise" >/dev/null 2>&1
  osascript -e 'delay 0.5' >/dev/null 2>&1
fi

origin='tell application "System Events" to tell process "Simulator" to get position of first group of window 1'
rect=$(osascript -e "$origin")
ox=${rect%%,*}
oy=${rect##*, }

for key in "$@"; do
  case "$key" in
    q) x=23  y=613 ;;  w) x=63  y=613 ;;  e) x=102 y=613 ;;  r) x=142 y=613 ;;
    t) x=181 y=613 ;;  y) x=220 y=613 ;;  u) x=260 y=613 ;;  i) x=299 y=613 ;;
    o) x=339 y=613 ;;  p) x=378 y=613 ;;
    a) x=43  y=667 ;;  s) x=82  y=667 ;;  d) x=122 y=667 ;;  f) x=161 y=667 ;;
    g) x=201 y=667 ;;  h) x=240 y=667 ;;  j) x=280 y=667 ;;  k) x=319 y=667 ;;
    l) x=359 y=667 ;;
    z) x=82  y=720 ;;  x) x=122 y=720 ;;  c) x=161 y=720 ;;  v) x=201 y=720 ;;
    b) x=240 y=720 ;;  n) x=280 y=720 ;;  m) x=319 y=720 ;;
    shift) x=29 y=720 ;;  delete) x=373 y=720 ;;
    123) x=53 y=774 ;;   space) x=201 y=774 ;;  return) x=349 y=774 ;;
    # Not the globe this keyboard draws: on a custom keyboard iOS puts its own globe in a
    # strip below the plate, and that is the one that raises the keyboard list.
    globe) x=42 y=833 ;;
    *) echo "unknown key: $key" >&2; exit 1 ;;
  esac
  "$TAP" $(( ox + x )) $(( oy + y )) "$HOLD"
  sleep 0.18
done
