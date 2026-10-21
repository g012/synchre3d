# Spell book

Every spell of Synchre, in play or not yet. They all live in
`assets/spells/spellbook.tres` and all of them work: a spell is in play when its `enabled`
flag is on (open the resource in the inspector, or flip `enabled = false` in the file).
Only enabled spells can be chanted, show on the rhythm panel and are used by the CPU.

Buttons: A "Ah", B "Bra", X "Ca", Y "Da". Rhythm: beats before each note (the first value is
the lead-in, so only the gaps after it matter); every spell fills one 4-beat measure. No two
spells share their first two syllables, so a chant is never mistaken for another one (checked
by `tests/test_rhythm.gd` with the whole book enabled). Spells may share a first syllable: until the
chant tells them apart, the gathered magic shows all of them (see the README).

## In play

| Spell | Buttons | Rhythm | Effect |
|---|---|---|---|
| Push | A B X Y A | 1, ½, ½, 1, 1 | A big, fast ball of light (radius 0.36, 16 u/s, 9 u range): the first enemy it touches is shoved about twice as far as by the RB shove. |
| Open Pit | X Y X Y | 1½, ½, 1½, ½ | Digs in front: a mountain sinks to a hill, a hill to a bump, a bump to flat ground; only flat ground opens into a pit. |
| Mend Earth | B Y B Y A | 1, 1, ½, ½, 1 | Closes the nearest hole inside a cone in front (25°, widened by the hole's size, rim within 3.6 u). With none, raises the ground ahead: bump, hill, mountain. |

## Ideas, ready to test

| Spell | Buttons | Rhythm | Effect |
|---|---|---|---|
| Hasten | Y A Y A | 1, 1½, 1, ½ | Tempo change: the shared tempo slides up 20 BPM (max 160) over one bar. |
| Slow | Y B Y B | ½, ½, 1, 2 | Tempo change: the shared tempo slides down 20 BPM (min 80) over one bar. |
| Raise Minion | B A X A | 1, 1, 1, 1 | Necromancy: a small, shadowy double of the caster climbs out of the ground in front, chases the opponent and shoves softly. It crumbles after 16 beats. No limit on how many, other than chanting speed. Minions can be shoved, hit by spells and fall into holes. |
| Shockwave | A A A Y | 1, 1, 1, 1 | A big blast around the caster (radius 3.4) blows every enemy away, harder up close. |
| Swap | X A X A | 1, ½, 1½, 1 | A small, very fast ball (24 u/s): if it touches someone, caster and target trade places. |
| Knockout | X B X Y | 1, 1, 1½, ½ | A spinning star: the target is knocked out for 4 beats. It can't move, jump, dash or shove (it can still chant), but it can be pushed. |

### How the tempo slide works

The tempo never jumps: Hasten and Slow ramp it linearly over 4 beats, so a chant that is
almost finished still lands. Behind the scenes the `BeatClock` keeps a tempo map, and every
rhythm engine stays locked to the match tempo but receives *warped* timestamps (the time
stretched so that beats of the current tempo fall where beats of the match tempo would).
Recognition is therefore done in beats: a player who follows the metronome through the slide
is judged exactly as at a steady tempo. Each new round starts back at the match tempo.

## Tuning

Numbers for the book spells are exported on `scripts/spells/spell_effects.gd` (group "Book
spells"): tempo step and slide length, minion lifetime / size / shove, shockwave radius and
force, knockout length. Projectile sizes and speeds are set in `_cast_bolt` there.

## More ideas

Add new ideas here, then as a disabled `SpellDefinition` in the book once they work.
