#!/bin/sh
# Checks every property of Formal/SessionRefresh/SessionRefresh.tla, one TLC run each, and
# prints a verdict table. Full TLC output (with the counterexample trace) goes to Formal/out/.
#   Formal/check-session.sh                 # the model of Session.swift
#   VARIANT=no-join Formal/check-session.sh # a deliberately broken copy (see SKILL.md)
#   Formal/check-session.sh SignOutSticks   # one property only
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
VARIANT=${VARIANT:-code}
SPEC_DIR="$HERE/SessionRefresh"
OUT="$HERE/out/$VARIANT"
mkdir -p "$OUT"

INVARIANTS="TypeOK NeverSendsAUsedRefreshToken StoreMatchesSession SignOutSticks"
PROPERTIES="EveryCallerReturns"
if [ $# -gt 0 ]; then
  INVARIANTS=""; PROPERTIES=""
  for p in "$@"; do
    case $p in EveryCallerReturns) PROPERTIES="$PROPERTIES $p";; *) INVARIANTS="$INVARIANTS $p";; esac
  done
fi

echo "Covered code, last changed in:"
git -C "$ROOT" log -1 --format='  %h %ad %s' --date=short -- \
  Packages/VomattKit/Sources/VomattCore/Networking/Session.swift \
  Packages/VomattKit/Sources/VomattCore/Networking/Middleware.swift \
  Packages/VomattKit/Sources/VomattCore/VomattService.swift
echo "Variant: $VARIANT"
echo

status=0
run() { # run <kind> <name>
  kind=$1; name=$2
  work=$(mktemp -d)
  cp "$SPEC_DIR/SessionRefresh.tla" "$work/"
  # Callers are interchangeable, so invariants are checked up to permutation. Liveness is not:
  # TLC's symmetry reduction is unsound for temporal properties.
  if [ "$kind" = INVARIANT ]; then base=SessionRefresh.cfg; sym="SYMMETRY Perms"; else base=SessionRefresh.liveness.cfg; sym=""; fi
  { cat "$SPEC_DIR/$base"; echo "  Variant = \"$VARIANT\""; echo "$sym"; echo "$kind $name"; } > "$work/SessionRefresh.cfg"
  log="$OUT/$name.log"
  # -deadlock: the bounded model stops when the backend has minted MaxPairs pairs; that is not a bug.
  (cd "$work" && "$HERE/tlc.sh" SessionRefresh.tla SessionRefresh.cfg -deadlock) > "$log" 2>&1
  states=$(sed -n 's/^\([0-9]*\) states generated, \([0-9]*\) distinct states found.*/\2 states/p' "$log" | tail -1)
  if grep -q "No error has been found" "$log"; then
    printf '  PASS  %-30s %s\n' "$name" "$states"
  elif grep -q -e "is violated" -e "Temporal properties were violated" "$log"; then
    printf '  FAIL  %-30s counterexample in %s\n' "$name" "Formal/out/$VARIANT/$name.log"
    # the steps, in the model's action names; the log has every state in full
    sed -n 's/^State \([0-9]*\): <\([A-Za-z0-9]*\).*/\1 \2/p; s/^State \([0-9]*\): <Initial.*/\1 Init/p' "$log" \
      | awk '{ printf "%s%s", (NR > 1 ? " > " : "        "), $2 } END { print "" }'
    status=1
  else
    printf '  ERROR %-30s see %s\n' "$name" "Formal/out/$VARIANT/$name.log"
    tail -20 "$log"
    status=2
  fi
  rm -rf "$work"
}
for name in $INVARIANTS; do run INVARIANT "$name"; done
for name in $PROPERTIES; do run PROPERTY "$name"; done
exit $status
