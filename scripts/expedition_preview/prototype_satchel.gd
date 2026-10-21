extends RefCounted
## PROTOTYPE ADAPTER, not an inventory. Records which generated finds were picked up
## during one preview expedition so extraction can report them. It assigns no value,
## carry limit, loss rule or stash, is never saved, and does not touch the build
## schema. Salvaged equipment stays owned by DuelProgression's existing transaction.
## Final inventory, extraction and economy rules remain open design decisions.
const SCHEMA := "boneshed.expedition_preview.satchel.prototype.0"

var entries: Array = []
var extracted := false

func collect(id: String, item: String) -> bool:
	if extracted or has(id):
		return false
	entries.append({"id": id, "item": item})
	return true

func has(id: String) -> bool:
	return entries.any(func(entry: Dictionary) -> bool: return entry.id == id)

static func label(item: String) -> String:
	var name := item.get_slice(".", 1).replace("_", " ").capitalize()
	return "Vault relic (%s)" % name.to_lower() if item.begins_with("relic.") else name

## Read-only report: finds plus the build items the existing progression owns.
func summary(builds: Dictionary) -> Dictionary:
	var player: Dictionary = builds.player
	return {"schema": SCHEMA, "prototype": true, "extracted": extracted,
		"finds": entries.map(func(entry: Dictionary) -> String: return label(entry.item)),
		"carried": player.carried.duplicate(), "equipped": player.equipped.duplicate()}
