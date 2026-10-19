class_name SpellBook
extends Resource
## The set of incantations a caster knows.

@export var spells: Array[SpellDefinition] = []


func patterns() -> Array[RhythmPattern]:
	var out: Array[RhythmPattern] = []
	for s in spells:
		out.append(s.to_pattern())
	return out
