# Synchre — rhythmic spellcasting arena prototype

A small Godot 4 prototype of **Synchre**, a rhythm-based magical combat game, rendered as
cohesive 3D pixel art (in the spirit of t3ssel8r's work). Two little characters on a floating
grassy island fight by casting spells: you move and jump freely while chanting incantations
as rhythmic sequences of A/B/X/Y presses. A Push spell blasts your rival toward the holes,
Open Pit tears a new hole in the ground, and Mend Earth closes one.

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
| Switch 1P ⇄ 2P (resets scores) | Back | Tab | |
| Restart round | Start | R | |
| Fullscreen / debug: hide outline pass | | F11 / F1 | |

Keyboard keys are bound by physical position, so they work the same on AZERTY. In 1-player
mode, either keyboard side and either pad control Pip.

Moving, jumping and chanting are fully independent. You can run, change direction, jump over
a hole or get knocked back in the middle of an incantation, and finish a spell in mid-air.
There is no "cast" button and movement is never locked while casting.

**Rules:** each round, make your opponent lose its footing over a hole or off the island's
edge. The survivor wins the round, the score updates and a new round starts after a short
delay. Holes opened or closed by spells reset each round.

## Rhythmic spellcasting

1. **Set your tempo.** Tap any four face buttons evenly. Once four taps and the wait after
   them are even (within ±20%), your tempo locks and the metronome starts clicking. The
   panel shows `TAP 4 BEATS` with a count, then your BPM and a 4-beat light. Any tempo works.
   The tempo stays as long as you keep playing; 6 silent beats reset it. These are the rules
   of the original Synchre prototype.
2. **Chant.** Each spell is one measure (4 beats) of syllables in a set rhythm:

   | Spell | Buttons | Rhythm (beats before each note) | Effect |
   |---|---|---|---|
   | **Push** | A B X Y A | 1, ½, ½, 1, 1 (the original `basic1` pattern) | A bolt from your hands shoves the first rival it touches with the usual knockback |
   | **Open Pit** | X Y X Y | 1½, ½, 1½, ½ (the original `basic2` pattern) | Opens a real hole about 2.4 units in front of you |
   | **Mend Earth** | B Y B Y A | 1, 1, ½, ½, 1 | Closes the hole nearest to the spot in front of you |

   Every note must land within 20% of its own duration. The whole incantation may drift a
   little as a block (the original's sliding measure), but the right buttons in the wrong
   rhythm do not cast.
3. **Read the feedback.** Gathered magic grows at your hands with each correct syllable, and
   your character poses and bobs. The rhythm panel (bottom-left; P2 bottom-right) shows:
   - your last syllables with a timing tick for each: centred = on time, shifted left or blue
     = early, right or orange = late, red cross = out of tolerance
   - each spell's notes on a 4-beat timeline, lighting up as you play them
   - the outcome: `PUSH!`, or a fizzle with its reason (`wrong syllable`, `too early`,
     `too late`, `tempo lost`). A fizzle dissipates the magic in grey puffs.

The CPU opponent keeps its original melee push; it does not chant.

## What's in the box

- **Arena:** a procedural floating island with six real holes. The holes are gaps in both the
  mesh and the collision. Hole walls, cliffs and the closed rocky underside share one
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

1. **Fixed orthographic camera, texel-snapped** (`scripts/render/pixel_camera.gd`). The camera
   is pitched 40°. Its position is snapped to whole texels in its own view plane, so static
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

Performance: roughly 0.35 ms GPU per frame on an RX 9060 XT, and about 1,800 FPS uncapped
(vsync is on by default).

## Gameplay architecture

- `scripts/arena/arena.gd` (`@tool`): the island is a signed distance field — an organic
  ellipse minus a set of holes. Marching squares turns it into the grass top with real gaps.
  Hole walls get jittered earth rows; the outside (cliff plus rocky underside) is one watertight, smooth-shaded shell swept from the exact grass outline down to a single apex. The code then builds separate *floor* and
  *wall* collision bodies, and an SDF texture shared with the shaders. `ground_sdf()` is also
  the AI's map.
- `scripts/character/character.gd`: a `CharacterBody3D` with a small state machine (spawning,
  active, pushing, hitstun, falling, out, victory). Support is a ray against the **floor
  collision**. When the character's centre is over a hole it stops colliding with the floor
  and drops, and only the hole walls constrain it. Pushes are resolved deterministically: a
  range check plus a cone check, then a fixed impulse, so they feel skill-based.
- `scripts/character/player_brain.gd` and `ai_brain.gd` drive a character's movement, jump
  and (AI only) melee push.
- `scripts/main.gd`: rounds, scoring, the 1P/2P toggle, per-player input and casters, and
  the HUD.

### Spellcasting pipeline

Each stage only talks to the next one through plain data or signals:

1. **Input capture** — `scripts/input/player_input.gd`: each face-button press is emitted
   from `_input` as a timestamped event (`Time.get_ticks_usec`, as in the original). Movement
   and the RT jump are polled separately during physics.
2. **Tempo and rhythm recognition** — `scripts/rhythm/rhythm_engine.gd`, a port of the
   original `RhythmInput` with the same constants and rules (tempo inference, 6-beat blank,
   20% per-note tolerance, measure-anchored matching, consumed taps). Time is injected, and the
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
   arena: `MagicBolt` for Push; `Arena.open_hole()` / `close_hole()` for Open Pit and Mend
   Earth. It is the only spell code that touches gameplay.
6. **Feedback** — `scripts/spells/spell_caster.gd` drives the gathering `MagicOrb`, the hand
   pose, the metronome (the original's sounds) and UI signals; `scripts/ui/rhythm_panel.gd`
   draws the panel.
7. **Arena and physics** — holes are runtime state in `Arena`. The grass top is split into
   chunks of about 2×2 units, each with its own mesh, hole walls and floor/wall collision. An
   opening or closing hole rebuilds only the chunks whose geometry changes, about 20 times a
   second, plus the SDF texels that the grass, terrain and AI read.

For multiplayer later: syllables are `(player, button, time)` events and recognition is
deterministic in their timestamps, so the same events replayed anywhere give the same spells.
Spell effects are separate from recognition and could be resolved authoritatively.

## Tuning

| What | Where |
|---|---|
| Island size, hole positions and radii, prop and spawn positions, grass density | `scenes/arena_config.tres` (`ArenaConfig`). Edit it in the inspector and the arena rebuilds in the editor. |
| Move speed, acceleration, jump velocity, air control, push strength, knockback friction, hit-stop | Exported vars on `scripts/character/character.gd` |
| Spells (buttons, rhythm, effect, color) | `assets/spells/spellbook.tres` |
| Pit radius and placement, Mend Earth reach | Exported vars on `scripts/spells/spell_effects.gd` |
| Push bolt speed, range, hit radius | `scripts/spells/magic_bolt.gd` |
| Rhythm tolerance, blank length | Constants in `scripts/rhythm/rhythm_engine.gd` (kept identical to the original) |
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
  leaf and FX atlases) and `tools/gen_font.py`.
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

The suite has 54 checks covering:

- tempo lock time and BPM
- tempo tolerance boundaries
- the 6-beat blank and tempo changes
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

Not verified:

- **Real controller:** a physical Xbox pad. Inputs were simulated through Godot's input
  pipeline, so the stick deadzone feel, the RT threshold on real hardware and the timing
  latency of an actual pad are untested.
- **Playtesting:** human timing comfort and AI difficulty. The rhythm tolerances are the
  original's; the AI reaction time is the main difficulty knob.
- **Platforms:** other GPUs and operating systems.

Known cost: an animating hole rebuilds a few terrain chunks in GDScript, about 5–9 ms per
update at 20 updates/s. That is fine at 60 FPS for one hole at a time; moving the chunk build
to native code would remove it.

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
