# Synchre — rhythmic spellcasting arena prototype

A small Godot 4 prototype of **Synchre**, a rhythm-based magical combat game, rendered as
cohesive 3D pixel art (in the spirit of t3ssel8r's work). Two little characters on a floating
grassy island fight by casting spells: you move and jump freely while chanting incantations
as rhythmic sequences of A/B/X/Y presses. A Push spell blasts your rival toward the holes,
Open Pit tears a new hole in the ground, and Mend Earth closes one, or raises the ground into
a bump, a hill and finally a mountain. A plain melee shove (RB) is always at hand too, weaker
than the Push spell. More spells wait in the [spell book](docs/spellbook.md).

## Running

- Godot **4.7** (Forward+), no plugins, assets or downloads needed. The `godot_mcp` addon in
  `addons/` is only an editor automation bridge and isn't required to play.
- Open the folder in Godot and press **F5**, or run `godot --path .` from this directory.
- The game renders at 640×360 "safe area" pixels and scales up exactly at 720p, 1080p and
  1440p (2×/3×/4×). Other window sizes use an anti-aliased pixel-art upscaler, so pixels stay
  the same size.

## Modes

The game opens on a **menu** (stick / D-pad / arrows to choose, A / Enter / Start to pick):

- **Single player: survival.** Pip alone on an endless field dotted with holes, ponds, trees, bushes, rocks and
  dancing flowers. Enemies
  (shadowy mushroom grunts) keep coming from just off screen and rush you, forever: more of
  them, faster, tougher and in packs as the minutes pass. They die when they fall into a hole
  or run out of health (shoves and spells hurt them); you lose when you fall or your health
  (100) runs out. The top of the screen shows health, time and kills; after a run, Start
  plays again. It is meant for practice: moving and chanting at the same time, then doing it
  from memory with the spell sheets hidden (**R3 / F2** toggles them).
- **Tutorial: learn the spells.** Pip alone on the island with three training dummies, one
  lesson per spell in play and per level (13 right now). Each lesson starts with the game
  chanting the spell itself on the beat, in Pip's voice, its syllables lighting up on a card
  at the top (the chant is drawn spaced by its rhythm, one tick per beat). Then it's your
  turn: cast it 3 times (start on any beat) to move on. The card lights your syllables as
  you chant and tells you how it went: the precision, why a chant fizzled, or which spell
  you cast instead. D-pad left / right (P / N) changes lesson, D-pad up (H) listens again.
  The dummies come back when knocked away or into a hole, and so do you.
- **Duel vs CPU** and **Duel vs human**: the island duels described below.

**Start / Back / Esc** pauses: resume, restart (a new survival run, or the duel from 0 - 0
at the same tempo) or quit to the menu. Leaving the window (alt-tab) pauses too. Every mode
starts with player 1 tapping the tempo while everyone stands still; the moment it locks, the
fight (or run) is on.

## Controls

The gamepad is the primary interface (Xbox layout). Pad 1 controls Pip; in 2-player mode pad 2
controls Mog. All bindings are InputMap actions (`p1_*`, `p2_*`) and can be remapped in
Project Settings.

| Action | Gamepad | Keyboard P1 | Keyboard P2 (2P mode) |
|---|---|---|---|
| Move (relative to the screen) | Left stick | WASD | Arrow keys |
| Syllable "Ah" | A | K | Numpad 2 |
| Syllable "Bra" | B | L | Numpad 6 |
| Syllable "Ca" | X | J | Numpad 4 |
| Syllable "Da" | Y | I | Numpad 8 |
| Jump | RT (analog, 50% threshold, one jump per pull) | Space | Numpad 0 / Numpad Enter |
| Shove (melee push) | RB | E | Numpad . |
| Dash (toward the stick, else forward; 0.65 s cooldown, one per jump in the air) | LB | Left Shift | Numpad + |
| Hold: strafe (keep facing). Duels: also manual aim while held (auto-aim otherwise); survival: aim is always manual | LT | Q | Numpad − |
| Pause menu (resume / restart / quit) | Start or Back | R or Esc | |
| Hide / show the spell sheets | R3 (right stick click) | F2 | |
| Tutorial: previous / next lesson, listen again | D-pad left / right, up | P / N, H | |
| Fullscreen / debug: hide outline pass | | F11 / F1 | |

Keyboard keys are bound by physical position, so they work the same on AZERTY. In 1-player
mode, either keyboard side and either pad control Pip.

Moving, jumping and chanting are fully independent. You can run, change direction, jump over
a hole or get knocked back in the middle of an incantation, and finish a spell in mid-air.
There is no "cast" button and movement is never locked while casting.

**Rules:** each round, make your opponent lose its footing over a hole or off the island's
edge. The survivor wins the round, the score updates and a new round starts after a short
delay. Holes and mounds made by spells reset each round.

**Survival field:** the same Arena node switches to an endless mode (`Arena.endless`): no
island edge, flat ground that streams around the player (a fixed set of ground chunks moved
along, collision chunks recycled, grass and props generated chunk by chunk), holes generated per
7×7 cell from a hash of the cell (about half the cells have one), and ponds per 14×14 cell
(40% chance; their water and waterfalls come and go with them), so a place keeps its holes
and ponds when you come back. The grass
shader drops tufts over holes by itself, so grass never waits for holes. Enemies are
ordinary fighters with health and a cheap `SwarmBrain` (rush, sidestep holes, shove);
`scripts/survival.gd` spawns them and ramps the pressure up over three minutes.

**Arena:** the island is twice as wide and deep as before (4× the area) and is generated
afresh at every launch: a new outline, 11–15 holes, trees around the rim, bushes, rocks,
stumps and mushrooms, and both spawn points on safe ground (the seed is printed to the
console). The camera follows both fighters and zooms out a little when they are far apart.

## Rhythmic spellcasting

1. **Player 1 sets the tempo, once, before the match.** The game opens on `SET THE TEMPO`:
   tap any face button four times evenly (the original Synchre count-in rule: the taps and
   the wait after them within ±20%). The tempo is clamped to **80–160 BPM**, and the match
   starts the moment it locks. That tempo is shared by both players, the CPU and everything
   that moves to the music (metronome, dancing flowers) for the whole match; going back to the menu
   starts a new game and asks again. (Tempo spells from the book can slide it; the new
   tempo carries over to the following rounds.)
2. **Chant.** Spells come in **families** that share the start and the end of their chant;
   each spell has its own middle. Chant the start and the end alone for a quick **level 1**
   (the family's first spell), add the spell's middle once for **level 2**, twice for
   **level 3**: longer chants, stronger spells.

   In play right now (the others wait in the book, disabled):

   | Family | Start … End | Spells (middle) |
   |---|---|---|
   | Force | A A … Y | **Push** (B X), Shockwave (X X) |
   | Time | Y B … Y | **Quicken** (X X) |
   | Hex | B X … A | **Swap** (X X), Minion (B Y) |

   The first enabled spell of each family (in bold) also has level 1. Rhythms are written
   as note lengths (♪ croche, ♩ noire, ♩. noire pointée) and the parts simply follow each
   other: Push level 1 is A♪ A♩ Y, level 2 A♪ A♩ B♪ X♩. Y, level 3 A♪ A♩ B♪ X♩. B♪ X♩. Y.
   Every middle lasts whole beats, so a repeated middle is the same beat-aligned rhythm.

   **Push** is a beam: it shoots out at once (no travel time), shoves and hurts everyone
   along it, and grows longer and wider with each level. From level 2 the ground heaves up
   along both sides of it as it goes, like the sea parting: one long continuous bump per
   side (a hill at level 3), whose front races along the beam, throwing enemies out to the
   sides. **Minion** raises 2 small minions at level 2, and 3
   bigger, stronger, quicker ones wreathed in sparks at level 3. Rhythms, effects and per-level numbers
   are in the [spell book](docs/spellbook.md).

   Timing is forgiving: every note may land up to **0.2 beat** early or late (120 ms at
   100 BPM), the same window whatever its length (the original Synchre allowed 20% of each
   note's own length), but **precision** scales the spell's power: a chant dead on the
   beat casts at full power, a sloppy one down to 55% (`power_range` on `SpellCaster`).
   **A spell can start on any beat** (or between beats): the rhythm is checked relative to
   your own first syllable, as in the original.

   **Auto-aim** (duels only, unless LT is held; never in survival): aimed spells (Push, Swap, Knockout, Open Pit,
   Mend Earth's raised ground, Minion) turn you toward your opponent (survival: the nearest
   enemy) as they fire. **Hold LT** to strafe: you keep facing the way you face while you
   move, and dashes and shoves don't turn you either. In duels it also switches to manual
   aim (spells fire straight ahead); in survival aim is always manual, LT only strafes. Mend Earth still closes the holes in front of where you faced.
3. **Read the feedback.** Gathered magic grows at your hands with each correct syllable, and
   your character poses and bobs. While your syllables could still become several spells
   (they share an opening, like X for Open Pit, Swap and Knockout), the magic is a pale,
   shared glow with a small satellite in each possible spell's color; satellites fold into
   it as the chant rules their spell out, and once one spell is left the glow morphs into
   its color. It only fizzles when no spell can continue the chant.

   A **ring at your feet** pulses on every beat (a wider wave on each bar's first beat), so
   you can keep time without looking away from the fight, and shows the chant in progress:
   one pip per syllable, clockwise from the top, lit in the button's color once validated,
   faint for the ones still to come. The CPU has one too.

   The rhythm panel (bottom-left; P2 bottom-right; the CPU's is compact) shows:
   - your last syllables with a timing tick for each: centred = on time, shifted left or blue
     = early, right or orange = late, red cross = out of tolerance
   - each spell's level-2 chant on a beat timeline, grouped by family with the shared start
     and end dimmed, lighting up as you play them (every spell still possible is lit)
   - whether auto-aim is on
   - the outcome: `PUSH LV2 87%` (level and precision), or a fizzle with its reason (`wrong syllable`, `too early`,
     `too late`, `tempo lost`). A fizzle dissipates the magic in grey puffs.

Every syllable has its own chanted voice (Ah, Bra, Ca and Da on the notes A3, C4, D4 and E4,
so each incantation is a tiny melody), and each spell effect has its own sound (bolt
whoosh, ground cracking open, earth mending with a chime, ground heaving up), plus a fizzle.
They are synthesized by `tools/gen_audio.py`.

**Dancing flowers** with little faces ring the island and dance to the match tempo, in the
spirit of Super Mario Bros. Wonder: a squash on every beat, swaying to alternate sides with
the head counter-tilting, leaves waving, petals pulsing, and a hop with squinted eyes on
each bar's downbeat. Before the tempo is set they just sway. The small flowers in the grass
bop on the beat too.

**Ponds:** each island has one or two small ponds you can wade through: shallow water
(about 0.3 deep) in a bowl dug into the lawn, with a sandy shore. Wading slows you to 72%,
throws up spray as you move and leaves ripple rings around you; your legs disappear under
the surface. Where a pond meets the island's edge it spills over as a waterfall that falls
into the sky and breaks up into mist; where it meets a hole (layout holes, or one opened by
Open Pit right in the pond) it pours into the hole and fades into the dark. Mend Earth
closing the hole stops the waterfall. The first pond of a random layout always straddles
the front edge; extra ones sit against a hole.

The water follows the style of [David Holland's 3D pixel art](https://www.davidhol.land/articles/3d-pixel-art-rendering/):
short, world-space, view-aligned horizontal glints that flick on and off, on top of
palette-banded depth colors (light shallows to deep teal, dithered), a foam line along the
shore and the spill lips, a drifting sheen, and cloud shadows. Instead of reading the depth
buffer, depth comes from the same analytic ground height the terrain uses, so it stays
exact as holes open and mounds rise. Waterfalls are ribbons hung from the lip, traced with
marching squares on the ground SDF inside the pond (about 12 ms per pond, only when a hole
near a pond opens or closes); streaks scroll down in world-anchored pixel columns.

Bumps and hills are walkable. Mountain flanks are too steep to climb, and they stop Push
bolts, which otherwise glide over gentle slopes. Holes can be opened through a hill.

The CPU opponent chants too (easy for now): every few seconds it picks a spell that suits
the situation (Push at range, Open Pit when you're a couple of steps ahead, Mend Earth near
a hole...), mostly at level 1 or 2, presses the syllables on the beat with a little wobble,
and now and then flubs a syllable and fizzles. Its ring shows what it is chanting.

## What's in the box

- **Arena:** a randomly generated floating island with real holes. The holes are gaps in
  both the rendered ground and the collision. Hole walls, cliffs and the closed rocky underside share one
  depth-based colouring, so soil fades through dark earth and brown rock into stone with
  dithered borders. The grass grows in dense, wind-animated clumps. There are flowers, trees with
  swaying leaf canopies, rocks, stumps and mushrooms, toon-shaded clouds drift around the
  island, and cloud shadows move across the ground.
- **Characters** modeled in Blender: *Pip* (red fox-eared hood, yellow scarf) and *Mog*
  (spotted mushroom cap, grumpy brows). They're animated procedurally:
  - idle (breathing, blinking) and a waddling walk
  - casting pose (hands gathering magic, a bob on each syllable), layered over walking and jumping
  - jump (stretch on take-off, squash on landing)
  - push wind-up and thrust (CPU melee)
  - hit reaction (flash, squint, recoil lean)
  - falling (flailing, spinning, sinking into the dark)
  - victory hops
  - squash and stretch on spawn, landing, pushing and hits
- **Feel:** acceleration and deceleration, quick turns, a forward lunge on push, hit-stop,
  knockback with friction, camera shake, impact star, ring, sparks, running dust, a dust ring
  when someone loses footing, jumping with air control, and buffered jump input.
- **AI:** chases you and tries to get *behind* you relative to your nearest edge, so its push
  sends you toward danger. It looks ahead with the arena's distance field to avoid holes and
  props, and it has a short reaction delay, so a sidestep can make it whiff and lunge toward a
  hole.

## Rendering architecture

Everything renders into a low-res `SubViewport` (`scripts/render/pixel_view.gd`), which is
then upscaled.

1. **Orthographic follow camera, texel-snapped** (`scripts/render/pixel_camera.gd`). The
   camera is pitched 40° and tracks the fighters' midpoint; it only zooms out (to keep both
   on screen), never below the authored pixel density. Its position is snapped to whole texels in its own view plane, so static
   geometry rasterizes identically every frame. The snapped-away remainder (`texel_error`)
   shifts the upscaled image by sub-pixels, which keeps camera shake smooth. Characters' visual
   roots are snapped to the same grid with `snap_point()`, so they don't shimmer while moving.
   The viewport has a hidden 1-pixel border to absorb that offset.
2. **One shared palette with hand-style light ramps** (`assets/palette/palette.json` →
   `tools/gen_palette.py` → `palette_ramp.png`). There are 32 colors, each with
   shadow, half, lit and highlight bands. The bands are hue-shifted in OKLCh: shadows drift
   cool and violet, highlights drift warm. Surfaces never output arbitrary colors. They carry a
   *palette index*, and the light pass picks a band
   (`shaders/include/toon.gdshaderinc`). The result is discrete cel bands, no PBR look, and a
   strictly limited palette. Band edges get an optional, screen-stable 4×4 Bayer dither.
3. **Blender asset convention.** Every face's palette index is baked into a second UV channel
   (Godot `UV2`), so the Blender models are colored by the game palette at runtime
   (`shaders/toon_palette.gdshader`).
4. **Outline and edge post-process** (`shaders/post_outline.gdshader`), drawn by a full-screen
   quad on the camera:
   - *Outlines:* a pixel that is in front of a neighbor by more than a slope-aware depth
     threshold is darkened. Outlines are one pixel wide and always on the foreground side.
     Characters get a darker outline than the scenery.
   - *Edge highlights:* convex creases at similar depth are lightened on the sun-facing side.
     This is what gives hole rims and the island lip a readable lit edge.
   - *Material IDs* are written to `ROUGHNESS` (solid, character, foliage, grass), so grass
     never gets outlined and foliage only outlines against non-foliage. In Godot 4.7, roughness
     is stored unpacked in the normal-roughness buffer's alpha channel.
   - *Sky:* pixels with no geometry become a banded, dithered gradient.
5. **Grass** (`shaders/grass.gdshader`, `scripts/arena/vegetation.gd`): grass is one MultiMesh
   of 16×16-texel billboard tufts. Each tuft's base is snapped to the pixel grid, so sprite
   texels map 1:1 to screen pixels. Lighting and shadow are sampled at the base
   (`LIGHT_VERTEX`), so a tuft shades exactly like the ground it grows from. Blades go from
   soil-colored at the base, to lawn green, to bright tips. Soil under clumps is darkened using
   a baked density map. Wind is traveling gusts plus flutter, quantized to whole texels, and
   grass bends away from the characters.
6. **Foliage** (`shaders/foliage.gdshader`, `scripts/arena/props.gd`): the Blender trees carry
   rough "blob" meshes. Leaf-cluster billboards are scattered over the blob surfaces, and each
   card is lit with the blob normal. That gives canopies clean toon bands while the leaf texture
   breaks up the silhouette. The blob itself is drawn as a dark core to fill gaps.
7. **Upscale** (`shaders/pixel_upscale.gdshader`): t3ssel8r's anti-aliased nearest-neighbor
   filter. At integer scales it's exact nearest, and it handles sub-pixel offsets and
   fractional scales without uneven pixel sizes.
8. **HUD** is drawn *inside* the low-res viewport with a generated 5×7 bitmap font that has a
   baked outline (`tools/gen_font.py`), so text sits on the same pixel grid as the world.

Performance: about 1,400–1,600 FPS uncapped on the 4× island on an RX 9060 XT, including while
holes and mounds animate (vsync is on by default).

## Gameplay architecture

- `scripts/arena/arena.gd` (`@tool`) and `arena_layout.gd`: the ground is described
  analytically — an organic island outline, minus runtime holes, raised by runtime mounds.
  Only what never changes is meshed: the grass top over the island outline (marching
  squares, chunked for culling) and one watertight, smooth-shaded outer shell (cliff plus
  rocky underside). See *Arena and physics* below for how holes and mounds work.
  `ground_sdf()` and `height_at()` mirror the shader math and are also the AI's map.
- `scripts/character/character.gd`: a `CharacterBody3D` with a small state machine (spawning,
  active, pushing, hitstun, falling, out, victory). Support uses the exact ground outline
  (`Arena.is_over_ground`), the same function the shaders cut holes with. When a grounded
  character's centre is over a hole it stops colliding with the floor and drops, held inside
  the hole it fell into. Pushes are resolved deterministically: a
  range check plus a cone check, then a fixed impulse, so they feel skill-based.
- `scripts/character/player_brain.gd` and `ai_brain.gd` drive a character's movement, jump
  and melee push (RB for players).
- `scripts/main.gd`: the menu and modes, rounds, scoring, survival runs, per-player input and casters, and
  the HUD.

### Spellcasting pipeline

Each stage only talks to the next one through plain data or signals:

1. **Input capture** — `scripts/input/player_input.gd`: each face-button press is emitted
   from `_input` as a timestamped event (`Time.get_ticks_usec`, as in the original). Movement
   and the RT jump are polled separately during physics.
2. **Tempo and rhythm recognition** — `scripts/rhythm/rhythm_engine.gd`, a port of the
   original `RhythmInput` with the same rules (tempo inference, blank, 20% per-note
   tolerance, matching relative to the taps, consumed taps). In the game the tempo comes
   from player 1's count-in before the match (`scripts/main.gd`, same detection code) and is
   given to every engine with `set_fixed_tempo` (never blanks, never re-detected).
   `scripts/rhythm/beat_clock.gd` holds it for the metronome, the dancing flowers and the
   grass (`beat_time` shader global). Still available in the engine for other modes: a
   12-beat blank (`blank_beats`, the original used 6) and tempo from a spell's opening
   notes (`tempo_from_openings`). Time is injected, and the
   original's once-per-frame checks are solved in closed form, which equals the original at
   infinite frame rate. Recognition therefore depends only on timestamps, never on render or
   physics rate. Patterns come from `scripts/rhythm/rhythm_pattern.gd`, the original pattern
   class plus optional per-note buttons.
3. **Incantation progress** — the same engine reports per-note judgements (perfect, early,
   late, miss), the longest valid prefix, and why an incantation broke. These all use the
   same tolerance math as the authoritative full match.
4. **Spell selection** — `assets/spells/spellbook.tres` holds `SpellDefinition` resources
   (buttons, note durations, effect, color). Adding a spell means adding a resource; no
   recognition code changes.
5. **Execution** — `scripts/spells/spell_effects.gd` resolves a completed spell against the
   arena: `MagicBolt` for Push (and Swap / Knockout); `Arena.open_hole()` / `close_hole()` /
   `raise_ground()` / `grow_mound()` / `lower_mound()` for Open Pit and Mend Earth, including
   the knockback from rising ground; minions, shockwave and tempo slides for the book spells.
   It is the only spell code that touches gameplay.
6. **Feedback** — `scripts/spells/spell_caster.gd` drives the gathering `MagicOrb`, the hand
   pose, the syllable voices (played the instant a button is pressed), the metronome (the
   original's sounds) and UI signals; `scripts/ui/rhythm_panel.gd`
   draws the panel.
7. **Arena and physics** — holes and mounds are small dictionaries in `Arena`; nothing is
   re-meshed when they change:
   - **Rendering:** their parameters go into a 64×6 float "features" texture (one texel per
     hole, mound or pond). The terrain shader lifts the grass top by the mounds in the vertex
     stage and discards its fragments over holes; grass tufts ride the mounds and collapse
     over holes. Each hole has its own rocky wall tube, built once when it opens (~1 ms) and
     only scaled while it opens or closes; its rim follows the mound height in the shader.
   - **Collision:** a grid of small `HeightMapShape3D` chunks (17×17 samples, 0.2 units).
     Samples are the mound height, or NaN (a real gap, supported by Jolt) over holes and off
     the island. A changing hole re-samples only the points it covers: about 0.2 ms per
     physics tick. A growing mountain, the largest change, takes about 1.4 ms every other
     tick while it rises (its outline is cached so only its scale changes). The previous
     design re-meshed terrain chunks at 5–9 ms per update.

For multiplayer later: syllables are `(player, button, time)` events and recognition is
deterministic in their timestamps, so the same events replayed anywhere give the same spells.
Spell effects are separate from recognition and could be resolved authoritatively.

## Tuning

| What | Where |
|---|---|
| Ponds: count, radius, depth (water level is `Arena.WATER_LEVEL`); wading speed (`wade_speed` on the character) | `scenes/arena_config.tres` (Ponds group), `scripts/arena/water.gd`, `shaders/water.gdshader`, `shaders/waterfall.gdshader` |
| Island size (`size_scale`), random layout on/off and feature counts, authored layout, grass density | `scenes/arena_config.tres` (`ArenaConfig`). Edit it in the inspector and the arena rebuilds in the editor (which always shows the authored layout). |
| Bump / hill / mountain size and growth time | `MOUND_LEVELS`, `MOUND_GROW_TIME` in `scripts/arena/arena.gd` |
| Camera follow margin, max zoom-out | Exported vars on `scripts/render/pixel_camera.gd` |
| Move speed, acceleration, jump velocity, air control, push strength, knockback friction, hit-stop | Exported vars on `scripts/character/character.gd` |
| Spells and families (buttons, rhythm, effect, color) | `assets/spells/spellbook.tres` |
| Timing window (beats, every note), precision-to-power range | `timing_window`, `power_range` on `scripts/spells/spell_caster.gd` |
| Pit radius and placement, Mend Earth reach, mound distance and knockback | Exported vars on `scripts/spells/spell_effects.gd` |
| Sounds | `python3 tools/gen_audio.py` (numpy), volumes on `spell_caster.gd` / `spell_effects.gd`; metronome volume `volume_db` on `scripts/rhythm/beat_clock.gd` (set just above the chanting) |
| Tutorial: casts per lesson, dummy placement | `SUCCESSES`, `DUMMY_*` in `scripts/tutorial.gd` |
| Push bolt speed, range, size, strength | `scripts/spells/magic_bolt.gd` |
| Rhythm tolerance, blank length, tempo from spell openings | `scripts/rhythm/rhythm_engine.gd` (`TOLERANCE` as in the original; `blank_beats`, `tempo_from_openings`) |
| AI reaction time, edge fear, chanting rate / timing wobble / flub chance | `scripts/character/ai_brain.gd` |
| Survival pressure: spawn ring, spawn interval, enemies alive, enemy health / speed / damage, ramp time | Exported vars on `scripts/survival.gd`; Pip's health `SURVIVAL_HP` in `scripts/main.gd` |
| Spell damage (survival) | `bolt.damage` and `take_damage` calls in `scripts/spells/spell_effects.gd`; shove damage `push_damage` on the character |
| Which spells are in play; book spell numbers | `enabled` in `assets/spells/spellbook.tres`; see `docs/spellbook.md` |
| Pixel density (world units per pixel), camera angle and focus | `scripts/render/pixel_camera.gd` |
| Outline and highlight thresholds and colors, sky | Uniforms in `shaders/post_outline.gdshader` |
| Colors | `assets/palette/palette.json`, then run `python3 tools/gen_palette.py` |
| Wind and cloud shadows | Shader globals `wind_direction`, `wind_strength` and `cloud_shadow_strength` in Project Settings |

## Asset pipeline

All assets are generated by scripts in this repository. Nothing was downloaded or bought.

- **Blender (5.x):** `tools/blender/build_characters.py` and `tools/blender/build_props.py`
  build the meshes with `bmesh` and export `.glb` files into `assets/models/`. Run one from
  Blender's Python console:
  `p = "<project>/tools/blender/build_props.py"; exec(open(p).read(), {"__file__": p})`.
  The `.blend` sources are kept in `assets/source/`.
- **Python (needs Pillow):** `tools/gen_palette.py`, `tools/gen_sprites.py` (grass, flower,
  leaf and FX atlases) and `tools/gen_font.py`. `tools/gen_audio.py` (numpy) synthesizes
  the syllable voices and spell sounds.
- **Godot:** the terrain, grass, collision and clouds are built at load time from the config.

## File layout

```
scenes/       main.tscn, character.tscn, arena_config.tres
scripts/      main.gd · render/ · arena/ · character/ · input/ · rhythm/ · spells/ · fx/ · ui/
shaders/      toon_palette, terrain, grass, foliage, fx, magic, post_outline, pixel_upscale, include/
assets/       palette/, models/ (glb), textures/, fonts/, materials/, spells/, audio/, source/ (.blend)
tests/        test_rhythm.gd (automated rhythm-recognition tests)
tools/        palette / sprite / font generators, blender/ build scripts
```

## Tests

```
godot --headless --path . -s tests/test_rhythm.gd
```

The suite has 89 checks covering:

- tempo lock time and BPM
- tempo tolerance boundaries
- the 12-beat blank (and the original 6) and tempo changes
- a fixed match tempo: never blanks, cannot be changed by taps, and every spell casts when
  started on each beat of the bar, on off-beats and at an arbitrary phase
- tempo set by a spell's opening: every spell cast from silence at 85–150 BPM with sloppy
  timing, wrong rhythm or wrong buttons rejected, the tempo kept for the next spell
- every spell at 70–160 BPM
- wrong and missed syllables
- exact late/early tolerance boundaries
- early/late ratings
- timeouts, with identical results whatever the update granularity
- rapid successive casts and consumed taps
- tempo drift within and beyond tolerance
- restarting an incantation
- the spell book: families and levels; every chant of every level castable and never
  mistaken for another, at the original and the game tolerance
- precision: a dead-on chant scores 1, a sloppy one less; the wide tolerance accepts what
  the original rejects
- tempo slides: a chant following a slide is cast, a nearly finished one still lands
- shared openings: progress follows every possible spell, narrows without fizzling, drops a
  spell whose next note is overdue without failing the others, and fizzles once when none fits
- agreement with a line-by-line port of the original frame-sampled algorithm on 150
  randomized takes

## Verification notes

Built and tested against Godot 4.7.2 and Blender 5.2.1:

- I inspected rendered screenshots at 2× and 4× throughout development.
- Movement, pushes, knockback, obstacle collision, falling into holes and off the edge,
  elimination, round reset and scoring, the 1P/2P toggle and the AI were all exercised with
  deterministic frame stepping and injected input.
- A headless run reports no script errors.
- Spellcasting was played through the real input path with simulated gamepad and keyboard
  events, in real time at 90 BPM. That covered:
  - tempo lock and the three spells
  - casting while moving, jumping mid-incantation, and finishing a spell airborne
  - wrong-syllable and late-note fizzles, then recovery
  - Push knocking the rival into a hole
  - opening and closing holes
  - jumping over a hole
  - pad 1 / pad 2 / keyboard routing in 2-player mode
  - several consecutive rounds with hole resets
- After the 4× arena and ground rework, again through simulated pad input:
  - Mend Earth from silence (tempo locked on its 3rd note at 90 BPM) closing a hole, then
    three casts on open ground growing a bump, a hill and a mountain, each knocking Mog away
  - Open Pit from silence opening under Mog, who fell in (round won)
  - a Push bolt gliding over a hill to hit Mog, and stopped by a mountain
  - RB and E shoves, a jump over a hole, walking into a hole
  - collision vs. the exact height function: within 5 cm on a mountain
- Tempo setup and dash, again with simulated pad input: 4 taps at 600 ms locked 99–100 BPM
  and set the flowers dancing; taps at ~196 BPM were clamped to 160 and shown; Start began
  the match with both casters on the shared tempo; a Push started mid-bar (off the beat)
  cast; LB dashed (5.6 units in 0.73 s vs ~3.3 walking) and a second press within the
  cooldown was ignored; Tab returned to the tempo screen.
- Spell book round: 4 taps at 600 ms started the match at once at 100 BPM; the CPU's chanted
  syllables all landed within tolerance (worst 66 ms of a 120 ms window) and it cast Push,
  Open Pit and Mend Earth; shove knockback 1.6 units vs 3.3 for the Push ball; Mend Earth
  closed the hole in front and ignored one at the side; three Open Pits took a mountain down
  to flat ground and a fourth opened a hole; Shockwave, Knockout (input blocked, still
  pushable), Swap, Raise Minion (crumbled after 9.61 s = 16 beats at 100 BPM) and Hasten
  (100 → 120 over one bar, then a Push chanted by pad at 120) all worked; the squash spring
  stays stable through 1-second frames (the focus-out bug).

Not verified:

- **Playtesting:** the game is playtested on a real pad by the user. The AI does not use
  hills tactically; it only avoids steep slopes.
- **Sound:** the generated sounds were checked by pitch, level and spectrogram, not by ear.
- **Platforms:** other GPUs and operating systems.

Known limits: only the island outline is meshed at load (about a second for the 4× island);
a hole dug through a mountain's flank shows its wall tube cutting the slope, which reads as a
crater rather than a clean shaft.

## Credits

- The rhythm recognition (tempo inference, patterns, tolerances), its pattern definitions and
  the metronome sounds come from the original Synchre prototype (`~/godot/synchre`), ported
  into `scripts/rhythm/` and `assets/audio/`. The original project was not modified.

- The outline and edge-detection approach is adapted from denovodavid's t3ssel8r-style
  shader as ported to Godot by Robert-K: <https://github.com/Robert-K/godot-3d-pixel-art>
  (MIT).
- The pixel-art upscale filter is based on t3ssel8r's (<https://youtu.be/d6tp43wZqps>), via
  the same port.
- The texel-snapped camera plus sub-pixel display offset follows the same references and
  <https://www.davidhol.land/articles/3d-pixel-art-rendering/>.
- Additional reference: <https://github.com/leopeltola/Godot-3d-pixelart-demo> (MIT).
