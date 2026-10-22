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


## Lowest level `spell` can be chanted at: 1 for the first enabled spell of its family
## (start + end alone), else 2.
func min_level(spell: SpellDefinition) -> int:
	for s in active():
		if s.family == spell.family:
			return 1 if s == spell else 2
	return 2


## Every chant in play: each enabled spell at each of its levels.
func patterns() -> Array[RhythmPattern]:
	var out: Array[RhythmPattern] = []
	for s in active():
		for level in range(min_level(s), s.max_level + 1):
			out.append(s.to_pattern(level))
	return out


func find(id: StringName) -> SpellDefinition:
	for s in spells:
		if s.id == id:
			return s
	return null
