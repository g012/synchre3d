class_name RhythmPattern
extends RefCounted
## A rhythmic figure, ported unchanged from the original Synchre prototype
## (~/godot/synchre/scripts/rhythm_pattern.gd), plus an optional syllable sequence.
##
## `beats` lists, for each note, the duration (in beats) of the gap that ends on that note;
## the first value is the lead-in from the start of the measure. In the original, patterns
## fill one 4-beat measure whose end coincides with the last note.
## `syllables` (optional) are the instrument/button indices each note must use
## (0 = A "Ah", 1 = B "Bra", 2 = X "Ca", 3 = Y "Da"). Empty = any button (original behavior).

const RONDE := 4.0
const BLANCHE := 2.0
const BLANCHEP := 3.0
const NOIRE := 1.0
const NOIREP := 1.5
const CROCHE := 0.5
const CROCHEP := 0.75
const DCROCHE := 0.25
const NOIRE3 := 2.0 / 3.0
const CROCHE3 := 1.0 / 3.0
const DCROCHE3 := 1.0 / 6.0

var pattern_name := ""
var beats := PackedFloat32Array()
var syllables := PackedInt32Array()
## Optional buttons of each note as bitmasks (bit n = button n): lets a note be a chord.
## When set, it replaces `syllables` for matching (`syllables` keeps one button per note).
var masks := PackedInt32Array()
## Arbitrary user data (e.g. the SpellDefinition this pattern casts).
var payload: Variant = null
## Optional power level of the payload this pattern casts (spell families).
var level := 0


func _init(new_name: String = "", new_beats: PackedFloat32Array = PackedFloat32Array(),
		new_syllables: PackedInt32Array = PackedInt32Array()) -> void:
	pattern_name = new_name
	beats = new_beats
	syllables = new_syllables


func size() -> int:
	return beats.size()


## Total length in beats (4 for the original one-measure patterns).
func length() -> float:
	var total := 0.0
	for b in beats:
		total += b
	return total


## Onset of note `i`, in beats from the start of the measure.
func onset(i: int) -> float:
	var t := 0.0
	for k in i + 1:
		t += beats[k]
	return t


## The original prototype's patterns (rhythm only, any button).
static func all() -> Array[RhythmPattern]:
	return [
		RhythmPattern.new("basic1", PackedFloat32Array([NOIRE, CROCHE, CROCHE, NOIRE, NOIRE])),
		RhythmPattern.new("basic2", PackedFloat32Array([NOIREP, CROCHE, NOIREP, CROCHE])),
	]
