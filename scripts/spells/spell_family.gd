class_name SpellFamily
extends Resource
## A family of spells sharing the start and the end of their chant. Each spell adds its own
## middle (see SpellDefinition): start + end alone casts the family's first spell at level 1,
## start + middle + end casts a spell at level 2, start + middle twice + end at level 3.
##
## Rhythms are written like sheet music: the length (in beats) of each syllable, i.e. the time
## until the next one (croche = 0.5, noire = 1...).

@export var id: StringName
@export var display_name := ""
## Opening syllables and their lengths.
@export var start := PackedInt32Array()
@export var start_lengths := PackedFloat32Array()
## Closing syllables and their lengths (the very last one's length is not used: the spell
## fires on it).
@export var end := PackedInt32Array()
@export var end_lengths := PackedFloat32Array()
