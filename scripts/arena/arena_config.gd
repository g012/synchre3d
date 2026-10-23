class_name ArenaConfig
extends Resource
## Everything that defines the arena layout. Edit this resource (res://scenes/arena_config.tres)
## and the island, holes, collision, grass and props regenerate from it.

@export_group("Island")
## Half-size of the elliptical island on X and Z (world units).
@export var radius := Vector2(7.9, 5.7)
## Amplitude of the organic wobble along the outer edge.
@export var edge_wobble := 0.45
## Thickness of the grass slab (depth of hole walls and cliffs).
@export var thickness := 1.5
## Extra depth of the rocky underside hanging below the slab.
@export var underside_depth := 4.5
## Marching-squares resolution of the island outline (holes are cut per pixel by shaders).
@export var cell_size := 0.2
@export var seed := 11

@export_group("Layout")
## Linear scale applied to the island (2 = twice as wide and deep, 4x the area).
@export var size_scale := 2.0
## In game, generate a fresh random layout (island shape, holes, props, spawns) on every
## launch. When off (and always in the editor) the arrays below are used as authored,
## scaled by `size_scale`.
@export var randomize_layout := true
## Random layout: count ranges (min, max) of each feature, and the hole radius range.
@export var hole_count := Vector2i(11, 15)
@export var hole_radius := Vector2(0.6, 1.25)
@export var tree_count := Vector2i(8, 11)
@export var bush_count := Vector2i(6, 9)
@export var rock_count := Vector2i(9, 13)
@export var stump_count := Vector2i(3, 5)
@export var mushroom_count := Vector2i(5, 8)
@export var dancing_flower_count := Vector2i(10, 14)

@export_group("Holes")
## One entry per hole: (centre x, centre z, radius).
@export var holes: Array[Vector3] = [
	Vector3(0.2, 0.1, 1.2),
	Vector3(-4.4, -1.7, 0.9),
	Vector3(4.3, 1.8, 0.95),
	Vector3(-2.8, 3.0, 0.68),
	Vector3(3.0, -2.9, 0.7),
	Vector3(-6.4, 1.8, 0.52),
]
## Organic wobble applied to hole outlines.
@export var hole_wobble := 0.12

@export_group("Ponds")
## One entry per pond: (centre x, centre z, radius). Shallow water you can wade through; where
## a pond meets the island edge or a hole, it spills over as a waterfall.
@export var ponds: Array[Vector3] = [Vector3(1.2, 5.0, 1.7)]
## Random layouts: how many ponds (the first spills over the front edge, the next ones sit
## against a hole), and their radius.
@export var pond_count := Vector2i(1, 2)
@export var pond_radius := Vector2(1.6, 2.3)
## Depth of a pond's bed below the lawn (the water surface sits at Arena.WATER_LEVEL).
@export var pond_depth := 0.42

@export_group("Vegetation")
## Grass blades per square unit inside grass clumps.
@export var grass_density := 46.0
## Keep grass this far from any edge so dangerous edges stay readable.
@export var grass_edge_margin := 0.45
@export var flower_density := 0.9

@export_group("Props")
## Trees: x, z, scale. Keep them toward the back (negative z) so they never hide players.
@export var trees: Array[Vector3] = [
	Vector3(-5.9, -3.2, 1.0),
	Vector3(-3.1, -4.4, 0.85),
	Vector3(5.7, -3.1, 1.1),
]
## Bushes: x, z, scale.
@export var bushes: Array[Vector3] = [
	Vector3(-0.9, -5.0, 0.8),
	Vector3(1.6, -4.9, 0.7),
	Vector3(7.3, 0.4, 0.6),
]
## Rocks: x, z, scale.
@export var rocks: Array[Vector3] = [
	Vector3(2.9, -4.5, 0.8),
	Vector3(-7.2, -0.6, 0.7),
	Vector3(6.2, 2.7, 0.65),
	Vector3(-1.2, 4.8, 0.5),
	Vector3(4.2, 4.5, 0.45),
]

## Tree stumps: x, z, scale.
@export var stumps: Array[Vector3] = [Vector3(-4.6, 4.0, 0.9), Vector3(6.4, -1.6, 0.8)]
## Mushroom clusters: x, z, scale (more spawn automatically at tree roots).
@export var mushrooms: Array[Vector3] = [Vector3(-6.9, 0.6, 1.0), Vector3(2.2, 4.3, 1.2), Vector3(5.6, 3.6, 0.9)]

## Dancing flowers (they move to the match tempo): x, z, scale.
@export var dancing_flowers: Array[Vector3] = [Vector3(-5.2, -4.4, 1.0), Vector3(1.0, -5.3, 1.1),
	Vector3(6.8, -0.3, 1.0), Vector3(-7.0, 2.4, 0.9), Vector3(3.6, 4.9, 1.0)]

@export_group("Players")
@export var spawn_points: Array[Vector2] = [Vector2(-3.7, 1.1), Vector2(3.8, -0.9)]
