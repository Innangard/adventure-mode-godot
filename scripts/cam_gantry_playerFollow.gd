extends Node3D

var follow_height_offset = 1.0
var cam_follow_dist = 2.5
var cam_current_dist = 2.5 # distance camera actually is, shrinks near walls
@export var thrall : Actor
@export var cam : Camera3D

@export var freeze = false

var velocity = Vector3.ZERO

var look_rotation_vel = Vector2.ZERO
var camLookAccell = 3.14
var camTimer = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	MgrPlayerSocket.get_player_one().ganty_thing = self
	#this should keep mouse within boarders, need to capture escape button so user can interact with menu (to leave) 
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


#also changed _physics_process to process here for jitter fix
func _process(delta: float) -> void:
	if thrall == null:
		return
	var desired_pos = thrall.global_position
	desired_pos.y += follow_height_offset
	velocity = (desired_pos - global_position) * (desired_pos - global_position).length_squared()
	var wanted_dist = ray_cam_pos()
	if wanted_dist < cam_current_dist:
		cam_current_dist = wanted_dist # snap in so we never see through the wall
	else:
		cam_current_dist = move_toward(cam_current_dist, wanted_dist, 4.0 * delta) # ease back out at 4 m/s
	cam.global_position = global_position + (global_basis.z * cam_current_dist)
	if freeze:
		return
	if velocity.length() > 10:
		velocity = velocity.normalized() * 10
	global_position += velocity * delta * 2#* (desired_pos - global_position).length()
	player_look(delta)


func ray_cam_pos():
	# Ray from the pivot back toward where the camera follow distance
	var space_state = thrall.get_world_3d().direct_space_state
	var origin = global_position
	var end = origin + (global_basis.z * cam_follow_dist)
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 1 # layer 1 is level geometry and actors i think

	# Ignore every actor so a skeleton walking behind you shouldn't push the camera in
	var ignore_list : Array[RID] = []
	for actor in Actor.ALL_EVER_MADE:
		if is_instance_valid(actor):
			ignore_list.append(actor.get_rid())
	query.exclude = ignore_list

	var col_result = space_state.intersect_ray(query)
	if "collider" in col_result.keys():
		var _dis = global_position.distance_to(col_result["position"])
		return max(_dis - 0.2, 0.1) # sit 0.2 m in front of the wall, never behind the pivot
	return cam_follow_dist


func player_look(delta):
	var disLook =  Input.get_vector("p1_look_left", "p1_look_right", "p1_look_dn", "p1_look_up")
	look_rotation_vel = disLook * delta * camLookAccell
	var default_angle = -20
	if cam.target_curr == Vector3.ZERO: # NOTE - No target
		rotate(global_basis.x.normalized(), look_rotation_vel.y)
		rotate_y(-look_rotation_vel.x)
		global_rotation_degrees.x = clamp(global_rotation_degrees.x, -60,20)
	else:
		var original_rot_x = global_rotation_degrees.x
		look_at(cam.target_curr)
		global_rotation_degrees.x = original_rot_x
		#global_rotation_degrees.y = global_rotation_degrees.y #rotate_toward(original_rot_y, global_rotation_degrees.y, 50 * delta)
		default_angle = -35
	global_rotation_degrees.z = 0
	#recentering here, add some timer so the rebound isn't immediate 
	if disLook.length() != 0: #some kind of input 
		camTimer = 12.0
	else:
		#subtraction should be proportional to framerate
		#higher refresh rate would decrement the same as lower
		camTimer -= delta
	if camTimer <= 0:
		global_rotation_degrees.x += (default_angle-global_rotation_degrees.x) * 0.9 * delta
	


func _input(event):
	if event is InputEventMouseMotion:
		#mouse movement will always reset timer
		camTimer = 12.0
		var disLook =  event.relative * 0.01
		look_rotation_vel = disLook * 0.1 * camLookAccell
		var default_angle = -20
		if cam.target_curr == Vector3.ZERO: # NOTE - No target
			rotate(global_basis.x.normalized(), -look_rotation_vel.y) # negative y because screen coords pos y is down
			rotate_y(-look_rotation_vel.x)
			global_rotation_degrees.x = clamp(global_rotation_degrees.x, -60,20)
		else:
			var original_rot_x = global_rotation_degrees.x
			look_at(cam.target_curr)
			global_rotation_degrees.x = original_rot_x
			#global_rotation_degrees.y = global_rotation_degrees.y #rotate_toward(original_rot_y, global_rotation_degrees.y, 50 * delta)
			default_angle = -35
		global_rotation_degrees.z = 0
		#global_rotation_degrees.x += (default_angle-global_rotation_degrees.x) * 0.9 * 0.1
	#KEY_ESCAPE cant persist because user moves mouse in pause menu
	#need a global to block MOUSE_MODE_CAPTURED
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	#for some reason this is true regardless: