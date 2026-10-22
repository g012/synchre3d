class_name SpellFamily
extends Resource
## A family of spells sharing the start and the end of their chant. Each spell adds its own
## middle (see SpellDefinition): start + end alone casts the family's first spell at level 1,
## start + middle + end casts a spell at level 2, start + middle twice + end at level 3.

@export var id: StringName
@export var display_name := ""
## Opening syllables and their gaps in beats (the first gap is the lead-in, as in
## RhythmPattern: only the gaps after it matter).
@export var start := PackedInt32Array()
@export var start_beats := PackedFloat32Array()
## Closing syllables and the gaps before each of them.
@export var end := PackedInt32Array()
@export var end_beats := PackedFloat32Array()
