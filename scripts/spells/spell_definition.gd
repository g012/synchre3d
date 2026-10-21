class_name SpellDefinition
extends Resource
## One incantation: which buttons, in which rhythm, and what it does.
## Adding a spell = adding one of these to the SpellBook (no recognition code involved).

enum Effect { PUSH, CREATE_HOLE, CLOSE_HOLE, TEMPO_UP, TEMPO_DOWN, RAISE_MINION, SHOCKWAVE,
	SWAP_BALL, KNOCKOUT }

## Button glyphs and spoken syllables, by button index (Xbox layout).
const BUTTONS: Array[String] = ["A", "B", "X", "Y"]
const SYLLABLES: Array[String] = ["Ah", "Bra", "Ca", "Da"]

@export var id: StringName
@export var display_name := ""
## Buttons, 0 = A "Ah", 1 = B "Bra", 2 = X "Ca", 3 = Y "Da".
@export var syllables := PackedInt32Array()
## Note durations in beats, as in the original Synchre patterns (RhythmPattern): each value
## is the gap ending on that note; together they fill one 4-beat measure.
@export var beats := PackedFloat32Array()
@export var effect := Effect.PUSH
## Palette color of the spell's magic.
@export var palette_index := 15
## In play. Disabled spells stay in the book as ready-to-test ideas.
@export var enabled := true
## What the spell does, for the book.
@export_multiline var description := ""


func to_pattern() -> RhythmPattern:
	var p := RhythmPattern.new(String(id), beats, syllables)
	p.payload = self
	return p


## e.g. "A B X Y A".
func button_string() -> String:
	var parts := PackedStringArray()
	for s in syllables:
		parts.append(BUTTONS[s])
	return " ".join(parts)


## e.g. "Ah-bra-ca-da-bra".
func incantation() -> String:
	var parts := PackedStringArray()
	for i in syllables.size():
		var s := SYLLABLES[syllables[i]]
		parts.append(s if i == 0 else s.to_lower())
	return "-".join(parts)
