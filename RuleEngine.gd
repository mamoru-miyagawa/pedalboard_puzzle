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
##   "cols":  int            # grid columns (default: num, i.e. single row)
##   "rows":  int            # grid rows    (default: 1)
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
		var slots := _all_slots_of(ctx, nm)
		if slots.is_empty():
			continue  # not placed (may be a spare pedal) — doesn't constrain
		for s in slots:
			if not _where_ok(s, ctx.num, rule, ctx):
				return false
	return true

static func _adjacent(ctx: Dictionary, rule: Dictionary) -> bool:
	var negate: bool = rule.get("negate", false)
	for nm in _select_names(ctx, rule.get("select", {})):
		var slots := _all_slots_of(ctx, nm)
		if slots.is_empty():
			continue  # not placed — doesn't constrain
		var subject = _item(ctx, nm)
		var found := false
		for s in slots:
			for ns in _neighbors(s, ctx):
				var other: String = ctx.order[ns]
				if other == "" or other == nm:
					continue  # skip self-neighbors (multi-slot pedals)
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
		for s in _all_slots_of(ctx, nm):
			if s not in slots:
				slots.append(s)
	if slots.size() <= 1:
		return true
	# For multi-row boards, check connected component via BFS.
	var rows: int = ctx.get("rows", 1)
	if rows > 1:
		return _group_connected(slots, ctx)
	# Single row: contiguous range check (original logic).
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
	for i in _region(int(ctx.num), rule.get("region", "all"), ctx):
		var nm: String = ctx.order[i]
		if nm == "":
			continue
		if _matches(_item(ctx, nm), rule.get("select", {}), null):
			n += 1
	return n

static func _no_adjacent_same(ctx: Dictionary, rule: Dictionary) -> bool:
	var field: String = rule.get("field", "")
	var checked := {}  # avoid checking pairs twice
	for i in range(int(ctx.num)):
		var a: String = ctx.order[i]
		if a == "":
			continue
		var ia = _item(ctx, a)
		if ia == null:
			continue
		for j in _neighbors(i, ctx):
			if j <= i:
				continue  # only check each pair once
			var b: String = ctx.order[j]
			if b == "" or b == a:
				continue  # skip self-neighbors (multi-slot pedals)
			var ib = _item(ctx, b)
			if ib == null:
				continue
			if str(ia.get(field, "")) == str(ib.get(field, "")):
				return false
	return true

# ---------------------------------------------------------------- helpers
static func _item(ctx: Dictionary, name: String):
	return ctx.db.get_item(name)

static func _slot_of(ctx: Dictionary, name: String) -> int:
	return ctx.order.find(name)

# Return ALL slot indices where this piece appears (for multi-slot pedals).
static func _all_slots_of(ctx: Dictionary, name: String) -> Array:
	var out: Array = []
	for i in range(int(ctx.num)):
		if ctx.order[i] == name:
			out.append(i)
	return out

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

# Returns the indices of slots adjacent to the given slot in the grid.
# For a single-row board this is just [s-1, s+1] (within bounds).
# For multi-row boards, adjacency is 4-connected (up/down/left/right).
static func _neighbors(s: int, ctx: Dictionary) -> Array:
	var cols: int = ctx.get("cols", int(ctx.num))
	var rows: int = ctx.get("rows", 1)
	var out: Array = []
	if rows <= 1:
		# Single row: linear adjacency.
		if s > 0:
			out.append(s - 1)
		if s < int(ctx.num) - 1:
			out.append(s + 1)
		return out
	# Multi-row grid: 4-connected neighbors.
	var sc: int = s % cols
	var sr: int = int(s / cols)
	if sc > 0:
		out.append(s - 1)          # left
	if sc < cols - 1:
		out.append(s + 1)          # right
	if sr > 0:
		out.append(s - cols)       # up (previous row)
	if sr < rows - 1:
		out.append(s + cols)       # down (next row)
	return out

# Check if a set of slot indices forms a connected component in the grid.
static func _group_connected(slots: Array, ctx: Dictionary) -> bool:
	if slots.size() <= 1:
		return true
	var slot_set := {}
	for s in slots:
		slot_set[s] = true
	var visited := {}
	var queue: Array = [slots[0]]
	visited[slots[0]] = true
	var count := 0
	while queue.size() > 0:
		var current: int = queue.pop_front()
		count += 1
		for nb in _neighbors(current, ctx):
			if slot_set.has(nb) and not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return count == slots.size()

static func _where_ok(s: int, num: int, rule: Dictionary, ctx: Dictionary = {}) -> bool:
	var cols: int = ctx.get("cols", num)
	var rows: int = ctx.get("rows", 1)
	var sc: int = s % cols if cols > 0 else 0
	var sr: int = int(s / cols) if cols > 0 else 0
	match rule.get("where", ""):
		"edge":
			return sc == 0 or sc == cols - 1
		"end_left", "first":
			return sc == 0 and sr == 0
		"end_right", "last":
			return sc == cols - 1 and sr == rows - 1
		"middle":
			return sc > 0 and sc < cols - 1
		"slot":
			return s == int(rule.get("slot", -1))
		"row_a":
			return sr == 0
		"row_b":
			return sr == 1
		"row_c":
			return sr == 2
		"top":
			return sr == rows - 1
		"bottom":
			return sr == 0
	return false

static func _region(num: int, region: String, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	var cols: int = ctx.get("cols", num)
	var rows: int = ctx.get("rows", 1)
	match region:
		"edges":
			for i in range(num):
				var c: int = i % cols if cols > 0 else i
				if c == 0 or c == cols - 1:
					out.append(i)
		"middle":
			for i in range(num):
				var c: int = i % cols if cols > 0 else i
				if c > 0 and c < cols - 1:
					out.append(i)
		"left":
			for i in range(num):
				var c: int = i % cols if cols > 0 else i
				if c < int(cols / 2):
					out.append(i)
		"right":
			for i in range(num):
				var c: int = i % cols if cols > 0 else i
				if c >= int((cols + 1) / 2):
					out.append(i)
		"row_a":
			for i in range(num):
				var r: int = int(i / cols) if cols > 0 else 0
				if r == 0:
					out.append(i)
		"row_b":
			for i in range(num):
				var r: int = int(i / cols) if cols > 0 else 0
				if r == 1:
					out.append(i)
		"row_c":
			for i in range(num):
				var r: int = int(i / cols) if cols > 0 else 0
				if r == 2:
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
		"row_a":
			return "on row A (bottom)"
		"row_b":
			return "on row B (top)"
		"row_c":
			return "on row C"
		"top":
			return "on the top row"
		"bottom":
			return "on the bottom row"
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
		"row_a":
			return "row A (bottom)"
		"row_b":
			return "row B (top)"
		"row_c":
			return "row C"
	return "whole board"
