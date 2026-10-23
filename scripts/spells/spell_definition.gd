class_name SpellDefinition
extends Resource
## One spell: its family, its own middle syllables, and what it does.
##
## The chant is `family.start + middle * (level - 1) + family.end`: level 1 (start + end,
## short) only exists for the first spell of each family in the book; each repeat of the
## middle raises the level (up to `max_level`). Adding a spell = adding one of these to the
## SpellBook (no recognition code involved).

enum Effect { PUSH, CREATE_HOLE, CLOSE_HOLE, TEMPO_UP, TEMPO_DOWN, RAISE_MINION, SHOCKWAVE,
	SWAP_BALL, KNOCKOUT, QUICKEN, SNARE_BALL }

## Button glyphs and spoken syllables, by button index (Xbox layout).
const BUTTONS: Array[String] = ["A", "B", "X", "Y"]
const SYLLABLES: Array[String] = ["Ah", "Bra", "Ca", "Da"]

@export var id: StringName
@export var display_name := ""
@export var family: SpellFamily
## This spell's own syllables (0 = A "Ah", 1 = B "Bra", 2 = X "Ca", 3 = Y "Da"), between the
## family's start and end, and the gap in beats before each of them.
@export var middle := PackedInt32Array()
@export var middle_beats := PackedFloat32Array()
@export_range(2, 4) var max_level := 3
@export var effect := Effect.PUSH
## Palette color of the spell's magic.
@export var palette_index := 15
## In play. Disabled spells stay in the book as ready-to-test ideas.
@export var enabled := true
## What the spell does, for the book.
@export_multiline var description := ""


## Buttons of the chant at `level`.
func syllables(level: int) -> PackedInt32Array:
	var out := family.start.duplicate()
	for k in level - 1:
		out.append_array(middle)
	out.append_array(family.end)
	return out


## Gaps (beats) before each note of the chant at `level`.
func beats(level: int) -> PackedFloat32Array:
	var out := family.start_beats.duplicate()
	for k in level - 1:
		out.append_array(middle_beats)
	out.append_array(family.end_beats)
	return out


func to_pattern(level: int) -> RhythmPattern:
	var p := RhythmPattern.new("%s_%d" % [id, level], beats(level), syllables(level))
	p.payload = self
	p.level = level
	return p


## e.g. "A A B X Y".
func button_string(level: int) -> String:
	var parts := PackedStringArray()
	for s in syllables(level):
		parts.append(BUTTONS[s])
	return " ".join(parts)


## e.g. "Ah-ah-bra-ca-da".
func incantation(level: int) -> String:
	var parts := PackedStringArray()
	var syl := syllables(level)
	for i in syl.size():
		var s := SYLLABLES[syl[i]]
		parts.append(s if i == 0 else s.to_lower())
	return "-".join(parts)
