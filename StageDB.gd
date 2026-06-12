extends RefCounted
class_name StageDB

## Loads stages either from a CSV in res://config (filename must contain "stage")
## or, if none is found, from res://config/stages.json.
##
## CSV layout — ONE ROW PER RULE. Stage-level columns (Stage Name, Items) only
## need filling on each stage's first row. Columns (header names, any order):
##
##   Stage       grouping id (e.g. 1, 1, 1, 2, 2) — rows with the same id form one stage
##   Stage Name  title shown in game
##   Slots       number of board slots (optional; defaults to the item count).
##               Set fewer than the items to give the player spare pedals.
##   Items       pedal names for the stage, separated by ; (e.g. "BD-2; SD-1; DD-8")
##   Group       optional id; rules sharing a (Stage, Group) are AND-bundled into one
##               requirement that only goes green when ALL its rules pass.
##   Description optional player-facing text shown instead of the auto-generated rule
##               text (e.g. "I don't like green pedals"). On a group, any row's text wins.
##   Type        position | adjacent | group_together | order | count | no_adjacent_same
##   Select      a selector (see below) — the items the rule is about
##   To          a selector — the neighbour target (adjacent only)
##   Where       edge | middle | slot           (position)
##   Slot        1-based slot number             (position, Where=slot)
##   Negate      TRUE/FALSE                      (adjacent: must-NOT sit next to)
##   Field       a column name                   (no_adjacent_same; also "order by")
##   Sequence    values separated by ;           (order)
##   Op          <= | < | >= | > | == | !=       (count)
##   Value       a number                        (count)
##   Region      all | edges | middle | left | right  (count)
##
## A SELECTOR is one cell, written as:
##   all                     every pedal
##   name:BD-2               one pedal by name
##   tag:vintage             pedals carrying a tag
##   Category 2=Gain         pedals where a field equals a value  (or  field:Category 2=Gain)
##   same:Brand              pedals sharing the subject's value of a field

static func load_stages() -> Array:
	var csv := _find_csv()
	if csv != "":
		var arr := _parse_csv(csv)
		if not arr.is_empty():
			return arr
	return _parse_json("res://config/stages.json")

static func _find_csv() -> String:
	# Try fixed names — open directly since file_exists can be unreliable on web.
	for guess in ["res://config/stages.csv", "res://config/Stages.csv"]:
		var f := FileAccess.open(guess, FileAccess.READ)
		if f != null:
			f.close()
			return guess
	# Fallback: scan the config directory (won't work in web, but DirAccess.open
	# safely returns null there so we just fall through to JSON).
	var d := DirAccess.open("res://config")
	if d == null:
		return ""
	for fn in d.get_files():
		if fn.get_extension().to_lower() == "csv" and fn.to_lower().find("stage") != -1:
			return "res://config/%s" % fn
	return ""

static func _parse_json(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("StageDB: no stages CSV and cannot open %s" % path)
		return []
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY and data.has("stages"):
		return data["stages"]
	if typeof(data) == TYPE_ARRAY:
		return data
	return []

static func _parse_csv(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var idx := {}
	var c := 0
	for h in f.get_csv_line():
		idx[String(h).strip_edges().to_lower()] = c
		c += 1

	var stages: Array = []
	var by_id := {}
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 0:
			continue
		var stage_id := _cell(row, idx, "stage")
		var rtype := _cell(row, idx, "type")
		if stage_id == "" and rtype == "":
			continue

		if not by_id.has(stage_id):
			var st := {"id": stage_id, "name": "", "items": [], "rules": []}
			by_id[stage_id] = st
			stages.append(st)
		var stage: Dictionary = by_id[stage_id]

		var sname := _cell(row, idx, "stage name")
		if sname != "" and stage["name"] == "":
			stage["name"] = sname
		var items := _cell(row, idx, "items")
		if items != "" and stage["items"].is_empty():
			stage["items"] = _split(items)
		var slots := _cell(row, idx, "slots")
		if slots != "" and not stage.has("slots"):
			stage["slots"] = int(slots)

		if rtype != "":
			stage["rules"].append(_build_rule(row, idx, rtype))
	f.close()
	return stages

static func _build_rule(row: Array, idx: Dictionary, rtype: String) -> Dictionary:
	var t := rtype.strip_edges().to_lower()
	var rule := {"type": t}
	match t:
		"position":
			rule["select"] = _sel(_cell(row, idx, "select"))
			rule["where"] = _cell(row, idx, "where").to_lower()
			var slot := _cell(row, idx, "slot")
			if slot != "":
				rule["slot"] = int(slot) - 1   # sheet is 1-based, engine is 0-based
		"adjacent":
			rule["select"] = _sel(_cell(row, idx, "select"))
			rule["to"] = _sel(_cell(row, idx, "to"))
			rule["negate"] = _truthy(_cell(row, idx, "negate"))
		"group_together":
			rule["select"] = _sel(_cell(row, idx, "select"))
		"order":
			var by := _cell(row, idx, "field")
			if by != "":
				rule["by"] = by
			rule["sequence"] = _split(_cell(row, idx, "sequence"))
		"count":
			rule["select"] = _sel(_cell(row, idx, "select"))
			rule["op"] = _op(_cell(row, idx, "op"))
			rule["value"] = int(_cell(row, idx, "value"))
			var region := _cell(row, idx, "region")
			rule["region"] = region.to_lower() if region != "" else "all"
		"no_adjacent_same":
			rule["field"] = _cell(row, idx, "field")
	var grp := _cell(row, idx, "group")
	if grp != "":
		rule["group"] = grp
	var desc := _cell(row, idx, "description")
	if desc != "":
		rule["desc"] = desc
	return rule

# --- cell / parsing helpers -------------------------------------------------
static func _cell(row: Array, idx: Dictionary, name: String) -> String:
	var i: int = idx.get(name.to_lower(), -1)
	if i >= 0 and i < row.size():
		return String(row[i]).strip_edges()
	return ""

static func _sel(raw: String) -> Dictionary:
	var s := raw.strip_edges()
	if s == "":
		return {}
	var low := s.to_lower()
	if low == "all":
		return {"all": true}
	if low.begins_with("name:"):
		return {"name": s.substr(5).strip_edges()}
	if low.begins_with("tag:"):
		return {"tag": s.substr(4).strip_edges()}
	if low.begins_with("same:"):
		return {"field": s.substr(5).strip_edges(), "same_as_subject": true}
	if low.begins_with("field:"):
		s = s.substr(6)
	var eq := s.find("=")
	if eq != -1:
		return {"field": s.substr(0, eq).strip_edges(), "value": s.substr(eq + 1).strip_edges()}
	return {"name": s}

static func _split(s: String) -> Array:
	var out: Array = []
	for part in s.replace("|", ";").replace(",", ";").split(";"):
		var t := part.strip_edges()
		if t != "":
			out.append(t)
	return out

static func _truthy(s: String) -> bool:
	return s.strip_edges().to_lower() in ["true", "1", "yes", "y", "x"]

# Accept word aliases for the count operator so cells never need to start with
# "=" (which Google Sheets treats as a formula). Symbols still work too.
static func _op(s: String) -> String:
	match s.strip_edges().to_lower():
		"==", "=", "eq", "is", "equal", "equals", "exactly", "":
			return "=="
		"!=", "ne", "not", "isnt", "not equal":
			return "!="
		"<=", "le", "lte", "at most", "atmost", "max", "no more than":
			return "<="
		">=", "ge", "gte", "at least", "atleast", "min", "no less than":
			return ">="
		"<", "lt", "less", "less than", "fewer", "fewer than", "under":
			return "<"
		">", "gt", "more", "more than", "greater", "greater than", "over":
			return ">"
	return s.strip_edges()
