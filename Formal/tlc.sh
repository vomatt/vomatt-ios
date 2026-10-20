#!/bin/sh
# Runs TLC (the TLA+ model checker) on a spec: Formal/tlc.sh <Spec.tla> <Spec.cfg> [tlc args]
# Java comes from Homebrew's openjdk (`brew install openjdk`); no system Java is needed.
# The TLA+ tools jar is pinned and fetched once into Formal/.tools (gitignored).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=1.7.4
JAR="$HERE/.tools/tla2tools-$VERSION.jar"
URL="https://github.com/tlaplus/tlaplus/releases/download/v$VERSION/tla2tools.jar"
SHA256=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88

JAVA=${JAVA:-}
if [ -z "$JAVA" ]; then
  for candidate in "$(brew --prefix openjdk 2>/dev/null)/bin/java" "$(command -v java || true)"; do
    if [ -n "$candidate" ] && "$candidate" -version >/dev/null 2>&1; then JAVA=$candidate; break; fi
  done
fi
[ -n "$JAVA" ] || { echo "tlc.sh: no Java runtime. Run: brew install openjdk" >&2; exit 2; }

if [ ! -f "$JAR" ]; then
  mkdir -p "$HERE/.tools"
  echo "tlc.sh: fetching tla2tools.jar v$VERSION" >&2
  curl -fsSL "$URL" -o "$JAR.tmp"
  echo "$SHA256  $JAR.tmp" | shasum -a 256 -c - >/dev/null || { rm -f "$JAR.tmp"; echo "tlc.sh: checksum mismatch" >&2; exit 2; }
  mv "$JAR.tmp" "$JAR"
fi

spec=$1; cfg=$2; shift 2
exec "$JAVA" -XX:+UseParallelGC -jar "$JAR" -workers auto -cleanup -config "$cfg" "$spec" "$@"
