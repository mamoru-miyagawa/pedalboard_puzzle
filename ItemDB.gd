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
		push_error("ItemDB: cannot open CSV: %s" % path)
		return false

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
