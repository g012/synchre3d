# Synchre — rhythmic spellcasting arena prototype

A small Godot 4 prototype of **Synchre**, a rhythm-based magical combat game, rendered as
cohesive 3D pixel art (in the spirit of t3ssel8r's work). Two little characters on a floating
grassy island fight by casting spells: you move and jump freely while chanting incantations
as rhythmic sequences of A/B/X/Y presses. A Push spell blasts your rival toward the holes,
Open Pit tears a new hole in the ground, and Mend Earth closes one, or raises the ground into
a bump, a hill and finally a mountain. A plain melee shove (RB) is always at hand too.

## Running

- Godot **4.7** (Forward+), no plugins, assets or downloads needed. The `godot_mcp` addon in
  `addons/` is only an editor automation bridge and isn't required to play.
- Open the folder in Godot and press **F5**, or run `godot --path .` from this directory.
- The game renders at 640×360 "safe area" pixels and scales up exactly at 720p, 1080p and
  1440p (2×/3×/4×). Other window sizes use an anti-aliased pixel-art upscaler, so pixels stay
  the same size.

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
| Switch 1P ⇄ 2P (new game: scores reset, tempo chosen again) | Back | Tab | |
| Restart round / confirm the tempo | Start | R | |
| Fullscreen / debug: hide outline pass | | F11 / F1 | |

Keyboard keys are bound by physical position, so they work the same on AZERTY. In 1-player
mode, either keyboard side and either pad control Pip.

Moving, jumping and chanting are fully independent. You can run, change direction, jump over
a hole or get knocked back in the middle of an incantation, and finish a spell in mid-air.
There is no "cast" button and movement is never locked while casting.

**Rules:** each round, make your opponent lose its footing over a hole or off the island's
edge. The survivor wins the round, the score updates and a new round starts after a short
delay. Holes and mounds made by spells reset each round.

**Arena:** the island is twice as wide and deep as before (4× the area) and is generated
afresh at every launch: a new outline, 11–15 holes, trees around the rim, bushes, rocks,
stumps and mushrooms, and both spawn points on safe ground (the seed is printed to the
console). The camera follows both fighters and zooms out a little when they are far apart.

## Rhythmic spellcasting

1. **Player 1 sets the tempo, once, before the match.** The game opens on `SET THE TEMPO`:
   tap any face button four times evenly (the original Synchre count-in rule: the taps and
   the wait after them within ±20%). The tempo is clamped to **80–160 BPM** (the screen
   says so if your taps were outside). Tap again to change it, then press **Start / R** to
   fight. That tempo is shared by both players and by everything that moves to the music
   (metronome, dancing flowers) for the whole match. It never resets; switching 1P/2P starts
   a new game and asks again.
2. **Chant.** Each spell is one measure (4 beats) of syllables in a set rhythm:

   | Spell | Buttons | Rhythm (beats before each note) | Effect |
   |---|---|---|---|
   | **Push** | A B X Y A | 1, ½, ½, 1, 1 (the original `basic1` pattern) | A bolt from your hands shoves the first rival it touches with the usual knockback |
   | **Open Pit** | X Y X Y | 1½, ½, 1½, ½ (the original `basic2` pattern) | Opens a real hole about 2.4 units in front of you |
   | **Mend Earth** | B Y B Y A | 1, 1, ½, ½, 1 | Closes the hole nearest to the spot in front of you. With no hole in reach it raises the ground 2.2 units ahead into a **bump**; cast it again at that mound for a **hill**, and again for a **mountain**. Rising ground throws anyone standing on it outward (harder at each level); the caster just rides it. |

   Every note must land within 20% of its own duration, measured against the match tempo.
   **A spell can start on any beat** (or between beats): there is no bar to wait for, the
   rhythm is checked relative to your own first syllable, as in the original. The right
   buttons in the wrong rhythm do not cast.
3. **Read the feedback.** Gathered magic grows at your hands with each correct syllable, and
   your character poses and bobs. The rhythm panel (bottom-left; P2 bottom-right) shows:
   - your last syllables with a timing tick for each: centred = on time, shifted left or blue
     = early, right or orange = late, red cross = out of tolerance
   - each spell's notes on a 4-beat timeline, lighting up as you play them
   - the outcome: `PUSH!`, or a fizzle with its reason (`wrong syllable`, `too early`,
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

Bumps and hills are walkable. Mountain flanks are too steep to climb, and they stop Push
bolts, which otherwise glide over gentle slopes. Holes can be opened through a hill.

The CPU opponent uses the melee shove only; it does not chant.

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
- `scripts/main.gd`: rounds, scoring, the 1P/2P toggle, per-player input and casters, and
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
   arena: `MagicBolt` for Push; `Arena.open_hole()` / `close_hole()` / `raise_ground()` /
   `grow_mound()` for Open Pit and Mend Earth, including the knockback from rising ground.
   It is the only spell code that touches gameplay.
6. **Feedback** — `scripts/spells/spell_caster.gd` drives the gathering `MagicOrb`, the hand
   pose, the syllable voices (played the instant a button is pressed), the metronome (the
   original's sounds) and UI signals; `scripts/ui/rhythm_panel.gd`
   draws the panel.
7. **Arena and physics** — holes and mounds are small dictionaries in `Arena`; nothing is
   re-meshed when they change:
   - **Rendering:** their parameters go into a 64×4 float "features" texture (one texel per
     hole or mound). The terrain shader lifts the grass top by the mounds in the vertex
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
| Island size (`size_scale`), random layout on/off and feature counts, authored layout, grass density | `scenes/arena_config.tres` (`ArenaConfig`). Edit it in the inspector and the arena rebuilds in the editor (which always shows the authored layout). |
| Bump / hill / mountain size and growth time | `MOUND_LEVELS`, `MOUND_GROW_TIME` in `scripts/arena/arena.gd` |
| Camera follow margin, max zoom-out | Exported vars on `scripts/render/pixel_camera.gd` |
| Move speed, acceleration, jump velocity, air control, push strength, knockback friction, hit-stop | Exported vars on `scripts/character/character.gd` |
| Spells (buttons, rhythm, effect, color) | `assets/spells/spellbook.tres` |
| Pit radius and placement, Mend Earth reach, mound distance and knockback | Exported vars on `scripts/spells/spell_effects.gd` |
| Sounds | `python3 tools/gen_audio.py` (numpy), volumes on `spell_caster.gd` / `spell_effects.gd` |
| Push bolt speed, range, hit radius | `scripts/spells/magic_bolt.gd` |
| Rhythm tolerance, blank length, tempo from spell openings | `scripts/rhythm/rhythm_engine.gd` (`TOLERANCE` as in the original; `blank_beats`, `tempo_from_openings`) |
| AI reaction time and edge fear | `scripts/character/ai_brain.gd` |
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

The suite has 67 checks covering:

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
- the spellbook
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

Not verified:

- **Real controller:** a physical Xbox pad. Inputs were simulated through Godot's input
  pipeline, so the stick deadzone feel, the RT threshold on real hardware and the timing
  latency of an actual pad are untested.
- **Playtesting:** human timing comfort and AI difficulty. The rhythm tolerances are the
  original's; the AI reaction time is the main difficulty knob. The AI does not use hills
  tactically; it only avoids steep slopes.
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
