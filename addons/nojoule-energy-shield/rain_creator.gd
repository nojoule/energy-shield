#class_name
extends Node3D


# --------------- Signals ----------------------
#signal
# ---------------- Enums -----------------------
#enum
# -------------- Constants ---------------------
#const
# --------------- Exports ----------------------
@export var plane_node: MeshInstance3D = null
@export var rain_amount: float = 10.0
@export var rain_speed: float = 1.0
@export var rain_interval: float = 500.0
# -------------- Variables ---------------------
var plane_size: Vector2 = Vector2.ZERO
var last_rain: float = 0.0
# --------------- Onready ----------------------
#@onready


# ------------ Process Functions -----------------
func _ready() -> void:
	plane_size.x = plane_node.mesh.size.x * plane_node.scale.x
	plane_size.y = plane_node.mesh.size.y * plane_node.scale.y


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	var current = Time.get_ticks_msec()
	if current - last_rain >= rain_interval * (randf() + 0.1):
		last_rain = current
		var rain: int = randi_range(int(rain_amount * 0.2), int(rain_amount * 0.8))
		for drop in rain:
			var offset: Vector3 = Vector3.ZERO
			offset.x = randf_range(-plane_size.x, plane_size.x)
			offset.y = randf_range(-plane_size.y, plane_size.y)
			var drop_pos: Vector3 = plane_node.global_position + offset
			plane_node.impact(drop_pos)


# ------------ Private Functions -----------------
#func _example() -> void:
	#pass


# ------------ Public Functions -----------------
#func example() -> void:
	#pass
