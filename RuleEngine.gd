extends RefCounted
class_name RuleEngine

## Three-way status for the UI. A rule stays PENDING (grey) until there's enough
## on the board to judge it, then becomes PASS (green) or FAIL (red).
const STATE_PENDING := 0
const STATE_PASS := 1
const STATE_FAIL := 2

## Evaluates and describes attribute-based puzzle rules.
##
## ctx = {
##   "order": Array[String]  # item Name per slot, "" for empty
##   "num":   int            # number of slots
##   "db":    ItemDB
##   "items": Array[String]  # item Names present in this stage
## }
##
## A "selector" picks items by attribute:
##   {"all": true}                          every item
##   {"name": "BD-2"}                        a specific item
##   {"tag": "vintage"}                      items carrying a tag
##   {"field": "Category 2", "value": "Gain"} items where a field equals a value
##   {"field": "Brand", "same_as_subject": true}  items sharing the subject's value

# ---------------------------------------------------------------- evaluation
static func evaluate(ctx: Dictionary, rule: Dictionary) -> bool:
	match rule.get("type", ""):
		"position":
			return _position(ctx, rule)
		"adjacent":
			return _adjacent(ctx, rule)
		"group_together":
			return _group(ctx, rule)
		"order":
			return _order(ctx, rule)
		"count":
			return _count(ctx, rule)
		"no_adjacent_same":
			return _no_adjacent_same(ctx, rule)
	return false

static func _position(ctx: Dictionary, rule: Dictionary) -> bool:
	for nm in _select_names(ctx, rule.get("select", {})):
		var s := _slot_of(ctx, nm)
		if s == -1:
			continue  # not placed (may be a spare pedal) — doesn't constrain
		if not _where_ok(s, ctx.num, rule):
			return false
	return true

static func _adjacent(ctx: Dictionary, rule: Dictionary) -> bool:
	var negate: bool = rule.get("negate", false)
	for nm in _select_names(ctx, rule.get("select", {})):
		var s := _slot_of(ctx, nm)
		if s == -1:
			continue  # not placed — doesn't constrain
		var subject = _item(ctx, nm)
		var found := false
		for d in [-1, 1]:
			var ns: int = s + d
			if ns < 0 or ns >= int(ctx.num):
				continue
			var other: String = ctx.order[ns]
			if other == "":
				continue
			if _matches(_item(ctx, other), rule.get("to", {}), subject):
				found = true
		var ok := (not found) if negate else found
		if not ok:
			return false
	return true

static func _group(ctx: Dictionary, rule: Dictionary) -> bool:
	var names := _select_names(ctx, rule.get("select", {}))
	if names.size() <= 1:
		return true
	var slots: Array = []
	for nm in names:
		var s := _slot_of(ctx, nm)
		if s != -1:
			slots.append(s)
	if slots.size() <= 1:
		return true
	slots.sort()
	return slots[slots.size() - 1] - slots[0] == slots.size() - 1

static func _order(ctx: Dictionary, rule: Dictionary) -> bool:
	var by: String = rule.get("by", "")
	var seq: Array = rule.get("sequence", [])
	var last_rank := -1
	for i in range(int(ctx.num)):
		var nm: String = ctx.order[i]
		if nm == "":
			continue
		var rank: int
		if by != "":
			var it = _item(ctx, nm)
			if it == null:
				continue
			rank = seq.find(str(it.get(by, "")))
		else:
			rank = seq.find(nm)
		if rank == -1:
			continue
		if rank < last_rank:
			return false
		last_rank = rank
	return true

static func _count(ctx: Dictionary, rule: Dictionary) -> bool:
	return _cmp(_count_n(ctx, rule), rule.get("op", "<="), int(rule.get("value", 0)))

static func _count_n(ctx: Dictionary, rule: Dictionary) -> int:
	var n := 0
	for i in _region(int(ctx.num), rule.get("region", "all")):
		var nm: String = ctx.order[i]
		if nm == "":
			continue
		if _matches(_item(ctx, nm), rule.get("select", {}), null):
			n += 1
	return n

static func _no_adjacent_same(ctx: Dictionary, rule: Dictionary) -> bool:
	var field: String = rule.get("field", "")
	for i in range(int(ctx.num) - 1):
		var a: String = ctx.order[i]
		var b: String = ctx.order[i + 1]
		if a == "" or b == "":
			continue
		var ia = _item(ctx, a)
		var ib = _item(ctx, b)
		if ia == null or ib == null:
			continue
		if str(ia.get(field, "")) == str(ib.get(field, "")):
			return false
	return true

# ---------------------------------------------------------------- helpers
static func _item(ctx: Dictionary, name: String):
	return ctx.db.get_item(name)

static func _slot_of(ctx: Dictionary, name: String) -> int:
	return ctx.order.find(name)

static func _matches(item, sel: Dictionary, subject) -> bool:
	if item == null:
		return false
	if sel.get("all", false):
		return true
	if sel.has("name"):
		return item.get("Name", "") == sel["name"]
	if sel.has("tag"):
		return sel["tag"] in item.get("tags", [])
	if sel.has("field"):
		var f = sel["field"]
		var v
		if sel.get("same_as_subject", false):
			if subject == null:
				return false
			v = subject.get(f, null)
		else:
			v = sel.get("value", null)
		return str(item.get(f, "")) == str(v)
	return false

static func _select_names(ctx: Dictionary, sel: Dictionary, subject = null) -> Array:
	var out: Array = []
	for nm in ctx.items:
		if _matches(_item(ctx, nm), sel, subject):
			out.append(nm)
	return out

static func _where_ok(s: int, num: int, rule: Dictionary) -> bool:
	match rule.get("where", ""):
		"edge":
			return s == 0 or s == num - 1
		"end_left", "first":
			return s == 0
		"end_right", "last":
			return s == num - 1
		"middle":
			return s > 0 and s < num - 1
		"slot":
			return s == int(rule.get("slot", -1))
	return false

static func _region(num: int, region: String) -> Array:
	var out: Array = []
	match region:
		"edges":
			out.append(0)
			if num > 1:
				out.append(num - 1)
		"middle":
			for i in range(1, num - 1):
				out.append(i)
		"left":
			for i in range(0, int(num / 2)):
				out.append(i)
		"right":
			for i in range(int((num + 1) / 2), num):
				out.append(i)
		_:
			for i in range(num):
				out.append(i)
	return out

static func _cmp(n: int, op: String, v: int) -> bool:
	match op:
		"<=":
			return n <= v
		"<":
			return n < v
		">=":
			return n >= v
		">":
			return n > v
		"==":
			return n == v
		"!=":
			return n != v
	return false

# ---------------------------------------------------------------- live state
static func state(ctx: Dictionary, rule: Dictionary, board_full: bool) -> int:
	var ok := evaluate(ctx, rule)
	if board_full:
		return STATE_PASS if ok else STATE_FAIL
	match rule.get("type", ""):
		"position":
			# A placed subject in the wrong spot is wrong right now.
			if _placed_count(ctx, rule.get("select", {})) == 0:
				return STATE_PENDING
			return STATE_PASS if ok else STATE_FAIL
		"adjacent":
			if rule.get("negate", false):
				# Prohibition: red the instant it's broken, else undecided.
				return STATE_FAIL if not ok else STATE_PENDING
			# "must sit next to": green when satisfied, else still pending (the
			# neighbour might arrive) — never prematurely red.
			if _placed_count(ctx, rule.get("select", {})) == 0:
				return STATE_PENDING
			return STATE_PASS if ok else STATE_PENDING
		"group_together":
			if _placed_count(ctx, rule.get("select", {})) <= 1:
				return STATE_PENDING
			return STATE_PASS if ok else STATE_FAIL
		"order":
			if _ranked_count(ctx, rule) <= 1:
				return STATE_PENDING
			return STATE_PASS if ok else STATE_FAIL
		"count":
			return _state_count(ctx, rule)
		"no_adjacent_same":
			return STATE_FAIL if not ok else STATE_PENDING
	return STATE_PENDING

static func _placed_count(ctx: Dictionary, sel: Dictionary) -> int:
	var n := 0
	for nm in _select_names(ctx, sel):
		if _slot_of(ctx, nm) != -1:
			n += 1
	return n

static func _ranked_count(ctx: Dictionary, rule: Dictionary) -> int:
	var by: String = rule.get("by", "")
	var seq: Array = rule.get("sequence", [])
	var n := 0
	for i in range(int(ctx.num)):
		var nm: String = ctx.order[i]
		if nm == "":
			continue
		var rank := -1
		if by != "":
			var it = _item(ctx, nm)
			if it != null:
				rank = seq.find(str(it.get(by, "")))
		else:
			rank = seq.find(nm)
		if rank != -1:
			n += 1
	return n

static func _state_count(ctx: Dictionary, rule: Dictionary) -> int:
	var n := _count_n(ctx, rule)
	var v := int(rule.get("value", 0))
	match rule.get("op", "<="):
		"==":
			if n > v:
				return STATE_FAIL
			return STATE_PASS if n == v else STATE_PENDING
		">=", ">":
			return STATE_PASS if _cmp(n, rule.get("op"), v) else STATE_PENDING
		"<=":
			return STATE_FAIL if n > v else STATE_PENDING
		"<":
			return STATE_FAIL if n >= v else STATE_PENDING
	return STATE_PENDING

# ---------------------------------------------------------------- descriptions
static func describe(rule: Dictionary) -> String:
	match rule.get("type", ""):
		"position":
			return "%s must be %s" % [_sel_text(rule.get("select", {})), _where_text(rule)]
		"adjacent":
			var neg: String = "not " if rule.get("negate", false) else ""
			return "%s must %ssit next to %s" % [_sel_text(rule.get("select", {})), neg, _sel_text(rule.get("to", {}))]
		"group_together":
			return "All %s must be grouped together" % _sel_text(rule.get("select", {}))
		"order":
			var by: String = rule.get("by", "")
			var seq: Array = rule.get("sequence", [])
			if by != "":
				return "%s order: %s" % [by, ", ".join(PackedStringArray(seq))]
			return "Order: %s" % ", ".join(PackedStringArray(seq))
		"count":
			return "%s %d %s in the %s" % [_op_word(rule.get("op", "<=")), int(rule.get("value", 0)), _sel_text(rule.get("select", {})), _region_text(rule.get("region", "all"))]
		"no_adjacent_same":
			return "No two neighbours share the same %s" % rule.get("field", "")
	return "?"

static func _sel_text(sel: Dictionary) -> String:
	if sel.get("all", false):
		return "every pedal"
	if sel.has("name"):
		return str(sel["name"])
	if sel.has("tag"):
		return "%s pedals" % sel["tag"]
	if sel.has("field"):
		if sel.get("same_as_subject", false):
			return "the same %s" % sel["field"]
		return "%s (%s)" % [str(sel.get("value", "")), sel["field"]]
	return "?"

static func _where_text(rule: Dictionary) -> String:
	match rule.get("where", ""):
		"edge":
			return "on an end"
		"end_left", "first":
			return "first (left end)"
		"end_right", "last":
			return "last (right end)"
		"middle":
			return "in the middle"
		"slot":
			return "in slot %d" % (int(rule.get("slot", 0)) + 1)
	return "?"

static func _op_word(op: String) -> String:
	match op:
		"<=":
			return "At most"
		"<":
			return "Fewer than"
		">=":
			return "At least"
		">":
			return "More than"
		"==":
			return "Exactly"
		"!=":
			return "Not"
	return op

static func _region_text(region: String) -> String:
	match region:
		"edges":
			return "end slots"
		"middle":
			return "middle slots"
		"left":
			return "left half"
		"right":
			return "right half"
	return "whole board"
