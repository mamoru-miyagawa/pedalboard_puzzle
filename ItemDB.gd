extends RefCounted
class_name ItemDB

## Loads item specs from a CSV exported from the design spreadsheet.
## Whatever the name column is called ("Pedal Name", "Name", ...) it is also
## aliased to the canonical key "Name" so the rest of the game can rely on it.

var items: Array = []      # array of field dictionaries
var by_name := {}          # canonical Name -> item

	func load_csv(path: String) -> bool:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_warning("ItemDB: cannot open CSV: %s — using built-in fallback." % path)
			_load_fallback()
			return true

	var cols: Array = []
	for h in f.get_csv_line():
		cols.append(String(h).strip_edges())
	var name_field := _pick_name_field(cols)

	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 0:
			continue
		var item := {}
		for i in range(cols.size()):
			item[cols[i]] = (String(row[i]).strip_edges() if i < row.size() else "")
		var nm := String(item.get(name_field, "")).strip_edges()
		if nm == "":
			continue
		item["Name"] = nm
		item["tags"] = _split_tags(String(item.get("Tags", "")))
		items.append(item)
		by_name[nm] = item
	f.close()
	return true

func get_item(name: String):
	return by_name.get(name, null)

func _pick_name_field(cols: Array) -> String:
	for candidate in ["Pedal Name", "Name", "name"]:
		if candidate in cols:
			return candidate
	return cols[0] if cols.size() > 0 else "Name"

	func _split_tags(s: String) -> Array:
		var out: Array = []
		for part in s.replace("|", ",").replace(";", ",").split(","):
			var t := part.strip_edges()
			if t != "":
				out.append(t)
		return out

	# Built-in fallback so the game always has pedal data even if the CSV is
	# missing from the export pck.
	func _load_fallback() -> void:
		var raw := [
			{"Pedal Name":"DD-8","Brand":"Boss","Color":"White","Category 1":"Digital","Category 2":"Delay","Size":"M","Bypass":"buffered","Era":"modern","Power":"mid","Extra":""},
			{"Pedal Name":"SD-1","Brand":"Boss","Color":"Yellow","Category 1":"Overdrive","Category 2":"Gain","Size":"M","Bypass":"buffered","Era":"modern","Power":"low","Extra":""},
			{"Pedal Name":"BD-2","Brand":"Boss","Color":"Blue","Category 1":"Overdrive","Category 2":"Gain","Size":"M","Bypass":"buffered","Era":"modern","Power":"low","Extra":""},
			{"Pedal Name":"CE-2","Brand":"Boss","Color":"Blue","Category 1":"Chorus","Category 2":"Modulation","Size":"M","Bypass":"true bypass","Era":"vintage","Power":"mid","Extra":"modded"},
			{"Pedal Name":"TR-2","Brand":"Boss","Color":"Green","Category 1":"Tremolo","Category 2":"Modulation","Size":"M","Bypass":"buffered","Era":"vintage","Power":"mid","Extra":""},
		]
		for d in raw:
			var nm := String(d.get("Pedal Name", "")).strip_edges()
			if nm == "":
				continue
			d["Name"] = nm
			d["tags"] = []
			items.append(d)
			by_name[nm] = d
