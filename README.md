# Synchre — 3D pixel-art arena prototype

A small Godot 4 prototype that renders real 3D as cohesive pixel art (in the spirit of
t3ssel8r's work): two little characters on a floating grassy island try to push each other
into holes in the ground.

## Running

- Godot **4.7** (Forward+), no plugins, assets or downloads needed. The `godot_mcp` addon in
  `addons/` is only an editor automation bridge and isn't required to play.
- Open the folder in Godot and press **F5**, or run `godot --path .` from this directory.
- The game renders at 640×360 "safe area" pixels and scales up exactly at 720p, 1080p and
  1440p (2×/3×/4×). Other window sizes use an anti-aliased pixel-art upscaler, so pixels stay
  the same size.

## Controls

| Action | 1 player (vs CPU) | 2 players |
|---|---|---|
| Move (relative to the screen) | WASD **or** arrow keys | P1: WASD · P2: arrow keys |
| Push | Space (or Enter) | P1: Space · P2: Enter |
| Switch 1P ⇄ 2P (resets scores) | Tab | Tab |
| Restart round | R | R |
| Fullscreen | F11 | F11 |
| Debug: show the image without the outline post-process | F1 | F1 |

**Rules:** each round, push your opponent until it loses its footing over a hole or off the
island's edge. The survivor wins the round, the score updates and a new round starts after a
short delay.

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
  - push wind-up and thrust
  - hit reaction (flash, squint, recoil lean)
  - falling (flailing, spinning, sinking into the dark)
  - victory hops
  - squash and stretch on spawn, landing, pushing and hits
- **Feel:** acceleration and deceleration, quick turns, a forward lunge on push, hit-stop,
  knockback with friction, camera shake, impact star, ring, sparks, running dust, a dust ring
  when someone loses footing, and push input buffering.
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
- `scripts/character/player_brain.gd` and `ai_brain.gd` drive a character through a
  three-method interface.
- `scripts/main.gd`: rounds, scoring, the 1P/2P toggle and the HUD.

## Tuning

| What | Where |
|---|---|
| Island size, hole positions and radii, prop and spawn positions, grass density | `scenes/arena_config.tres` (`ArenaConfig`). Edit it in the inspector and the arena rebuilds in the editor. |
| Move speed, acceleration, push range, cone, strength, cooldown, knockback friction, hit-stop | Exported vars on `scripts/character/character.gd` |
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
scripts/      main.gd · render/ · arena/ · character/ · fx/ · ui/
shaders/      toon_palette, terrain, grass, foliage, fx, post_outline, pixel_upscale, include/
assets/       palette/, models/ (glb), textures/ (atlases), fonts/, materials/, source/ (.blend)
tools/        palette / sprite / font generators, blender/ build scripts
```

## Verification notes

Built and tested against Godot 4.7.2 and Blender 5.2.1:

- I inspected rendered screenshots at 2× and 4× throughout development.
- Movement, pushes, knockback, obstacle collision, falling into holes and off the edge,
  elimination, round reset and scoring, the 1P/2P toggle and the AI were all exercised with
  deterministic frame stepping and injected input.
- A headless run reports no script errors.

Not verified: other GPUs and operating systems, gamepad input, and how a human player rates
the AI's difficulty. The AI's reaction time is the main knob for that.

## Credits

- The outline and edge-detection approach is adapted from denovodavid's t3ssel8r-style
  shader as ported to Godot by Robert-K: <https://github.com/Robert-K/godot-3d-pixel-art>
  (MIT).
- The pixel-art upscale filter is based on t3ssel8r's (<https://youtu.be/d6tp43wZqps>), via
  the same port.
- The texel-snapped camera plus sub-pixel display offset follows the same references and
  <https://www.davidhol.land/articles/3d-pixel-art-rendering/>.
- Additional reference: <https://github.com/leopeltola/Godot-3d-pixelart-demo> (MIT).
