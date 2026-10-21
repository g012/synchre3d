class_name SpellBook
extends Resource
## Every spell of the game, including ideas not yet in play: only `enabled` ones can be
## chanted (and show on the rhythm panel). See docs/spellbook.md.

@export var spells: Array[SpellDefinition] = []


## The spells currently in play.
func active() -> Array[SpellDefinition]:
	var out: Array[SpellDefinition] = []
	for s in spells:
		if s.enabled:
			out.append(s)
	return out


func patterns() -> Array[RhythmPattern]:
	var out: Array[RhythmPattern] = []
	for s in active():
		out.append(s.to_pattern())
	return out


func find(id: StringName) -> SpellDefinition:
	for s in spells:
		if s.id == id:
			return s
	return null
