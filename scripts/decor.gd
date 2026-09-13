class_name Decor
extends Node2D
## One placed item. Scenery, and possibly shelter.

## One material for every plant. Shared deliberately: the shader takes each plant's
## phase from its own world position, so a single material still gives every plant its
## own cadence while letting them batch into one draw call.
const SWAY: Shader = preload("res://shaders/sway.gdshader")
static var _sway_material: ShaderMaterial

var kind: DecorKind

@onready var sprite: Sprite2D = $Sprite2D

func configure(decor_kind: DecorKind) -> void:
	kind = decor_kind

func _ready() -> void:
	if kind == null:
		push_error("Decor added without a kind; call configure() first.")
		return
	sprite.texture = kind.texture
	var texture_size := sprite.texture.get_size()
	if texture_size.y > 0.0:
		var scale_factor := kind.size / texture_size.y
		sprite.scale = Vector2(scale_factor, scale_factor)
	# Rooted at its base rather than its middle, so placing one puts its foot where the
	# player tapped instead of burying half of it.
	sprite.offset = Vector2(0.0, -texture_size.y * 0.5)

	if _sway_material == null:
		_sway_material = ShaderMaterial.new()
		_sway_material.shader = SWAY
	sprite.material = _sway_material

func shelters() -> bool:
	return kind != null and kind.shelter_radius > 0.0
