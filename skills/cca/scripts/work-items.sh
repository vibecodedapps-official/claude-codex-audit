#!/bin/sh
# work-items.sh: validate a work-items.jsonl file.
#
# Usage:
#   sh work-items.sh check <file> <report body> <claims.md>
#
# The format is defined in skills/cca/work-items.md. With jq, this checks that every
# line is one JSON object; that the common keys and the fields of its op are present
# with the right types; that ids run W1 upward with no gap; that every $new:<key>
# placeholder names a create on an earlier line and create keys are unique; that
# set_pr_description targets a PR forge id, not a placeholder; that run equals the run
# id in the report body's first heading ("# cca audit report: <run-id>"); that every
# C<n> in items is an item heading "#### C<n>: " in the report body; and that every
# "claim <n>" is a claim line in claims.md.
#
# Prints "work-items: ok" and exits 0, or one line per error, "work-items
# <file>:<line>: <message>", and exits 1. Exits 2 on a usage error or an unreadable
# file, and with "work-items: jq not found" when jq is missing.
set -u

usage() {
	echo "usage: work-items.sh check <file> <report body> <claims.md>" >&2
	exit 2
}

[ $# -eq 4 ] && [ "$1" = check ] || usage
file=$2
body=$3
claims=$4

if ! command -v jq >/dev/null 2>&1; then
	echo "work-items: jq not found"
	exit 2
fi

for f in "$file" "$body" "$claims"; do
	if [ ! -f "$f" ] || [ ! -r "$f" ]; then
		echo "work-items: cannot read $f" >&2
		exit 2
	fi
done

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# The run id: the first "# " heading of the report body must be
# "# cca audit report: <run-id>".
head1=$(grep -n -m 1 '^# ' "$body" | tr -d '\r')
run=
case ${head1#*:} in
"# cca audit report: "*) run=${head1#*:# cca audit report: } ;;
esac
run=$(printf '%s' "$run" | sed 's/[ ]*$//')
if [ -z "$run" ]; then
	hl=${head1%%:*}
	[ -n "$hl" ] || hl=1
	echo "work-items $body:$hl: no '# cca audit report: <run-id>' heading"
	exit 1
fi

# Item headings of the report body, and claim numbers of claims.md, as JSON sets.
cids=$(jq -R -n '[inputs | sub("\r$"; "") | capture("^#### (?<c>C[0-9]+): ") | {(.c): true}] | add // {}' < "$body") || exit 2
cnums=$(jq -R -n '[inputs | sub("\r$"; "") | capture("^(?<n>[0-9]+)\\. \\[claim:") | {(.n | tonumber | tostring): true}] | add // {}' < "$claims") || exit 2

cat > "$tmp/check.jq" <<'EOF'
def fstr($o; $k):
	if ($o | has($k) | not) then ["missing field '\($k)'"]
	elif ($o[$k] | type) != "string" then ["field '\($k)' must be a string"]
	elif ($o[$k] | length) == 0 then ["field '\($k)' is empty"]
	else [] end;

# A placeholder must name a create on an earlier line.
def newref($v; $creates; $what):
	if ($v | type) == "string" and ($v | startswith("$new:")) and (($creates | has($v[5:])) | not)
	then ["'\($v)' in \($what) has no create on an earlier line"]
	else [] end;

def item_errs($o; $cids; $cnums):
	if ($o | has("items") | not) then ["missing field 'items'"]
	elif ($o.items | type) != "array" then ["field 'items' must be an array"]
	elif ($o.items | length) == 0 then ["field 'items' is empty"]
	else
		[ $o.items[]
			| . as $it
			| if ($it | type) != "string" then "item is not a string"
			elif ($it | test("^C[0-9]+$")) then
				(if ($cids | has($it)) then empty else "unknown report item '\($it)'" end)
			elif ($it | test("^claim [0-9]+$")) then
				(if ($cnums | has($it | ltrimstr("claim ") | tonumber | tostring)) then empty else "unknown claim '\($it)'" end)
			else "item '\($it)' is not C<n> or claim <n>" end ]
	end;

def link_errs($o; $creates):
	if ($o.links | type) != "array" then ["field 'links' must be an array"]
	else
		[ $o.links | to_entries[]
			| .key as $i
			| .value as $l
			| if ($l | type) != "object" or (($l.type | type) != "string") or (($l.to | type) != "string")
				then "links[\($i)] must be an object with string fields 'type' and 'to'"
				else newref($l.to; $creates; "links[\($i)]")[] end ]
	end;

def op_errs($o; $s):
	$o.op as $op
	| if $op == "create" then
		fstr($o; "key") + fstr($o; "type") + fstr($o; "title") + fstr($o; "description")
		+ (if ($o.key | type) == "string" and ($o.key | length) > 0 then
			(if ($s.creates | has($o.key)) then ["duplicate create key '\($o.key)'"] else [] end)
			+ (if ($o.target | type) == "string" and $o.target != ("$new:" + $o.key)
				then ["target '\($o.target)' must be '$new:\($o.key)'"] else [] end)
		else [] end)
		+ (if ($o | has("fields")) and ($o.fields | type) != "object" then ["field 'fields' must be an object"] else [] end)
		+ (if ($o | has("links")) then link_errs($o; $s.creates) else [] end)
	elif $op == "set_field" then
		fstr($o; "field") + (if ($o | has("value")) and $o.value != null then [] else ["missing field 'value'"] end)
	elif $op == "set_state" then fstr($o; "value")
	elif $op == "add_link" then
		fstr($o; "link_type") + fstr($o; "to") + newref($o.to; $s.creates; "to")
	elif $op == "set_pr_description" then
		fstr($o; "text")
		+ (if ($o.target | type) == "string" and ($o.target | startswith("$new:"))
			then ["set_pr_description target '\($o.target)' must be a PR forge id, not a placeholder"] else [] end)
	elif $op == "add_comment" or $op == "set_description" or $op == "set_acceptance_criteria" then
		fstr($o; "text")
	else ["unknown op '\($op)'"] end;

# line_errors: the messages for one line and the create key it defines, if any.
def line_errors($raw; $s; $run; $cids; $cnums):
	if ($raw | test("^[ \t]*$")) then {msgs: ["empty line"], key: null}
	else
		($raw | try {o: fromjson} catch null) as $p
		| if $p == null then {msgs: ["not valid JSON"], key: null}
		elif ($p.o | type) != "object" then {msgs: ["not a JSON object"], key: null}
		else
			$p.o as $o
			| {msgs: (
				fstr($o; "run")
				+ (if ($o.run | type) == "string" and $o.run != $run
					then ["run '\($o.run)' does not match the report run id '\($run)'"] else [] end)
				+ fstr($o; "id")
				+ (if ($o.id | type) == "string" and $o.id != "W\($s.k)"
					then ["id '\($o.id)' should be 'W\($s.k)'"] else [] end)
				+ fstr($o; "op")
				+ fstr($o; "target")
				+ item_errs($o; $cids; $cnums)
				+ fstr($o; "reason")
				+ (if ($o | has("target_url")) and ($o.target_url | type) != "string"
					then ["field 'target_url' must be a string"] else [] end)
				+ (if ($o.op | type) == "string" and $o.op != "create"
					then newref($o.target; $s.creates; "target") else [] end)
				+ (if ($o.op | type) == "string" then op_errs($o; $s) else [] end)
			),
			key: (if $o.op == "create" and ($o.key | type) == "string" and ($o.key | length) > 0
				then $o.key else null end)}
		end
	end;

reduce inputs as $raw ({n: 0, k: 0, creates: {}, out: []};
	.n += 1
	| ($raw | sub("\r$"; "")) as $r
	| (if ($r | test("^[ \t]*$")) then . else .k += 1 end) as $s
	| line_errors($r; $s; $run; $cids; $cnums) as $e
	| $s
	| .out += [$e.msgs[] | "\($s.n): \(.)"]
	| if $e.key != null then .creates[$e.key] = true else . end)
| .out[]
EOF

jq -r -n -R --arg run "$run" --argjson cids "$cids" --argjson cnums "$cnums" \
	-f "$tmp/check.jq" < "$file" > "$tmp/raw" 2> "$tmp/jqerr"
rc=$?
if [ "$rc" -ne 0 ]; then
	echo "work-items: jq failed" >&2
	cat "$tmp/jqerr" >&2
	exit 2
fi
tr -d '\r' < "$tmp/raw" > "$tmp/out"

if [ -s "$tmp/out" ]; then
	while IFS= read -r l; do
		printf 'work-items %s:%s\n' "$file" "$l"
	done < "$tmp/out"
	exit 1
fi
echo "work-items: ok"
