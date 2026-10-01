#!/bin/sh
# verify.sh <manifest path> [name]: check a built fixture against the key literals in
# tests/fixture/expected.md.
#
# Usage: m=$(sh tests/fixture/build.sh solo) && sh tests/fixture/verify.sh "$m" solo
#
# name is solo, solo-dirty, or full. Without it, the name comes from the fixture
# directory: manifest-groups.json means full; otherwise an app checkout on
# scratch-branch means solo-dirty; otherwise solo.
#
# Expected values are literals copied from expected.md; change them only together with
# expected.md and build.sh, with the reason in the commit body.
# Exit 0 when every check passes; otherwise print one line per mismatch and exit 1.
set -u

m=${1:-}
if [ -z "$m" ] || [ ! -f "$m" ]; then
	echo "verify: no manifest at '$m'"
	exit 2
fi
F=$(cd "$(dirname "$m")" && pwd)
A=$F/app

name=${2:-}
if [ -z "$name" ]; then
	if [ -f "$F/manifest-groups.json" ]; then
		name=full
	elif [ "$(git -C "$A" rev-parse --abbrev-ref HEAD 2>/dev/null)" = scratch-branch ]; then
		name=solo-dirty
	else
		name=solo
	fi
fi
case $name in
solo | solo-dirty | full) ;;
*)
	echo "verify: unknown fixture '$name'"
	exit 2
	;;
esac

fails=0
fail() {
	echo "verify $name: $*"
	fails=$((fails + 1))
}

# same <label> <expected> <actual>
same() {
	[ "$2" = "$3" ] || fail "$1: expected '$2', got '$3'"
}

rev() {
	git -C "$1" rev-parse "$2" 2>/dev/null
}

if [ "$name" = full ]; then
	mb=6b27db42e063b1881b90f0b4c277d0a8ce2f3ab3
	later=5a6d60c0a485e6a069f04e0f73f8dfedcb498ff2
	head=191e0ad183ea7509077bff3fd3b462d57d4b70e1
else
	mb=bd5d5e1e67a1fc55adeaa1452920245b1d368f7f
	later=2b5e8f3511e25bc0225ffc4ef6957dcca51d9fcd
	if [ "$name" = solo ]; then
		head=0c23936980b254c4abd489d3ecfd296f5e7bc0db
	else
		head=6d2c9a58b52f0cd66760feefd29b1d1915d92045
	fi
fi

# Every fixture: merge-base, the base's later commit, the feature head.
same "app merge-base" "$mb" "$(git -C "$A" merge-base main feature 2>/dev/null)"
same "app commits on main since the merge-base" "$later add count command" \
	"$(git -C "$A" log --format='%H %s' "$mb..main" 2>/dev/null)"
same "app feature head" "$head" "$(rev "$A" feature)"
same "app files changed on main since the merge-base" "README.md src/users.sh" \
	"$(git -C "$A" diff --name-only "$mb" main 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"

# The base's later change shows as a removal only in the two-dot diff.
n3=$(git -C "$A" diff main...feature 2>/dev/null | grep -c '^-.*count_users')
n2=$(git -C "$A" diff main..feature 2>/dev/null | grep -c '^-.*count_users')
same "count_users removals in the three-dot diff" 0 "$n3"
same "count_users removals in the two-dot diff" 3 "$n2"

# Skipped test.
same "skipped test line" 'skip test_deactivate_keeps_row "flaky on CI, fix after release"' \
	"$(git -C "$A" show feature:tests/test_users.sh 2>/dev/null | grep '^skip ')"

case $name in
solo)
	same "app checkout branch" feature "$(git -C "$A" rev-parse --abbrev-ref HEAD 2>/dev/null)"
	;;
solo-dirty)
	same "app checkout branch" scratch-branch "$(git -C "$A" rev-parse --abbrev-ref HEAD 2>/dev/null)"
	same "symlink entry mode" 120000 \
		"$(git -C "$A" ls-tree feature links/outside 2>/dev/null | cut -d' ' -f1)"
	same "symlink target" /etc/hosts "$(git -C "$A" cat-file -p feature:links/outside 2>/dev/null)"
	same "app status" " M README.md|?? notes/" \
		"$(git -C "$A" status --porcelain 2>/dev/null | tr '\n' '|' | sed 's/|$//')"
	[ -f "$A/.test-output/results.txt" ] || fail "ignored file .test-output/results.txt is missing"
	[ ! -e "$F/filter-ran" ] || fail "filter-ran exists: $F/filter-ran"
	;;
full)
	same "MUST rule" 'main:style/shell-scripts.md:5:Every shell script MUST run `set -eu` before its first command.' \
		"$(git -C "$F/guidelines" grep -n MUST main 2>/dev/null)"
	same "legacy HEAD" 2f21951b0c72eba8ccf5b3db9b4481ade113f8bd "$(rev "$F/legacy" HEAD)"
	same "legacy main" b3b208f6b760091e46d601739e93d43ee9f0bce7 "$(rev "$F/legacy" main)"
	same "config/settings.ini bytes on feature" \
		5b6170705d0d0a6e616d653d75736572730d0a706167655f73697a653d3530300d0a6578706f72745f6b6579733d73686f72740d0a \
		"$(git -C "$A" show feature:config/settings.ini 2>/dev/null | od -An -tx1 | tr -d ' \n')"
	same "tickets touching src/output.sh" \
		"APP-5: audit log for commands|APP-4: short export keys as an option|APP-3: paginate the user list" \
		"$(git -C "$A" log --format=%s main..feature -- src/output.sh 2>/dev/null | tr '\n' '|' | sed 's/|$//')"
	;;
esac

# Handoff files (solo and solo-dirty): the five files exist, the handoff's hash and each
# verdicts file's heading hash are the literals in expected.md, and the claim count per
# kind from handoff.sh equals the literals there.
case $name in
solo | solo-dirty)
	hs=$(cd "$(dirname "$0")/../.." && pwd)/skills/cca/scripts/handoff.sh
	for f in handoff.md manifest-handoff.json manifest-scratch.json claims-verdicts.md \
		claims-verdicts-stale.md; do
		[ -f "$F/$f" ] || fail "$f is missing"
	done
	same "handoff.md hash" 36b30bd89b131ec1eed669ab0a0c58bbc9c5aaa8 \
		"$(git hash-object --no-filters "$F/handoff.md" 2>/dev/null)"
	same "claims-verdicts.md heading hash" 36b30bd89b131ec1eed669ab0a0c58bbc9c5aaa8 \
		"$(sed -n 's/^## .* (handoff), hash //p' "$F/claims-verdicts.md" 2>/dev/null)"
	same "claims-verdicts-stale.md heading hash" 0000000000000000000000000000000000000000 \
		"$(sed -n 's/^## .* (handoff), hash //p' "$F/claims-verdicts-stale.md" 2>/dev/null)"
	same "claims-verdicts.md entries" 5 "$(grep -c '^- claim ' "$F/claims-verdicts.md" 2>/dev/null)"
	grep -q '"claims": \["./handoff.md"\]' "$F/manifest-handoff.json" 2>/dev/null ||
		fail "manifest-handoff.json does not list ./handoff.md as claims"
	grep -q '"scratch": "./app/.test-output"' "$F/manifest-scratch.json" 2>/dev/null ||
		fail "manifest-scratch.json has no scratch key ./app/.test-output"
	if claims=$(sh "$hs" claims "$F/handoff.md" 2>&1); then
		same "handoff claim counts" "code=4 verification=2 decision=2 scope=1 status=2" \
			"$(printf '%s\n' "$claims" | awk -F'\t' '{ n[$1]++ } END { printf "code=%d verification=%d decision=%d scope=%d status=%d", n["code"], n["verification"], n["decision"], n["scope"], n["status"] }')"
		same "handoff claim total" 11 "$(printf '%s\n' "$claims" | wc -l | tr -d ' ')"
	else
		fail "handoff.sh claims failed: $claims"
	fi
	;;
esac

if [ "$fails" -gt 0 ]; then
	exit 1
fi
echo "verify $name: ok"
