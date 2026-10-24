class_name SpellDefinition
extends Resource
## One spell: its family, its own middle syllables, and what it does.
##
## Chants by level, rhythms written as note lengths (the parts simply follow each other):
##  * level 1: family.start + family.end (short; only the first spell of each family in the
##    book has it),
##  * level 2: family.start + middle + family.end,
##  * level 3: the level-2 chant, same rhythm and length, with some of the middle's notes
##    played as chords (`chords`): harder, not longer.
## Push: A croche, A noire, B croche, X noire, Y; level 3 makes the X an X+Y chord.
## Adding a spell = adding one of these to the SpellBook (no recognition code involved).

enum Effect { PUSH, CREATE_HOLE, CLOSE_HOLE, TEMPO_UP, TEMPO_DOWN, RAISE_MINION, SHOCKWAVE,
	SWAP_BALL, KNOCKOUT, QUICKEN, SNARE_BALL }

## Lead-in before the first syllable in a pattern's measure (RhythmPattern's first gap):
## with one timing window for every note it only sets how far back taps are looked for.
const LEAD_IN := 1.0

## Button glyphs and spoken syllables, by button index (Xbox layout).
const BUTTONS: Array[String] = ["A", "B", "X", "Y"]
const SYLLABLES: Array[String] = ["Ah", "Bra", "Ca", "Da"]
## Chords that can be asked for, as button bitmasks (bit n = button n): neighbouring face
## buttons only. A+B, B+Y, X+Y, A+X, X+A+B, A+B+Y, B+Y+X, A+X+Y.
const CHORDS: Array[int] = [3, 10, 12, 5, 7, 11, 14, 13]

@export var id: StringName
@export var display_name := ""
@export var family: SpellFamily
## This spell's own syllables (0 = A "Ah", 1 = B "Bra", 2 = X "Ca", 3 = Y "Da"), between the
## family's start and end, and the length of each in beats (croche 0.5, noire 1...).
@export var middle := PackedInt32Array()
@export var middle_lengths := PackedFloat32Array()
## Level 3: for each middle note, the chord to play instead (button bitmask, one of CHORDS),
## or 0 to keep the single syllable. Should contain the note's own syllable.
@export var chords := PackedInt32Array()
@export_range(2, 3) var max_level := 3
@export var effect := Effect.PUSH
## Palette color of the spell's magic.
@export var palette_index := 15
## In play. Disabled spells stay in the book as ready-to-test ideas.
@export var enabled := true
## What the spell does, for the book.
@export_multiline var description := ""


## Main button of each note of the chant at `level` (a chord's own syllable).
func syllables(level: int) -> PackedInt32Array:
	var out := family.start.duplicate()
	if level >= 2:
		out.append_array(middle)
	out.append_array(family.end)
	return out


## Buttons of each note at `level` as bitmasks (chords at level 3).
func masks(level: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in family.start:
		out.append(1 << s)
	if level >= 2:
		for k in middle.size():
			var chord := chords[k] if level >= 3 and k < chords.size() else 0
			out.append(chord if chord != 0 else 1 << middle[k])
	for s in family.end:
		out.append(1 << s)
	return out


## Length (beats) of each syllable of the chant at `level` (the last one is not used).
func lengths(level: int) -> PackedFloat32Array:
	var out := family.start_lengths.duplicate()
	if level >= 2:
		out.append_array(middle_lengths)
	out.append_array(family.end_lengths)
	return out


## The same rhythm as RhythmPattern wants it: the gap before each syllable (the first one is
## the lead-in), i.e. the lengths shifted by one.
func beats(level: int) -> PackedFloat32Array:
	var l := lengths(level)
	var out := PackedFloat32Array([LEAD_IN])
	out.append_array(l.slice(0, l.size() - 1))
	return out


func to_pattern(level: int) -> RhythmPattern:
	var p := RhythmPattern.new("%s_%d" % [id, level], beats(level), syllables(level))
	p.masks = masks(level)
	p.payload = self
	p.level = level
	return p


## Buttons of a mask, e.g. [1, 3] for B+Y.
static func mask_buttons(mask: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in 4:
		if mask & (1 << b):
			out.append(b)
	return out


## e.g. "A A B X+Y Y".
func button_string(level: int) -> String:
	var parts := PackedStringArray()
	for m in masks(level):
		var names := PackedStringArray()
		for b in mask_buttons(m):
			names.append(BUTTONS[b])
		parts.append("+".join(names))
	return " ".join(parts)


## e.g. "Ah-ah-bra-ca+da-da".
func incantation(level: int) -> String:
	var parts := PackedStringArray()
	var ms := masks(level)
	for i in ms.size():
		var names := PackedStringArray()
		for b in mask_buttons(ms[i]):
			names.append(SYLLABLES[b].to_lower())
		var s := "+".join(names)
		parts.append(s.left(1).to_upper() + s.substr(1) if i == 0 else s)
	return "-".join(parts)
