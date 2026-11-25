extends Node

@export var reset_particles : GPUParticles3D
@export var reset_sfx : AudioStreamPlayer3D
@export var rest_menu : PackedScene

var player_socket
var thrall

func _process(delta: float) -> void:
	if player_socket != null && is_instance_valid(player_socket.headsUpDisplay.child_menu) == false:
		get_back_up()

func rest(thrall : Actor):
	# NOTE - A bit of a hack to get it working for now
	player_socket = MgrPlayerSocket.get_player_one()
	self.thrall = player_socket.thrall
	player_socket.cont_state = player_socket.ControlState.NONE
	#for child in psock.get_children():
	#	print(child.name)
	#print(psock)

	thrall.enque_action("emote_sit")
	var look_pos = thrall.global_position + (thrall.global_position - get_parent().global_position)
	look_pos.y = thrall.global_position.y
	thrall.look_at(look_pos)
	# Host's fire is where the host and co-op respawn, so save it and tell everybody
	if multiplayer.is_server():
		var level_path : String = MgrTransition.current_level.resource_path
		var node_path : NodePath = get_tree().current_scene.get_path_to(self) # relative to the level root
		MgrMultiplayer.share_host_rest(level_path, node_path) # us
		MgrMultiplayer.share_host_rest.rpc(level_path, node_path) # everybody else
	reset()
	player_socket.headsUpDisplay.open_submenu(rest_menu)

func reset():
	reset_particles.emitting = true
	reset_sfx.play()
	get_tree().current_scene.reset_level_now()

func get_back_up():
	#print("Get back up")
	player_socket.cont_state = player_socket.ControlState.FULL
	player_socket = null


const RESPAWN_RING_RADIUS = 2.0 # how far from the fire you get back up
const RESPAWN_RING_SLOTS = 8 # spots around the fire, slot 0 at 0 degrees, slot 1 at 45, etc

## Stands a respawning player up next to this fire, facing it. slot picks their spot in the ring
func spawn_player_at_checkpoint(thrall : Actor, slot : int):
	var fire_pos : Vector3 = get_parent().global_position
	var angle : float = (TAU / RESPAWN_RING_SLOTS) * (slot % RESPAWN_RING_SLOTS)
	var spot : Vector3 = fire_pos + Vector3(cos(angle), 0, sin(angle)) * RESPAWN_RING_RADIUS
	spot.y += 0.1 # little nudge up so we don't spawn inside the floor
	thrall.global_position = spot
	thrall.velocity = Vector3.ZERO

	# Face the fire. Actors face +Z, so look at a point on the far side, same trick as rest()
	var look_pos = thrall.global_position + (thrall.global_position - fire_pos)
	look_pos.y = thrall.global_position.y
	thrall.look_at(look_pos)