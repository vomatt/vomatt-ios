#!/usr/bin/env bash
# Pulls what the iOS app shares with vomatt-web into this repo.
#
#   scripts/sync.sh api [--url https://api.example.com]   OpenAPI contract from vomatt-api (prints a diff first)
#   scripts/sync.sh api --file path/to/openapi.json       the contract from a file (e.g. vomatt-api's docs/frontend/openapi.json)
#   scripts/sync.sh locales                               en/zh strings
#   scripts/sync.sh tokens                                color tokens -> asset catalog + Swift
#   scripts/sync.sh avatars                               the bot avatar SVGs
#   scripts/sync.sh all                                   everything above
#   scripts/sync.sh check                                 fails when anything differs from vomatt-web or vomatt-api
#
# WEB_DIR points at the vomatt-web checkout (default: ../vomatt-web), API_DIR at vomatt-api's (default:
# ../vomatt-api). Files are read from their commits WEB_REF and API_REF (default: origin/main, fetched
# first), not their working trees, so work in progress there never reaches the app. The contract comes
# from vomatt-api's own snapshot (docs/frontend/openapi.json): the web's api-docs.json copy can lag
# behind endpoints the web already calls.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="${WEB_DIR:-$ROOT/../vomatt-web}"
SPEC="$ROOT/Packages/VomattKit/Sources/VomattAPI/openapi.json"
LOCALES="$ROOT/App/Resources/Locales"
COLORS="$ROOT/App/Resources/Colors.xcassets"
TOKENS_SWIFT="$ROOT/App/DesignSystem/Tokens.generated.swift"
AVATARS="$ROOT/App/Resources/Avatars.xcassets"
WEB_REF="${WEB_REF:-origin/main}"
API_DIR="${API_DIR:-$ROOT/../vomatt-api}"
API_REF="${API_REF:-origin/main}"
API_SNAPSHOT=docs/frontend/openapi.json

require_web() {
	# Behind a stale local branch the app would copy strings the web already changed
	[[ "$WEB_REF" == origin/* ]] && git -C "$WEB_DIR" fetch -q origin
	git -C "$WEB_DIR" rev-parse --verify --quiet "$WEB_REF^{commit}" >/dev/null \
		|| { echo "sync.sh: no commit $WEB_REF in vomatt-web at $WEB_DIR (set WEB_DIR, WEB_REF)" >&2; exit 1; }
}

require_api() {
	[[ "$API_REF" == origin/* ]] && git -C "$API_DIR" fetch -q origin
	git -C "$API_DIR" rev-parse --verify --quiet "$API_REF^{commit}" >/dev/null \
		|| { echo "sync.sh: no commit $API_REF in vomatt-api at $API_DIR (set API_DIR, API_REF)" >&2; exit 1; }
}

# vomatt-api's contract snapshot as of API_REF.
api_contract() {
	git -C "$API_DIR" show "$API_REF:$API_SNAPSHOT"
}

# Prints a web file as of WEB_REF.
web_file() {
	git -C "$WEB_DIR" show "$WEB_REF:$1"
}

# The avatar names (without .svg) as of WEB_REF.
web_avatars() {
	git -C "$WEB_DIR" ls-tree --name-only "$WEB_REF" public/avatars/ | grep '\.svg$' | sed 's|.*/||; s/\.svg$//' | sort
}

sync_api() {
	local source="" tmp
	tmp="$(mktemp)"
	if [[ "${1:-}" == "--url" ]]; then
		source="${2:?--url needs the API origin}/v3/api-docs"
		curl -fsSL "$source" -o "$tmp"
	else
		if [[ "${1:-}" == "--file" ]]; then
			source="${2:?--file needs a path}"
		else
			require_api
			source="$API_DIR/$API_SNAPSHOT at $API_REF"
		fi
		if [[ "${1:-}" == "--file" ]]; then cp "$2" "$tmp"; else api_contract > "$tmp"; fi
	fi
	# Stable formatting keeps the git diff readable
	python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); json.dump(d, open(sys.argv[1],"w"), indent=2, ensure_ascii=False, sort_keys=True)' "$tmp"
	echo "Contract changes from $source:"
	if [[ -f "$SPEC" ]]; then python3 "$ROOT/scripts/api-diff.py" "$SPEC" "$tmp"; else echo "(first sync)"; fi
	mv "$tmp" "$SPEC"
	echo "Wrote $SPEC. Build the package (make test) to regenerate the client."
}

sync_locales() {
	require_web
	web_file src/locales/en.json > "$LOCALES/en.json"
	web_file src/locales/zh.json > "$LOCALES/zh.json"
	echo "Copied en.json and zh.json from $WEB_REF"
}

sync_tokens() {
	require_web
	local css
	css="$(mktemp)"
	web_file src/styles/global.css > "$css"
	python3 "$ROOT/scripts/tokens.py" "$css" "$COLORS" "$TOKENS_SWIFT"
	rm "$css"
}

sync_avatars() {
	require_web
	rm -rf "$AVATARS"
	mkdir -p "$AVATARS"
	echo '{"info":{"author":"xcode","version":1}}' > "$AVATARS/Contents.json"
	local count=0
	for kind in $(web_avatars); do
		local set="$AVATARS/bot-$kind.imageset"
		mkdir -p "$set"
		web_file "public/avatars/$kind.svg" > "$set/$kind.svg"
		python3 "$ROOT/scripts/svg_oklch.py" "$set/$kind.svg"
		cat > "$set/Contents.json" <<-JSON
		{
		  "images" : [ { "filename" : "$kind.svg", "idiom" : "universal" } ],
		  "info" : { "author" : "xcode", "version" : 1 },
		  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "original" }
		}
		JSON
		count=$((count + 1))
	done
	echo "Copied $count avatars"
}

check() {
	require_web
	local status=0
	cmp -s <(web_file src/locales/en.json) "$LOCALES/en.json" || { echo "locales/en.json differs from the web"; status=1; }
	cmp -s <(web_file src/locales/zh.json) "$LOCALES/zh.json" || { echo "locales/zh.json differs from the web"; status=1; }
	require_api
	local diff
	diff="$(python3 "$ROOT/scripts/api-diff.py" "$SPEC" <(api_contract))"
	[[ "$diff" == "No contract changes." ]] || { echo "API contract differs from vomatt-api:"; echo "$diff"; status=1; }
	local ios_avatars
	ios_avatars="$(ls "$AVATARS" | grep imageset | sed 's/^bot-//; s/\.imageset$//' | sort)"
	[[ "$(web_avatars)" == "$ios_avatars" ]] || { echo "avatars differ from the web"; status=1; }
	[[ $status -eq 0 ]] && echo "In sync with vomatt-web $WEB_REF ($(git -C "$WEB_DIR" rev-parse --short "$WEB_REF")) and vomatt-api $API_REF ($(git -C "$API_DIR" rev-parse --short "$API_REF"))"
	return $status
}

case "${1:-}" in
	api) shift; sync_api "$@" ;;
	locales) sync_locales ;;
	tokens) sync_tokens ;;
	avatars) sync_avatars ;;
	all) sync_api; sync_locales; sync_tokens; sync_avatars ;;
	check) check ;;
	*) sed -n '2,16p' "$0"; exit 1 ;;
esac
