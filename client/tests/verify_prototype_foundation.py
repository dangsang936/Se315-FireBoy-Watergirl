from __future__ import annotations

import re
import sys
from pathlib import Path


CLIENT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = CLIENT_ROOT.parent


REQUIRED_FILES = [
	"project.godot",
	"scenes/bootstrap/game.tscn",
	"scenes/bootstrap/game_real.tscn",
	"scenes/players/fireboy.tscn",
	"scenes/players/watergirl.tscn",
	"scenes/levels/prototype_level.tscn",
	"scenes/levels/real_level_blank.tscn",
	"scenes/ui/level_complete_overlay.tscn",
	"scenes/ui/hud.tscn",
	"scenes/ui/host_waiting_room.tscn",
	"scenes/menus/pause_menu.tscn",
	"scripts/core/game_manager/game_manager.gd",
	"scripts/player/movement/player.gd",
	"scripts/player/state_machine/player_state.gd",
	"scripts/player/state_machine/player_state_machine.gd",
	"scripts/player/input/player_input_reader.gd",
	"scripts/player/motor/player_motor.gd",
	"scripts/player/motor/edge_correction.gd",
	"scripts/player/animation/player_animation_controller.gd",
	"scripts/player/interaction/push_interactor.gd",
	"scripts/player/interaction/ladder_detector.gd",
	"scripts/player/states/idle_state.gd",
	"scripts/player/states/run_state.gd",
	"scripts/player/states/airborne_state.gd",
	"scripts/player/states/push_state.gd",
	"scripts/player/states/climb_state.gd",
	"scripts/player/states/disabled_state.gd",
	"scripts/ui/hud/hud.gd",
	"scripts/ui/level_complete_overlay.gd",
	"scripts/ui/host_waiting_room.gd",
	"scripts/ui/menus/pause_menu.gd",
	"scenes/gameplay/objects/ladder.tscn",
	"scenes/levels/ladder_test_level.tscn",
	"docs/level_workflow.md",
	"docs/player_state_machine.md",
	"tests/player_state_machine_probe.gd",
	"tests/button_ladder_interactions_probe.gd",
	"tests/precision_player_movement_probe.gd",
	"tests/client_prediction_contract_probe.gd",
	"tests/multiplayer_hazard_sync_probe.gd",
	"tests/multiplayer_puzzle_sync_probe.gd",
]

REQUIRED_REPO_FILES = [
	"shared/scripts/multiplayer/movement/player_movement_config.gd",
	"shared/scripts/multiplayer/movement/player_movement_state.gd",
	"shared/scripts/multiplayer/movement/player_movement_simulator.gd",
	"client/scripts/multiplayer/prediction/client_prediction_controller.gd",
	"shared/scripts/gameplay/levels/prototype_level.gd",
	"shared/scripts/gameplay/hazards/hazard_zone.gd",
	"shared/scripts/gameplay/doors/exit_door.gd",
	"shared/scripts/gameplay/doors/goal_door.gd",
	"shared/scripts/gameplay/collectibles/collectible_gem.gd",
	"shared/scripts/gameplay/collectibles/gem_manager.gd",
	"shared/scripts/gameplay/objects/push_block.gd",
	"shared/scripts/gameplay/objects/ladder.gd",
	"shared/scenes/gameplay/collectibles/collectible_gem.tscn",
	"shared/scenes/gameplay/objects/push_block.tscn",
	"shared/scenes/gameplay/doors/goal_door.tscn",
]

REQUIRED_ACTIONS = ["move_left", "move_right", "jump", "pause", "restart"]

REQUIRED_RULE_SNIPPETS = [
	"Focus gameplay only",
	"no local co-op mode",
	"no co-op-adjacent work",
]

BANNED_INPUT_ACTIONS = [
	"move_left_p2",
	"move_right_p2",
	"jump_p2",
	"player_2",
	"watergirl_",
	"split_screen",
	"local_coop",
]

PLAYER_COMPONENT_FILES = [
	"scripts/player/state_machine/player_state.gd",
	"scripts/player/state_machine/player_state_machine.gd",
	"scripts/player/input/player_input_reader.gd",
	"scripts/player/motor/player_motor.gd",
	"scripts/player/motor/edge_correction.gd",
	"scripts/player/animation/player_animation_controller.gd",
	"scripts/player/interaction/push_interactor.gd",
	"scripts/player/interaction/ladder_detector.gd",
]

PLAYER_STATE_FILES = [
	"scripts/player/states/idle_state.gd",
	"scripts/player/states/run_state.gd",
	"scripts/player/states/airborne_state.gd",
	"scripts/player/states/push_state.gd",
	"scripts/player/states/climb_state.gd",
	"scripts/player/states/disabled_state.gd",
]

REQUIRED_2D_LAYER_NAMES = {
	1: "World",
	2: "Player",
	3: "PushBlock",
	4: "Ladder",
	5: "Hazard",
	6: "Collectible",
	7: "Exit",
	8: "PressureButton",
}

COLLISION_SCENE_SNIPPETS = {
	"scenes/players/fireboy.tscn": ["collision_layer = 2", "collision_mask = 5", "collision_mask = 8"],
	"scenes/players/watergirl.tscn": ["collision_layer = 2", "collision_mask = 5", "collision_mask = 8"],
	"shared/scenes/gameplay/objects/push_block.tscn": ["collision_layer = 4", "collision_mask = 3", "collision_mask = 2"],
	"scenes/gameplay/objects/ladder.tscn": ["collision_layer = 8", "collision_mask = 0"],
	"scenes/gameplay/objects/pressure_button.tscn": ["collision_layer = 128", "collision_mask = 2"],
	"scenes/gameplay/objects/bridge_platform.tscn": ["collision_layer = 1", "collision_mask = 6"],
	"shared/scenes/gameplay/collectibles/collectible_gem.tscn": ["collision_layer = 32", "collision_mask = 2"],
	"scenes/gameplay/collectibles/water_gem.tscn": ["collision_layer = 32", "collision_mask = 2"],
	"scenes/levels/prototype_level.tscn": ["collision_layer = 1", "collision_mask = 6", "collision_layer = 16", "collision_layer = 64"],
	"scenes/levels/ladder_test_level.tscn": ["collision_layer = 1", "collision_mask = 6", "collision_layer = 16", "collision_layer = 64"],
	"scenes/levels/real_level_blank.tscn": ["collision_layer = 16", "collision_layer = 64"],
}

COLLISION_SCRIPT_SNIPPETS = {
	"scripts/player/movement/player.gd": ["PLAYER_COLLISION_LAYER: int = 2", "PLAYER_COLLISION_MASK: int = 5"],
	"scripts/player/interaction/ladder_detector.gd": ["LADDER_DETECTOR_LAYER: int = 0", "LADDER_DETECTOR_MASK: int = 8"],
	"shared/scripts/gameplay/objects/ladder.gd": ["LADDER_COLLISION_LAYER: int = 8", "LADDER_COLLISION_MASK: int = 0"],
	"shared/scripts/gameplay/objects/pressure_button.gd": ["PRESSURE_BUTTON_COLLISION_LAYER: int = 128", "PRESSURE_BUTTON_COLLISION_MASK: int = 2"],
	"shared/scripts/gameplay/objects/push_block.gd": ["PUSH_BLOCK_COLLISION_LAYER: int = 4", "PUSH_BLOCK_COLLISION_MASK: int = 3", "PUSH_DETECTOR_COLLISION_MASK: int = 2"],
	"shared/scripts/gameplay/objects/bridge_platform.gd": ["WORLD_COLLISION_LAYER: int = 1", "WORLD_COLLISION_MASK: int = 6"],
	"shared/scripts/gameplay/collectibles/collectible_gem.gd": ["GEM_COLLISION_LAYER: int = 32", "GEM_COLLISION_MASK: int = 2"],
	"shared/scripts/gameplay/hazards/hazard_zone.gd": ["HAZARD_COLLISION_LAYER: int = 16", "HAZARD_COLLISION_MASK: int = 2"],
	"shared/scripts/gameplay/doors/exit_door.gd": ["EXIT_COLLISION_LAYER: int = 64", "EXIT_COLLISION_MASK: int = 2"],
}


def read(path: Path) -> str:
	return path.read_text(encoding="utf-8")


def require(condition: bool, message: str, failures: list[str]) -> None:
	if not condition:
		failures.append(message)


def check_required_files(failures: list[str]) -> None:
	for relative_path in REQUIRED_FILES:
		require((CLIENT_ROOT / relative_path).exists(), f"Missing {relative_path}", failures)
	for relative_path in REQUIRED_REPO_FILES:
		require((REPO_ROOT / relative_path).exists(), f"Missing {relative_path}", failures)


def check_rules(failures: list[str]) -> None:
	rules_path = REPO_ROOT / "docs" / "GDD" / "project_rules.md"
	require(rules_path.exists(), "Missing docs/GDD/project_rules.md", failures)
	if not rules_path.exists():
		return
	rules_text = read(rules_path)
	for snippet in REQUIRED_RULE_SNIPPETS:
		require(snippet in rules_text, f"Rule missing snippet: {snippet}", failures)


def check_project_settings(failures: list[str]) -> None:
	project_text = read(CLIENT_ROOT / "project.godot")
	require('run/main_scene="res://scenes/menus/main_menu.tscn"' in project_text, "Wrong main scene", failures)
	for layer_index, layer_name in REQUIRED_2D_LAYER_NAMES.items():
		require(f'2d_physics/layer_{layer_index}="{layer_name}"' in project_text, f"Missing 2D physics layer {layer_index}: {layer_name}", failures)
	for action in REQUIRED_ACTIONS:
		require(f'{action}=' in project_text, f"Missing input action {action}", failures)
	jump_block = re.search(r"jump=\{\n(?P<body>.*?)\n\}", project_text, re.S)
	require(jump_block is not None, "Missing jump input block", failures)
	if jump_block:
		require('"keycode":87' in jump_block.group("body"), "Jump action must use W", failures)
		require('"keycode":32' not in jump_block.group("body"), "Jump action must not use Space", failures)
	for banned in BANNED_INPUT_ACTIONS:
		require(banned not in project_text, f"Banned co-op input/config found: {banned}", failures)


def check_shared_project_links(failures: list[str]) -> None:
	client_shared = CLIENT_ROOT / "shared"
	server_shared = REPO_ROOT / "server" / "shared"
	expected = (REPO_ROOT / "shared").resolve()
	for label, path in [("client/shared", client_shared), ("server/shared", server_shared)]:
		require(path.exists(), f"Missing {label}; res://shared paths will not resolve", failures)
		if path.exists():
			require(path.resolve() == expected, f"{label} must resolve to {expected}", failures)

def check_collision_contracts(failures: list[str]) -> None:
	for relative_path, snippets in COLLISION_SCENE_SNIPPETS.items():
		text = read(REPO_ROOT / relative_path if relative_path.startswith("shared/") else CLIENT_ROOT / relative_path)
		for snippet in snippets:
			require(snippet in text, f"{relative_path} missing collision contract {snippet}", failures)

	for relative_path, snippets in COLLISION_SCRIPT_SNIPPETS.items():
		text = read(REPO_ROOT / relative_path if relative_path.startswith("shared/") else CLIENT_ROOT / relative_path)
		for snippet in snippets:
			require(snippet in text, f"{relative_path} missing collision default {snippet}", failures)


def check_scene_contracts(failures: list[str]) -> None:
	game_text = read(CLIENT_ROOT / "scenes" / "bootstrap" / "game.tscn")
	require("res://scripts/core/game_manager/game_manager.gd" in game_text, "Game missing game_manager script", failures)
	require('name="LevelRoot"' in game_text, "Game missing LevelRoot", failures)
	require("res://scenes/ui/hud.tscn" in game_text, "Game missing HUD instance", failures)

	for player_scene_name in ["fireboy.tscn", "watergirl.tscn"]:
		player_text = read(CLIENT_ROOT / "scenes" / "players" / player_scene_name)
		require('type="CharacterBody2D"' in player_text, f"{player_scene_name} root is not CharacterBody2D", failures)
		for node_name in ["CollisionShape2D", "AnimatedSprite2D", "Camera2D"]:
			require(f'name="{node_name}"' in player_text, f"{player_scene_name} missing {node_name}", failures)
		require("res://scripts/player/movement/player.gd" in player_text, f"{player_scene_name} missing movement script", failures)
		for node_name in ["PlayerInputReader", "PlayerMotor", "PlayerAnimationController", "PushInteractor", "LadderDetector", "PlayerStateMachine"]:
			require(f'name="{node_name}"' in player_text, f"{player_scene_name} missing additive {node_name}", failures)
		for state_name in ["IdleState", "RunState", "AirborneState", "PushState", "ClimbState", "DisabledState"]:
			require(f'name="{state_name}"' in player_text, f"{player_scene_name} missing additive {state_name}", failures)

	level_text = read(CLIENT_ROOT / "scenes" / "levels" / "prototype_level.tscn")
	for node_name in ["Players", "PlayerSpawn", "Terrain", "Objects", "Collectibles", "Hazards", "Goals", "HazardZone", "LavaPool", "PoisonPool"]:
		require(f'name="{node_name}"' in level_text, f"Level missing {node_name}", failures)
	real_level_text = read(CLIENT_ROOT / "scenes" / "levels" / "real_level_blank.tscn")
	for node_name in ["Players", "PlayerSpawn", "Terrain", "Objects", "Hazards", "Goals", "FireDoor", "WaterDoor", "HazardZone", "LavaPool", "PoisonPool"]:
		require(f'name="{node_name}"' in real_level_text, f"Real blank level missing {node_name}", failures)
	require("res://shared/scripts/gameplay/levels/prototype_level.gd" in real_level_text, "Real blank level missing level script", failures)
	require("res://shared/scripts/gameplay/hazards/hazard_zone.gd" in real_level_text, "Real blank level missing hazard script", failures)

	game_real_text = read(CLIENT_ROOT / "scenes" / "bootstrap" / "game_real.tscn")
	require("res://scenes/levels/real_level_blank.tscn" in game_real_text, "Real game bootstrap missing blank level", failures)
	require("res://scripts/core/game_manager/game_manager.gd" in game_real_text, "Real game bootstrap missing game manager", failures)
	require('name="LevelRoot"' in game_real_text, "Real game bootstrap missing LevelRoot", failures)

	hud_text = read(CLIENT_ROOT / "scenes" / "ui" / "hud.tscn")
	require('type="CanvasLayer"' in hud_text, "HUD root is not CanvasLayer", failures)
	require("res://scenes/menus/pause_menu.tscn" in hud_text, "HUD missing pause menu", failures)
	require('name="GemLabel"' in hud_text, "HUD missing persistent gem count label", failures)


def check_goal_door_contracts(failures: list[str]) -> None:
	for level_name in ["real_level_blank.tscn", "real_level_blank_2.tscn"]:
		level_path = CLIENT_ROOT / "scenes" / "levels" / level_name
		require(level_path.exists(), f"Missing {level_name}", failures)
		if not level_path.exists():
			continue
		text = read(level_path)
		for snippet in [
			'path="res://shared/scenes/gameplay/doors/goal_door.tscn"',
			'name="FireDoor"',
			'name="WaterDoor"',
			"required_element = 0",
			"required_element = 1",
			'name="Collectibles"',
			'name="FireGem"',
			'name="WaterGem"',
			'name="PlayerSpawn"',
		]:
			require(snippet in text, f"{level_name} missing goal door contract snippet: {snippet}", failures)
		require("ExitDoor" not in text, f"{level_name} must use FireDoor/WaterDoor, not legacy ExitDoor", failures)
		require("PlayerSpawn2" not in text, f"{level_name} must use the shared PlayerSpawn, not PlayerSpawn2", failures)
		require("player_spawn_2_path" not in text, f"{level_name} must not override player_spawn_2_path", failures)

	prototype_text = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "levels" / "prototype_level.gd")
	for snippet in [
		"fire_goal_door_path",
		"water_goal_door_path",
		"_try_complete_level",
		"_fire_door_ready",
		"_water_door_ready",
	]:
		require(snippet in prototype_text, f"PrototypeLevel missing dual-door logic: {snippet}", failures)

	host_waiting_room_text = read(CLIENT_ROOT / "scenes" / "ui" / "host_waiting_room.tscn")
	require("res://scripts/ui/host_waiting_room.gd" in host_waiting_room_text, "Host waiting room missing script", failures)
	require('name="StartGameButton"' in host_waiting_room_text, "Host waiting room missing StartGameButton", failures)
	require('name="FireboyButton"' in host_waiting_room_text, "Host waiting room missing FireboyButton", failures)
	require('name="WatergirlButton"' in host_waiting_room_text, "Host waiting room missing WatergirlButton", failures)


def check_scripts(failures: list[str]) -> None:
	player_text = read(CLIENT_ROOT / "scripts" / "player" / "movement" / "player.gd")
	for snippet in [
		"class_name PrototypePlayer",
		"enum PlayerState { IDLE, RUNNING, AIRBORNE, PUSHING, CLIMBING, DISABLED }",
		"enum Element { FIRE, WATER }",
		"@export var speed: float",
		"@export var jump_velocity: float",
		"@export var state_machine_path: NodePath",
		"@export var ladder_detector_path: NodePath",
		"reset_to_spawn",
		"set_control_enabled",
		"func get_player_state() -> PlayerState:",
		"func get_player_state_name() -> StringName:",
		"func get_push_direction() -> float:",
		"func can_survive_pool(pool_type: int) -> bool:",
		"_state_machine.transition_from_player_context()",
		"func is_ladder_available() -> bool:",
		"func apply_ladder_movement(delta: float) -> void:",
	]:
		require(snippet in player_text, f"Player script missing {snippet}", failures)
	require("var existing_key_event: InputEventKey" in player_text, "Player input setup should avoid key_event shadow warning", failures)
	for snippet in ["@export var air_acceleration: float", "@export var air_deceleration: float", "@export var turn_acceleration: float", "@export var air_brake_multiplier: float", "@export var jump_hold_time: float", "@export var rise_gravity_multiplier: float", "@export var fall_gravity_multiplier: float", "@export var jump_cut_gravity_multiplier: float", "@export var edge_correction_distance: float", "func clear_precision_timers() -> void:", "_get_run_jump_velocity", "clampf(absf(velocity.x) / speed"]:
		require(snippet in player_text, f"Player momentum jump missing {snippet}", failures)
	for snippet in ["@export var camera_path: NodePath", "make_current()", "reset_smoothing()"]:
		require(snippet in player_text, f"Player camera restart fix missing {snippet}", failures)

	prediction_text = read(CLIENT_ROOT / "scripts" / "multiplayer" / "prediction" / "client_prediction_controller.gd")
	for snippet in [
		"class_name ClientPredictionController",
		"const MAX_PENDING_INPUTS: int = 128",
		"func predict(packet: Dictionary, delta: float) -> PlayerMovementState:",
		"func reconcile(snapshot: Dictionary, delta: float) -> PlayerMovementState:",
		"func _replay_pending_inputs(delta: float) -> PlayerMovementState:",
	]:
		require(snippet in prediction_text, f"Prediction controller missing {snippet}", failures)

	game_manager_text = read(CLIENT_ROOT / "scripts" / "core" / "game_manager" / "game_manager.gd")
	for state in ["LOADING_LEVEL", "PLAYING", "PAUSED", "WON", "LOST", "RESTARTING"]:
		require(state in game_manager_text, f"Game manager missing state {state}", failures)
	for snippet in ["var _is_reloading: bool", "queue_free()", "await get_tree().process_frame", "call_deferred(\"_load_level\")", "_set_player_control_enabled(false)"]:
		require(snippet in game_manager_text, f"Game manager restart fix missing {snippet}", failures)
	require(
		'DEFAULT_LEVEL_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")' in game_manager_text,
		"Game manager default level must be the real blank level, not the prototype fallback",
		failures,
	)

	for relative_path in [
		"shared/scripts/gameplay/levels/prototype_level.gd",
		"shared/scripts/gameplay/hazards/hazard_zone.gd",
		"shared/scripts/gameplay/doors/exit_door.gd",
		"shared/scripts/gameplay/collectibles/collectible_gem.gd",
		"shared/scripts/gameplay/collectibles/gem_manager.gd",
		"shared/scripts/gameplay/objects/push_block.gd",
		"scripts/ui/hud/hud.gd",
		"scripts/ui/host_waiting_room.gd",
		"scripts/ui/menus/pause_menu.gd",
	]:
		text = read(REPO_ROOT / relative_path if relative_path.startswith("shared/") else CLIENT_ROOT / relative_path)
		require("extends " in text, f"{relative_path} missing extends", failures)

	network_manager_text = read(CLIENT_ROOT / "scripts" / "network_manager.gd")
	for snippet in [
		"func host_room(port: int = DEFAULT_PORT) -> void:",
		"OS.create_process",
		"func request_role(role: int) -> void:",
		"rpc_id(1, \"request_role\", role)",
		"func start_game() -> void:",
		"rpc_id(1, \"request_start_game\")",
		"signal authoritative_player_snapshot_received(player_id: int, snapshot: Dictionary)",
		"func send_player_input(packet: Dictionary) -> void:",
		"rpc_id(1, \"receive_player_input\", multiplayer.get_unique_id(), packet)",
		"func receive_authoritative_player_snapshot(player_id: int, snapshot: Dictionary) -> void:",
	]:
		require(snippet in network_manager_text, f"Network manager host flow missing {snippet}", failures)

	server_network_manager_text = read(REPO_ROOT / "server" / "network_manager.gd")
	for snippet in [
		"func request_role(role: int) -> void:",
		"_assign_role(sender_id, role)",
		"func request_start_game() -> void:",
		"multiplayer.get_remote_sender_id()",
		"rpc_id(pid, \"notify_game_start\")",
		"var _authoritative_states: Dictionary = {}",
		"func receive_player_input(player_id: int, packet: Dictionary) -> void:",
		"PlayerMovementSimulator.step",
		"rpc_id(sender_id, \"receive_authoritative_player_snapshot\", player_id, snapshot)",
	]:
		require(snippet in server_network_manager_text, f"Server host flow missing {snippet}", failures)

	player_text = read(CLIENT_ROOT / "scripts" / "player" / "movement" / "player.gd")
	for snippet in [
		"var _prediction_controller: ClientPredictionController",
		"func apply_authoritative_snapshot(snapshot: Dictionary) -> void:",
		"_prediction_controller.reconcile(snapshot, _last_prediction_delta)",
	]:
		require(snippet in player_text, f"Player prediction integration missing {snippet}", failures)

	game_manager_text = read(CLIENT_ROOT / "scripts" / "core" / "game_manager" / "game_manager.gd")
	for snippet in [
		"NetworkManager.authoritative_player_snapshot_received.connect(_on_authoritative_player_snapshot_received)",
		"func _on_authoritative_player_snapshot_received(player_id: int, snapshot: Dictionary) -> void:",
		"if _player.has_method(\"apply_authoritative_snapshot\")",
	]:
		require(snippet in game_manager_text, f"Game manager prediction routing missing {snippet}", failures)

	scene_loader_text = read(CLIENT_ROOT / "addons" / "maaacks_game_template" / "base" / "nodes" / "autoloads" / "scene_loader" / "scene_loader.gd")
	require(
		"ResourceLoader.CACHE_MODE_REPLACE_DEEP" in scene_loader_text,
		"SceneLoader must replace deep resource cache so editor debug runs cannot reuse stale gameplay scenes",
		failures,
	)
	require(
		"ResourceLoader.load(_scene_path, \"\", ResourceLoader.CACHE_MODE_REPLACE_DEEP)" in scene_loader_text,
		"SceneLoader must load scenes synchronously with deep cache replacement",
		failures,
	)
	require(
		"call_deferred(\"change_scene_to_resource\")" in scene_loader_text,
		"SceneLoader cached scene changes must be deferred out of the loading callback",
		failures,
	)
	require(
		"load_threaded_get" not in scene_loader_text,
		"SceneLoader must not call load_threaded_get because it crashes Godot 4.6.2 in the gameplay start flow",
		failures,
	)
	require(
		"load_threaded_request" not in scene_loader_text,
		"SceneLoader must not use threaded scene loading in the gameplay start flow",
		failures,
	)
	lobby_ui_text = read(CLIENT_ROOT / "scripts" / "ui" / "lobby_ui.gd")
	require(
		"SceneLoader.load_scene(\"res://scenes/bootstrap/game.tscn\")" in lobby_ui_text,
		"Lobby game start should use cache-replacing SceneLoader",
		failures,
	)
	require(
		"change_scene_to_file(\"res://scenes/bootstrap/game.tscn\")" not in lobby_ui_text,
		"Lobby game start must not bypass SceneLoader with change_scene_to_file",
		failures,
	)

	hazard_text = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "hazards" / "hazard_zone.gd")
	require("POISON" in hazard_text, "Hazard zone missing poison pool type", failures)

	collectible_gem_text = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "collectibles" / "collectible_gem.gd")
	for snippet in [
		"class_name CollectibleGem",
		"extends Area2D",
		"enum GemElement { FIRE, WATER }",
		"signal collected(gem: CollectibleGem, player: PrototypePlayer)",
		"signal wrong_element_touched(gem: CollectibleGem, player: PrototypePlayer)",
		"func can_collect(player: PrototypePlayer) -> bool:",
		'set_deferred("monitoring", false)',
		'set_deferred("monitorable", false)',
	]:
		require(snippet in collectible_gem_text, f"Collectible gem missing {snippet}", failures)

	gem_manager_text = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "collectibles" / "gem_manager.gd")
	for snippet in [
		"class_name GemManager",
		"extends Node2D",
		"signal gem_progress_changed(collected: int, required: int)",
		"func configure_for_player(player: PrototypePlayer) -> void:",
		"func is_unlocked() -> bool:",
		"func get_remaining_count() -> int:",
		"required_count == 0",
	]:
		require(snippet in gem_manager_text, f"Gem manager missing {snippet}", failures)

	level_script_text = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "levels" / "prototype_level.gd")
	for snippet in [
		"signal exit_locked(remaining: int, gem_element: int)",
		"@export var collectibles_path: NodePath = ^\"Collectibles\"",
		"_gem_manager.configure_for_player",
		"_gem_manager.is_unlocked()",
	]:
		require(snippet in level_script_text, f"Level gem gate missing {snippet}", failures)

	hud_script_text = read(CLIENT_ROOT / "scripts" / "ui" / "hud" / "hud.gd")
	for snippet in [
		"func set_gem_progress(collected: int, required: int) -> void:",
		"_gem_label.text",
		"Gems: %s/%s",
	]:
		require(snippet in hud_script_text, f"HUD gem progress missing {snippet}", failures)

	pause_menu_text = read(CLIENT_ROOT / "scripts" / "ui" / "menus" / "pause_menu.gd")
	require("func set_paused_view(should_show: bool) -> void:" in pause_menu_text, "Pause menu should avoid is_visible shadow warning", failures)

	gem_scene_text = read(REPO_ROOT / "shared" / "scenes" / "gameplay" / "collectibles" / "collectible_gem.tscn")
	for snippet in [
		'type="Area2D"',
		'name="Visual"',
		'type="Polygon2D"',
		'name="CollisionShape2D"',
		"res://shared/scripts/gameplay/collectibles/collectible_gem.gd",
	]:
		require(snippet in gem_scene_text, f"Collectible gem scene missing {snippet}", failures)

	push_block_text = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "objects" / "push_block.gd")
	for snippet in [
		"class_name PushBlock",
		"extends RigidBody2D",
		'add_to_group("push_block")',
		"@export var max_push_force: float",
		"@export var push_ramp_time: float",
		"@export var two_player_boost_multiplier: float",
		"@export var max_linear_speed: float",
		"@export var max_angular_speed: float",
		"@export var idle_damping: float",
		"@export var moving_damping: float",
		"func register_push_attempt(body: Node2D, push_direction: float) -> void:",
		"_push_attempts",
		"move_toward",
		"_integrate_forces",
	]:
		require(snippet in push_block_text, f"Push block missing {snippet}", failures)

	for snippet in [
		"func get_push_direction() -> float:",
		"_register_push_block_contacts",
		"PushInteractor",
	]:
		require(snippet in player_text, f"Player push contact missing {snippet}", failures)

	push_block_scene = read(REPO_ROOT / "shared" / "scenes" / "gameplay" / "objects" / "push_block.tscn")
	for snippet in [
		'type="RigidBody2D"',
		'name="CollisionShape2D"',
		'name="Visual"',
		'name="PushDetector"',
		'name="GroundDetector"',
		"size = Vector2(16, 16)",
		"res://shared/scripts/gameplay/objects/push_block.gd",
	]:
		require(snippet in push_block_scene, f"Push block scene missing {snippet}", failures)

	pressure_button_text = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "objects" / "pressure_button.gd")
	for snippet in ["class_name PressureButton", "@export var visual_path: NodePath", "@export var released_frame: int", "@export var pressed_frame: int", "func _sync_visual_state() -> void:", "AnimatedSprite2D"]:
		require(snippet in pressure_button_text, f"Pressure button artwork state missing {snippet}", failures)
	pressure_button_scene = read(CLIENT_ROOT / "scenes" / "gameplay" / "objects" / "pressure_button.tscn")
	for snippet in ['name="PressureButton"', 'name="CollisionShape2D"', 'name="AnimatedSprite2D"', "SpriteFrames"]:
		require(snippet in pressure_button_scene, f"Pressure button scene missing {snippet}", failures)
	require("frame = 0" in pressure_button_scene or "frame = " not in pressure_button_scene, "Pressure button scene should start on default frame 0", failures)

	ladder_text = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "objects" / "ladder.gd")
	for snippet in ["class_name Ladder", "extends Area2D", "@export var climb_speed: float", "add_to_group(\"ladder\")", "func get_climb_speed() -> float:"]:
		require(snippet in ladder_text, f"Ladder script missing {snippet}", failures)
	ladder_scene = read(CLIENT_ROOT / "scenes" / "gameplay" / "objects" / "ladder.tscn")
	for snippet in ['name="Ladder"', 'type="Area2D"', 'name="CollisionShape2D"', "res://shared/scripts/gameplay/objects/ladder.gd"]:
		require(snippet in ladder_scene, f"Ladder scene missing {snippet}", failures)

	check_player_state_machine_structure(failures)

def check_player_state_machine_structure(failures: list[str]) -> None:
	for relative_path in PLAYER_COMPONENT_FILES + PLAYER_STATE_FILES:
		text = read(CLIENT_ROOT / relative_path)
		require("extends " in text, f"{relative_path} missing extends", failures)

	base_state_text = read(CLIENT_ROOT / "scripts" / "player" / "state_machine" / "player_state.gd")
	for snippet in ["class_name PlayerStateNode", "var owner_player: PrototypePlayer", "func enter", "func exit", "func physics_update", "func get_stable_name() -> StringName:"]:
		require(snippet in base_state_text, f"Base player state missing {snippet}", failures)

	state_machine_text = read(CLIENT_ROOT / "scripts" / "player" / "state_machine" / "player_state_machine.gd")
	for snippet in ["class_name PlayerStateMachine", "func transition_to", "func transition_from_player_context", "func get_current_state_name() -> StringName:", "push_error(\"Unknown player state transition target"]:
		require(snippet in state_machine_text, f"Player state machine missing {snippet}", failures)

	input_text = read(CLIENT_ROOT / "scripts" / "player" / "input" / "player_input_reader.gd")
	for snippet in ['Input.get_axis("move_left", "move_right")', 'Input.is_action_just_pressed("jump")', 'Input.is_action_just_released("jump")', "var jump_pressed: bool = false", "var jump_just_released: bool = false", "KEY_A", "KEY_D", "KEY_S", "KEY_W"]:
		require(snippet in input_text, f"Player input reader missing {snippet}", failures)

	motor_text = read(CLIENT_ROOT / "scripts" / "player" / "motor" / "player_motor.gd")
	for snippet in ["class_name PlayerMotor", "const EDGE_CORRECTION_SCRIPT", "func apply_movement", "func get_run_jump_velocity", "func was_edge_correction_applied_this_frame() -> bool:", "_coyote_timer", "_jump_buffer_timer", "_jump_hold_timer", "turn_acceleration", "jump_hold_time", "fall_gravity_multiplier", "fast_fall_gravity_multiplier"]:
		require(snippet in motor_text, f"Player motor missing {snippet}", failures)

	animation_text = read(CLIENT_ROOT / "scripts" / "player" / "animation" / "player_animation_controller.gd")
	for snippet in ["class_name PlayerAnimationController", "func play_for_motion", "flip_h", "sprite_frames.has_animation"]:
		require(snippet in animation_text, f"Player animation controller missing {snippet}", failures)

	push_text = read(CLIENT_ROOT / "scripts" / "player" / "interaction" / "push_interactor.gd")
	for snippet in ["class_name PushInteractor", "PhysicsRayQueryParameters2D.create", "intersect_shape", "register_push_attempt", "last_push_contact"]:
		require(snippet in push_text, f"Push interactor missing {snippet}", failures)

	ladder_detector_text = read(CLIENT_ROOT / "scripts" / "player" / "interaction" / "ladder_detector.gd")
	for snippet in ["class_name LadderDetector", "extends Area2D", "func is_on_ladder() -> bool:", "func get_current_climb_speed", "area_entered.connect", "area_exited.connect"]:
		require(snippet in ladder_detector_text, f"Ladder detector missing {snippet}", failures)

	edge_correction_text = read(CLIENT_ROOT / "scripts" / "player" / "motor" / "edge_correction.gd")
	for snippet in ["class_name EdgeCorrection", "func try_apply(delta: float, input_direction: float) -> bool:", "edge_correction_distance", "owner_player.test_move", "correction_applied_this_frame"]:
		require(snippet in edge_correction_text, f"Edge correction helper missing {snippet}", failures)

	state_names = {
		"idle_state.gd": "&\"idle\"",
		"run_state.gd": "&\"run\"",
		"airborne_state.gd": "&\"airborne\"",
		"push_state.gd": "&\"push\"",
		"climb_state.gd": "&\"climb\"",
		"disabled_state.gd": "&\"disabled\"",
	}
	for file_name, state_literal in state_names.items():
		state_text = read(CLIENT_ROOT / "scripts" / "player" / "states" / file_name)
		require(state_literal in state_text, f"{file_name} missing stable state name {state_literal}", failures)
		require("func enter" in state_text and "func exit" in state_text, f"{file_name} missing explicit enter/exit hooks", failures)

	catch_all = CLIENT_ROOT / "scripts" / "player" / "states" / "player_states.gd"
	require(not catch_all.exists(), "Do not add one catch-all scripts/player/states/player_states.gd", failures)


def check_res_paths(failures: list[str]) -> None:
	for file_path in CLIENT_ROOT.rglob("*"):
		if file_path.suffix not in {".tscn", ".tres", ".import", ".godot"}:
			continue
		if "addons\\maaacks_game_template" in str(file_path.relative_to(CLIENT_ROOT)):
			continue
		text = file_path.read_text(encoding="utf-8", errors="ignore")
		for match in re.finditer(r'res://[^"\]\)]+', text):
			res_path = match.group(0)
			if res_path.startswith("res://.godot/"):
				continue
			if res_path.startswith("res://shared/") or res_path.startswith("res://client/"):
				local_path = REPO_ROOT / res_path.removeprefix("res://")
			else:
				local_path = CLIENT_ROOT / res_path.removeprefix("res://")
			require(local_path.exists(), f"Broken res path in {file_path.relative_to(CLIENT_ROOT)}: {res_path}", failures)


def check_review_regressions(failures: list[str]) -> None:
	player_text = read(CLIENT_ROOT / "scripts" / "player" / "movement" / "player.gd")
	require(
		"_apply_prediction_state(predicted_state)" not in player_text,
		"Connected player prediction must not apply raw simulated position before move_and_slide",
		failures,
	)
	require(
		"NetworkManager.send_player_input(input_packet)" not in player_text,
		"Do not send live prediction input until server simulation is collision-aware",
		failures,
	)

	server_text = read(REPO_ROOT / "server" / "network_manager.gd")
	require(
		'packet.get("t", 0)' in server_text,
		"Server authoritative snapshot must ack the input packet tick key 't'",
		failures,
	)
	require(
		'packet.get("ack_tick", 0)' not in server_text,
		"Server must not read ack_tick from client input packets",
		failures,
	)

	gem_script = read(REPO_ROOT / "shared" / "scripts" / "gameplay" / "collectibles" / "collectible_gem.gd")
	require(
		"can_collect(player)" in gem_script,
		"CollectibleGem._on_body_entered must call can_collect() with a PrototypePlayer",
		failures,
	)
	require(
		"collision_mask = 1 # Force look at layer 1" not in gem_script,
		"CollectibleGem must not override its mask to World at runtime",
		failures,
	)

	for relative_path in [
		"scenes/levels/prototype_level.tscn",
		"scenes/levels/ladder_test_level.tscn",
	]:
		text = read(CLIENT_ROOT / relative_path)
		require(
			"res://client/" not in text,
			f"{relative_path} must not use res://client paths inside the client project",
			failures,
		)

	gem_scene = read(REPO_ROOT / "shared" / "scenes" / "gameplay" / "collectibles" / "collectible_gem.tscn")
	require(gem_scene.count("collision_mask = ") == 1, "Collectible gem scene must have one collision_mask assignment", failures)
	require("collision_mask = 2" in gem_scene, "Collectible gem must scan Player layer", failures)

	push_scene = read(REPO_ROOT / "shared" / "scenes" / "gameplay" / "objects" / "push_block.tscn")
	root_block = push_scene.split("[node name=\"PushDetector\"", 1)[0]
	require(root_block.count("collision_mask = ") == 1, "PushBlock root must have one collision_mask assignment", failures)
	require("collision_mask = 3" in root_block, "PushBlock root must scan World and Player layers", failures)


def check_multiplayer_gameplay_sync_contracts(failures: list[str]) -> None:
	gameplay_files = [
		REPO_ROOT / "shared" / "scripts" / "gameplay" / "collectibles" / "collectible_gem.gd",
		REPO_ROOT / "shared" / "scripts" / "gameplay" / "collectibles" / "gem_manager.gd",
		REPO_ROOT / "shared" / "scripts" / "gameplay" / "objects" / "push_block.gd",
	]
	for path in gameplay_files:
		text = read(path)
		require("/root/GameplayRpc" not in text, f"{path} must use NetworkManager gameplay relay, not GameplayRpc", failures)
		require("/root/GameplayRPC" not in text, f"{path} must not use legacy GameplayRPC lookup", failures)


def main() -> int:
	failures: list[str] = []
	check_required_files(failures)
	check_rules(failures)
	if (CLIENT_ROOT / "project.godot").exists():
		check_project_settings(failures)
	check_shared_project_links(failures)
	if not failures:
		check_scene_contracts(failures)
		check_goal_door_contracts(failures)
		check_scripts(failures)
		check_collision_contracts(failures)
		check_multiplayer_gameplay_sync_contracts(failures)
		check_res_paths(failures)
		check_review_regressions(failures)
	if failures:
		print("Prototype foundation verification failed:")
		for failure in failures:
			print(f"- {failure}")
		return 1
	print("Prototype foundation verification passed.")
	return 0


if __name__ == "__main__":
	sys.exit(main())
