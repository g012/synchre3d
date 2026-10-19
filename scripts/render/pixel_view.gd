class_name PixelView
extends Node
## Renders the 3D world into a fixed-height low-res SubViewport and upscales it to the window.
##
## The SubViewport is 2 pixels larger than what is displayed (1 px margin per side) so the
## image can be shifted by the camera's sub-pixel texel error without exposing the border.
## At 720p/1080p/1440p the scale is an exact integer; other window sizes use the
## t3ssel8r-style anti-aliased upscale shader, which keeps every pixel the same size.

## Minimum low-res area that is always visible ("safe area"); the image grows on the
## other axis to fill the window. 640x360 scales by exactly 2/3/4 at 720p/1080p/1440p.
@export var safe_size := Vector2i(640, 360)
## Smoothly offset the image by the camera's sub-pixel error (smooth shake/drift).
@export var subpixel_camera := true

@onready var viewport: SubViewport = $GameViewport
@onready var display: Sprite2D = $Display

var pixel_scale := 1.0


func _ready() -> void:
	display.texture = viewport.get_texture()
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	get_tree().root.size_changed.connect(_resize)
	_resize()


func _resize() -> void:
	var win := Vector2(get_tree().root.size)
	if win.y <= 0.0:
		return
	pixel_scale = minf(win.x / safe_size.x, win.y / safe_size.y)
	var internal := Vector2i((win / pixel_scale).ceil())
	viewport.size = internal + Vector2i(2, 2)
	display.scale = Vector2.ONE * pixel_scale


func _process(_delta: float) -> void:
	var offset := Vector2.ZERO
	var cam := viewport.get_camera_3d() as PixelCamera
	if subpixel_camera and cam:
		# Camera moved right by e texels -> image content must move left by e.
		offset = Vector2(-cam.texel_error.x, cam.texel_error.y) * pixel_scale
	display.position = Vector2(-pixel_scale, -pixel_scale) + offset
