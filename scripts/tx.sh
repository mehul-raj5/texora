#!/bin/zsh
# Sends a developer automation command to a Texora launched with --automation.
# Usage: scripts/tx.sh <cmd> [arg] [arg2] [key=value ...]
cmd="$1"; arg="${2:-}"; arg2="${3:-}"
shift $(( $# < 3 ? $# : 3 ))
extra=""
for kv in "$@"; do k="${kv%%=*}"; v="${kv#*=}"; extra+=", ${k}: $(printf '%s' "$v" | /usr/bin/python3 -I -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"; done
J_ARG=$(printf '%s' "$arg" | /usr/bin/python3 -I -c 'import json,sys;print(json.dumps(sys.stdin.read()))')
J_ARG2=$(printf '%s' "$arg2" | /usr/bin/python3 -I -c 'import json,sys;print(json.dumps(sys.stdin.read()))')
osascript -l JavaScript -e "ObjC.import('Foundation');
var info = \$({cmd: '$cmd', arg: $J_ARG, arg2: $J_ARG2 $extra});
\$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('app.texora.debug', \$(), info, true);" >/dev/null
