#!/bin/sh
# work-items.sh: validate a work-items.jsonl file.
#
# Usage:
#   sh work-items.sh check <file> <report body> <claims.md>
#
# The format is defined in skills/cca/work-items.md. With jq, this reads every line
# first, then checks that every line is one JSON object; that the common keys and the
# fields of its op are present with the right types, and no other key is; that ids run
# W1 upward with no gap; that every $new:<key> placeholder names a create on an earlier
# line and create keys are unique; that set_pr_description, update_comment, and
# remove_link name forge ids, not placeholders; that set_fields holds a non-empty object
# with no null value; that mentions are well formed and match the {mention:<key>}
# placeholders in text; that run equals the run id in the report body's first heading
# ("# cca audit report: <run-id>"); that every C<n> in items is an item heading
# "#### C<n>: " in the report body; that every "claim <n>" is a claim line in claims.md;
# that every W<n> in items names another operation in the file; and that every
# operation reaches a C<n> or a claim directly or through the W<n> it cites.
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
	echo "work-items: jq not found" >&2
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

def isph($v): ($v | type) == "string" and ($v | startswith("$new:"));

# A placeholder must name a create on an earlier line.
def newref($v; $creates; $what):
	if isph($v) and (($creates | has($v[5:])) | not)
	then ["'\($v)' in \($what) has no create on an earlier line"]
	else [] end;

# $s.ids holds W1 to W<n> for the n operations in the file, and $s.k is this one.
def item_errs($o; $cids; $cnums; $s):
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
			elif ($it | test("^W[0-9]+$")) then
				(if $it == "W\($s.k)" then "item '\($it)' names this operation"
				elif ($s.ids | has($it)) then empty
				else "item '\($it)' names no operation in the file" end)
			else "item '\($it)' is not C<n>, W<n>, or claim <n>" end ]
	end;

# True when items is a non-empty array of strings that are all C<n>, W<n>, or claim <n>.
def items_wellformed($o):
	($o | has("items")) and ($o.items | type) == "array" and ($o.items | length) > 0
	and ($o.items | all(type == "string" and test("^(C[0-9]+|W[0-9]+|claim [0-9]+)$")));

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

def fields_errs($o):
	if ($o | has("fields") | not) then ["missing field 'fields'"]
	elif ($o.fields | type) != "object" then ["field 'fields' must be an object"]
	elif ($o.fields | length) == 0 then ["field 'fields' is empty"]
	else [ $o.fields | to_entries[] | select(.value == null) | "field 'fields' has a null value for '\(.key)'" ] end;

def mention_errs($o):
	(if ($o.text | type) == "string" then [ $o.text | match("\\{mention:[^{}]*\\}"; "g").string ] else [] end) as $used
	| (if ($o | has("mentions") | not) then []
		elif ($o.mentions | type) != "array" then ["field 'mentions' must be an array"]
		else
			[ $o.mentions | to_entries[]
				| .key as $i
				| .value as $m
				| if ($m | type) != "object" or (($m | keys) != ["name", "placeholder"])
					then "mentions[\($i)] must be an object with only 'name' and 'placeholder'"
					elif ($m.name | type) != "string" or ($m.name | length) == 0
					then "mentions[\($i)] name must be a non-empty string"
					elif ($m.placeholder | type) != "string" or ($m.placeholder | length) == 0
					then "mentions[\($i)] placeholder must be a non-empty string"
					elif ($m.placeholder | test("^\\{mention:[A-Za-z0-9._-]+\\}$") | not)
					then "mentions[\($i)] placeholder '\($m.placeholder)' must be {mention:<key>}"
					elif ($o.mentions[:$i] | map(select(type == "object") | .placeholder) | any(. == $m.placeholder))
					then "mentions[\($i)] placeholder '\($m.placeholder)' is a duplicate"
					elif ($o.text | type) == "string" and (($used | any(. == $m.placeholder)) | not)
					then "mentions[\($i)] placeholder '\($m.placeholder)' does not appear in text"
					else empty end ]
		end)
	+ (if ($o.text | type) == "string" then
		(($o.mentions // []) | if type == "array" then map(select(type == "object") | .placeholder) else [] end) as $have
		| [ $used | unique[] | select(. as $u | ($have | any(. == $u)) | not)
			| "text has '\(.)' with no entry in mentions" ]
	else [] end);

def op_fields($op):
	if $op == "create" then ["key", "type", "title", "description", "fields", "links"]
	elif $op == "set_field" then ["field", "value"]
	elif $op == "set_state" then ["value"]
	elif $op == "add_link" or $op == "remove_link" then ["link_type", "to"]
	elif $op == "set_fields" then ["fields"]
	elif $op == "update_comment" then ["comment_id", "text", "mentions"]
	elif $op == "add_comment" or $op == "set_description" or $op == "set_acceptance_criteria" or $op == "set_pr_description" then ["text", "mentions"]
	else null end;

def unknown_errs($o):
	op_fields($o.op) as $f
	| if $f == null then []
	else
		($f + ["run", "id", "op", "target", "items", "reason", "target_url"]) as $ok
		| [ $o | keys_unsorted[] | . as $k | select(($ok | map(select(. == $k)) | length) == 0)
			| "unknown field '\($k)'" ]
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
	elif $op == "set_fields" then fields_errs($o)
	elif $op == "add_link" then
		fstr($o; "link_type") + fstr($o; "to") + newref($o.to; $s.creates; "to")
	elif $op == "remove_link" then
		fstr($o; "link_type") + fstr($o; "to")
		+ (if isph($o.target) then ["remove_link target '\($o.target)' must be a forge id, not a placeholder"] else [] end)
		+ (if isph($o.to) then ["remove_link to '\($o.to)' must be a forge id, not a placeholder"] else [] end)
	elif $op == "update_comment" then
		fstr($o; "comment_id") + fstr($o; "text") + mention_errs($o)
		+ (if isph($o.target) then ["update_comment target '\($o.target)' must be a forge id, not a placeholder"] else [] end)
	elif $op == "set_pr_description" then
		fstr($o; "text") + mention_errs($o)
		+ (if isph($o.target)
			then ["set_pr_description target '\($o.target)' must be a PR forge id, not a placeholder"] else [] end)
	elif $op == "add_comment" or $op == "set_description" or $op == "set_acceptance_criteria" then
		fstr($o; "text") + mention_errs($o)
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
				+ item_errs($o; $cids; $cnums; $s)
				+ (if items_wellformed($o) and (item_errs($o; $cids; $cnums; $s) | length) == 0 and (($s.grounded | has("W\($s.k)")) | not)
					then ["items reach no report item or claim"] else [] end)
				+ fstr($o; "reason")
				+ (if ($o | has("target_url")) and ($o.target_url | type) != "string"
					then ["field 'target_url' must be a string"] else [] end)
				+ (if ($o.op | type) == "string" and $o.op != "create"
					then newref($o.target; $s.creates; "target") else [] end)
				+ (if ($o.op | type) == "string" then op_errs($o; $s) + unknown_errs($o) else [] end)
			),
			key: (if $o.op == "create" and ($o.key | type) == "string" and ($o.key | length) > 0
				then $o.key else null end)}
		end
	end;

# Read every line first. ops: one {id, direct, cites} per non-blank line that is a JSON
# object with an items array, ids W1 upward by position. direct: it lists a C<n> or a
# claim. cites: the W<n> it lists.
def read_ops($lines):
	[ $lines | map(sub("\r$"; "")) | map(select(test("^[ \t]*$") | not)) | to_entries[]
		| .key as $i
		| (.value | try fromjson catch null) as $o
		| {id: "W\($i + 1)",
			items: (if ($o | type) == "object" and ($o.items | type) == "array"
				then [ $o.items[] | select(type == "string") ] else [] end)}
		| {id, direct: (.items | any(test("^(C[0-9]+|claim [0-9]+)$"))),
			cites: [ .items[] | select(test("^W[0-9]+$")) ]} ];

# The ids of the operations that reach a C<n> or a claim, directly or through a cited W<n>.
def grounded_ids($ops):
	reduce range(0; ($ops | length) + 1) as $_ ({};
		. as $g
		| reduce $ops[] as $p (.;
			if (.[$p.id] | not) and ($p.direct or ($p.cites | any($g[.] // false)))
			then .[$p.id] = true else . end));

[inputs] as $lines
| read_ops($lines) as $ops
| ($ops | map({(.id): true}) | add // {}) as $ids
| grounded_ids($ops) as $grounded
| reduce $lines[] as $raw ({n: 0, k: 0, creates: {}, out: []};
	.n += 1
	| ($raw | sub("\r$"; "")) as $r
	| (if ($r | test("^[ \t]*$")) then . else .k += 1 end) as $s
	| ($s + {ids: $ids, grounded: $grounded}) as $c
	| line_errors($r; $c; $run; $cids; $cnums) as $e
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
