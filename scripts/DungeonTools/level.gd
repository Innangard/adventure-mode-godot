class_name Level
extends Node3D

## Top level of the gameplay level
## Serializes things

## parent node of all local dungeon obejcts
@export var dungeon_objects: Node3D

@export_category("Spawn room parameters")
## Determines whether to treat this room as the root.
@export var is_spawn_room: bool = false
## Array of all dungeon room scenes, excluding this one. (only needed for spawn room)
@export var dungeon_rooms: Array[PackedScene]

var spawned_players : Array[Actor] = []
var local_player : Actor

## Music that will play when the level is loading. 
## TODO - Replace with FAM and moods/themes
@export var level_music : AudioStream 

signal level_started
signal level_reset

func level_start():
	MgrTransition.request_song(level_music)
	#print("level start...")
	#var entering_player = MgrPlayerSocket.spawn_player()
	#entering_player.global_position = spawn_point.global_position

	## Spawn other connected players
	var our_id = multiplayer.get_unique_id()
	for conn in MgrMultiplayer.connection_level:
		if conn == our_id or conn == 0 or MgrMultiplayer.connection_level[conn] != MgrTransition.current_level.resource_path:
			continue
		var con_player : Actor = MgrPlayerSocket.spawn_player()
		con_player.name = "PLAYER|" + str(conn)
		con_player.set_multiplayer_authority(conn)
		con_player.get_node("actor_nametag").set_nametag_visibility(ActorNametag.VisState.ALWAYS)
		add_child(con_player)
		spawned_players.append(con_player)
		var player_type = MgrMultiplayer.peer_type[conn]
		if player_type == "main":
			con_player.add_to_group("allies")
		elif player_type == "ally":
			con_player.dup.set_material_overlay(MgrPlayerSocket.ally_material)
			con_player.add_to_group("allies")
		elif player_type == "enemy":
			con_player.dup.set_material_overlay(MgrPlayerSocket.enemy_material)
			con_player.add_to_group("enemies")
			con_player.get_node("actor_nametag").set_nametag_visibility(ActorNametag.VisState.CHANGE)
		

	## TODO make a player spawning function or something
	var new_player : Actor = MgrPlayerSocket.spawn_player()
	add_child(new_player)
	new_player.name = "PLAYER|" + str(our_id) # NOTE Hardcoded name where part of name is used as data
	#new_player.transform = MgrPlayerSocket.player_last_saved_pos
	MgrPlayerSocket.get_player_one().ganty_thing.thrall = new_player
	MgrPlayerSocket.get_player_one().ganty_thing.cam.target_current = new_player
	MgrPlayerSocket.get_player_one().ganty_thing.freeze = false
	MgrPlayerSocket.get_player_one().ganty_thing.cam.freeze = false
	MgrPlayerSocket.get_player_one().enthrall_new_thrall(new_player)
	MgrPlayerSocket.get_player_one().cont_state = MgrPlayerSocket.get_player_one().ControlState.FULL
	new_player.set_multiplayer_authority(our_id)
	new_player.add_to_group("local_player")
	new_player.get_node("actor_nametag").set_nametag_visibility(ActorNametag.VisState.NEVER)
	spawned_players.append(new_player)
	local_player = new_player
	if MgrPlayerSocket.player_outfit:
		var dup : DresserUpper = local_player.find_child("DresserUpper")
		dup.outfit_load(MgrPlayerSocket.player_outfit)

	# find spawn point:
	if MgrMultiplayer.respawn_pending:
		# We died and loaded this level just to get back to the host's bonfire
		MgrMultiplayer.respawn_pending = false
		place_player_for_respawn(new_player)
	elif MgrTransition.target_spawn_point != "":
		print(MgrTransition.target_spawn_point)
		## FIXME - Hack for indader spawns 
		if MgrPlayerSocket.player_type == "enemy":
			MgrTransition.target_spawn_point = "spawn_3"
		var spawn = find_child(MgrTransition.target_spawn_point)
		new_player.global_transform = spawn.global_transform
		var psock = MgrPlayerSocket.get_player_one()
		#psock.ganty_thing.freeze = true
		psock.ganty_thing.global_position = new_player.global_position + (new_player.global_basis.z * 10) + Vector3(0,5,0)
		psock.ganty_thing.look_at(new_player.global_position)
		#MgrTransition.target_spawn_point = ""
	else:
		new_player.global_transform = MgrPlayerSocket.player_last_saved_pos
	
	## ---------- Loading the dungeon state ----------
	## If we just loaded the dungeon for the first time and we're the host, populate the object data.
	#if multiplayer.is_server() and is_spawn_room and MgrDungeonState.object_data.is_empty():
		#print("DATA IS EMPTY, NEED TO FILL")
		
	# link up the level to the manager so we can get live network state changes
	#MgrDungeonState.connect("network_state_changed", Callable(self.on_network_state_changed))
	#
	# retrieve the dungeon object data for this room
	# NOTE: key is now the scene path, rather than the name of the root note. easier to do remote state changes this way
	var data = MgrDungeonState.load_objects(self.scene_file_path)
	new_player.multiplayer_spawn()

	# Loads saved time_of_day from dungeon state if it exists.
	if data.has("time_of_day"):
		#print("LOADED time_of_day =", data["time_of_day"])
		$DayNightCycle.set_time(data["time_of_day"])
	else:
		#print("NO time_of_day FOUND")
		pass

	# Initialize all the dungeon objects, and hook up their state update signals
	if dungeon_objects:
		for object in dungeon_objects.get_children():
			if !(object is DungeonObject):
				push_warning(object.name + " is not a dungeon object.")
				continue
			# if we have a data entry, load it up
			if data != null && data.has(object.name):
				object.deserialize(data[object.name])
			object.connect("state_update", self._on_object_update)
	print("Level has finished starting")
	level_started.emit() # does not work for some reason
	await get_tree().create_timer(1).timeout
	MgrTransition.msg_big(name, 3)

## Puts our respawning local player in the right spot for their type and moves the camera.
## Host and co-op: host's bonfire, or the spawn point we came in through if the host never rested.
## Invaders: a multiplayer spawn point, or the spawn point we came in through if there isn't one.
func place_player_for_respawn(player : Actor):
	var slot : int = get_respawn_slot()
	var spawn = null
	if MgrTransition.target_spawn_point != "":
		spawn = find_child(MgrTransition.target_spawn_point) # the spawn point we came in through

	if MgrPlayerSocket.player_type == "enemy":
		var mp_spawn = find_multiplayer_spawn_point()
		if mp_spawn != null:
			spawn = mp_spawn
	else:
		var fire = null
		if MgrMultiplayer.host_rest_level_path == MgrTransition.current_level.resource_path:
			fire = get_node_or_null(MgrMultiplayer.host_rest_node_path) # path is relative to the level root, which is us
		if fire != null:
			fire.spawn_player_at_checkpoint(player, slot)
			move_camera_behind(player)
			return

	if spawn != null:
		# Line people up sideways from the spawn point so nobody's stacked on each other
		player.global_transform = spawn.global_transform
		player.global_position += spawn.global_basis.x * (slot * 1.5)
	else:
		push_warning("Couldn't find a respawn spot, using last saved position")
		player.global_transform = MgrPlayerSocket.player_last_saved_pos
	player.velocity = Vector3.ZERO
	move_camera_behind(player)


## Our spot in line when respawning, from our id's place in the sorted list of everybody connected.
## Just keeps people from standing inside each other
func get_respawn_slot() -> int:
	var ids : Array[int] = [multiplayer.get_unique_id()]
	ids.append_array(multiplayer.get_peers())
	ids.sort()
	return ids.find(multiplayer.get_unique_id())


## First spawn point in this level marked as a multiplayer spawn, or null if there isn't one
func find_multiplayer_spawn_point():
	for node in find_children("*"):
		if node is Spawnpoint3D and node.subtype == Spawnpoint3D.Subtype.MULTIPLAYER:
			return node
	return null


## Same camera swing as the spawn point code in level_start
func move_camera_behind(player : Actor):
	var psock = MgrPlayerSocket.get_player_one()
	psock.ganty_thing.global_position = player.global_position + (player.global_basis.z * 10) + Vector3(0,5,0)
	psock.ganty_thing.look_at(player.global_position)

## Rest at fire, respawn enemies, pass time, etc.
func reset_level_now():
	print("Whooosh, reset sound! And respawn enemies n shit.")
	level_reset.emit()
	MgrPlayerSocket.get_player_one().thrall.character.reset()
	pass

# All dungeon object connect their state_update signal to this function
# WARNING: this function is mega ugly bear with me
func _on_object_update(node: DungeonObject, data: Dictionary) -> void:
	# NOTE: this function is called whether it's the local or remote player, meaning if the players
	#	    are in the same level both server_update and client_update will be called, resulting in a double client update
	if multiplayer.is_server():
		MgrDungeonState.server_update_state(self.scene_file_path, node.name, data) # server calling itself
	else:
		MgrDungeonState.client_update_state.rpc_id(1, self.scene_file_path, node.name, data) # client calling server
		
	# if this dungeon object changes the state of some other object in another scene, apply those
	for conn: ObjectConnection in node.remote_connections:
		if multiplayer.is_server():
			MgrDungeonState.server_update_state(
				conn.get_scene_name(), conn.object_name, conn.affected_properties
			)
		else:
			MgrDungeonState.client_update_state.rpc_id(
				1, conn.get_scene_name(), conn.object_name, conn.affected_properties
			)
			
#func on_network_state_changed(scene_name: String, object_name: String, state: Dictionary):
	## If this state change isn't for the currently loaded scene, we don't need to deserialize it.
	#if self.scene_file_path != scene_name:
		#return
		#
	#var node: DungeonObject = dungeon_objects.find_child(object_name)
	#print("NETWORK >>> ", object_name, state)
	#node.deserialize(state)

func save_objects():
	#print("SAVING time_of_day =", $DayNightCycle.time_of_day)
	# Pack the current time_of_day into the save data so it persists between scenes.
	var extra_data = {}
	if is_instance_valid($DayNightCycle):
		extra_data["time_of_day"] = $DayNightCycle.time_of_day

	var data = [] if dungeon_objects == null else dungeon_objects.get_children()
	MgrDungeonState.save_objects(self.scene_file_path, data, extra_data)

func remove_player(conn_id : int):
	print(spawned_players)
	for guy in spawned_players:
		if str(conn_id) in guy.name:
			guy.multiplayer_despawn()
			spawned_players.remove_at(spawned_players.find(guy))
			return