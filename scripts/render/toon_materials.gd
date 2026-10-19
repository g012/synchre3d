class_name ToonMaterials
extends RefCounted
## Shared materials and helpers to apply the toon palette shading to imported Blender models.

const SOLID := preload("res://assets/materials/toon_solid.tres")
const CHARACTER := preload("res://assets/materials/toon_character.tres")
const FOLIAGE_CORE := preload("res://assets/materials/foliage_core.tres")
const FOLIAGE_LEAVES := preload("res://assets/materials/foliage_leaves.tres")


## Overrides the material of every MeshInstance3D below `root`.
static func apply(root: Node, material: Material) -> void:
	for mi in mesh_instances(root):
		mi.material_override = material


static func mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(mesh_instances(c))
	return out
