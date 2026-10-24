# Spell book

Every spell of Synchre lives in `assets/spells/spellbook.tres`, and all of them work. In play right now: Push, Shockwave, Quicken, Swap and Minion; the others
are disabled for testing. Level 1 (start + end) belongs to the first *enabled* spell of each
family, so it is currently Push (A A Y), Quicken (Y B Y) and Swap (B X A); the tables below
show the full book. A
spell is in play when its `enabled` flag is on (in the inspector, or `enabled = false` in the
file to take one out). Only enabled spells can be chanted, show on the rhythm panel and are
used by the CPU.

## Families and levels

Spells are grouped in **families** that share the start and the end of their chant; each
spell has its own **middle**:

- **Level 1** = start + end. Short, weak. Only the family's first enabled spell has it.
- **Level 2** = start + middle + end.
- **Level 3** = start + middle + middle + end. Longest, strongest.

Buttons: A "Ah", B "Bra", X "Ca", Y "Da". Every family starts with a different button and
no chant is ever mistaken for another one, at any level (checked by `tests/test_rhythm.gd`
with the whole book). While a chant is still ambiguous (a family's start), the gathered
magic shows every spell it could become and narrows down as you go.

**Precision:** each note may be off by up to 40% of its own duration; the chant's precision
(100% = every note dead on the beat grid that fits it best) scales the spell's power from
55% to 100%. The rhythm panel shows the result, e.g. `PUSH LV2 87%`.

Rhythms below are the gaps in beats before each note (the first note's lead-in is left out).

## Force: A A … Y (A A ½ apart, Y 1 beat after the last note)

| Spell | Middle | Level 1 / 2 / 3 chant | Effect by level |
|---|---|---|---|
| **Push** | B X (½, ½) | A A Y / A A B X Y / A A B X B X Y | A beam from the hands, at once (no travel): shoves and hurts everyone along it. Length 6 / 8 / 10.5, width 0.35 / 0.55 / 0.8, knockback 10 / 15 / 19 (the RB shove is 7.5). Props stop it. From level 2 the ground heaves up along both sides of it as it goes: one long ridge per side (a bump, a hill at level 3) whose front races along the beam, throwing enemies out sideways. |
| Shockwave | X X (1, 1) | – / A A X X Y / A A X X X X Y | Blast around the caster pushing every enemy away. Radius 2.4 / 3.4 / 4.4, force ×0.8 / ×1 / ×1.2. |

## Earth: X Y … X (Y ½ after X, X 1 beat after the last note)

| Spell | Middle | Level 1 / 2 / 3 chant | Effect by level |
|---|---|---|---|
| **Open Pit** | Y Y (½, ½) | X Y X / X Y Y Y X / X Y Y Y Y Y X | Digs in front: a mound sinks one step (two at level 3): mountain → hill → bump → flat; flat ground opens a pit of radius 0.6 / 0.85 / 1.1. |
| Mend Earth | B A (1, ½) | – / X Y B A X / X Y B A B A X | Closes the nearest hole in a cone in front (where you faced, not where auto-aim turns you); with none, raises the ground ahead one step (two at level 3): bump → hill → mountain, shoving whoever stands there (×0.8 / ×1 / ×1.2). |

## Time: Y B … Y (B ½ after Y, Y 1 beat after the last note)

Tempo and speed: the shared tempo, or how fast fighters move.

| Spell | Middle | Level 1 / 2 / 3 chant | Effect by level |
|---|---|---|---|
| **Hasten** | A X (½, ½) | Y B Y / Y B A X Y / Y B A X A X Y | The shared tempo slides up +10 / +20 / +30 BPM (max 160) over one bar, so a chant almost finished still lands. The new tempo carries over to the next rounds. |
| Slow | B B (1, 1) | – / Y B B B Y / Y B B B B B Y | The shared tempo slides down −10 / −20 / −30 BPM (min 80) over one bar. |
| Quicken | X X (½, ½) | – / Y B X X Y / Y B X X X X Y | The caster runs faster: ×1.27 / ×1.45 / ×1.63 for 4 / 8 / 12 beats. Green sparks trail behind. |
| Snare | X B (1, 1) | – / Y B X B Y / Y B X B X B Y | A slow, heavy blob (7 u/s): whoever it hits moves at 65% / 50% / 38% speed for about 3.6 / 6 / 8.4 beats, dripping blue. |

## Hex: B X … A (X ½ after B, A 1 beat after the last note)

| Spell | Middle | Level 1 / 2 / 3 chant | Effect by level |
|---|---|---|---|
| **Knockout** | Y (1) | B X A / B X Y A / B X Y Y A | Spinning star: the target is knocked out 2 / 4 / 6 beats. It can't move, jump, dash or shove (it can still chant), but it can be pushed. |
| Swap | X X (½, ½) | – / B X X X A / B X X X X X A | Small, very fast ball: if it touches someone, caster and target trade places. Range 6 / 10 / 14. |
| Minion | B Y (1, 1) | – / B X B Y A / B X B Y B Y A | Necromancy: shadowy doubles of the caster climb out of the ground in front, chase the nearest enemy and shove. Level 2: 2 small ones; level 3: 3 bigger, stronger, quicker ones wreathed in sparks. They crumble after 16 beats. No limit on how many. |

Durations, distances and forces are also scaled by precision (55–100%).

## How the tempo slide works

The tempo never jumps: Hasten and Slow ramp it linearly over 4 beats. Behind the scenes the
`BeatClock` keeps a tempo map, and every rhythm engine stays locked to the match tempo but
receives *warped* timestamps (the time stretched so that beats of the current tempo fall
where beats of the match tempo would). Recognition is therefore done in beats: a player who
follows the metronome through the slide is judged exactly as at a steady tempo. The new
tempo carries over to the following rounds; only a new game (from the menu) asks for a tempo
again.

## Tuning

- Families, middles, rhythms, colors: `assets/spells/spellbook.tres` (`SpellFamily` and
  `SpellDefinition` resources). Reorder the spells to change which one owns level 1.
- Per-level numbers: `_lv(...)` calls in `scripts/spells/spell_effects.gd`, plus its
  exported base values (group "Book spells").
- Tolerance and the precision-to-power range: `timing_tolerance`, `power_range` on
  `scripts/spells/spell_caster.gd`.

## More ideas

Add new ideas here, then as a `SpellDefinition` in a family (or a new family with an
unused start) once they work.
