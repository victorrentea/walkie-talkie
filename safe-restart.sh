#!/usr/bin/env bash
# Alias of ./relay-restart.sh — the one restart path. See its header for the flags.
exec "$(cd "$(dirname "$0")" && pwd)/relay-restart.sh" "$@"
