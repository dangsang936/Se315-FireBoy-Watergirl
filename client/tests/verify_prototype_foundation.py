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
	"scenes/levels/prototype_level.tscn",
	"scenes/levels/real_level_blank.tscn",
	"scenes/ui/hud.tscn",
	"scenes/menus/pause_menu.tscn",
	"scripts/core/game_manager/game_manager.gd",
	"scripts/player/movement/player.gd",
	"scripts/gameplay/levels/prototype_level.gd",
	"scripts/gameplay/hazards/hazard_zone.gd",
	"scripts/gameplay/doors/exit_door.gd",
	"scripts/gameplay/objects/push_block.gd",
	"scripts/ui/hud/hud.gd",
	"scripts/ui/menus/pause_menu.gd",
	"scenes/gameplay/objects/push_block.tscn",
	"docs/level_workflow.md",
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


def read(path: Path) -> str:
	return path.read_text(encoding="utf-8")


def require(condition: bool, message: str, failures: list[str]) -> None:
	if not condition:
		failures.append(message)


def check_required_files(failures: list[str]) -> None:
	for relative_path in REQUIRED_FILES:
		require((CLIENT_ROOT / relative_path).exists(), f"Missing {relative_path}", failures)


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
	require('run/main_scene="res://scenes/bootstrap/game.tscn"' in project_text, "Wrong main scene", failures)
	for action in REQUIRED_ACTIONS:
		require(f'{action}=' in project_text, f"Missing input action {action}", failures)
	jump_block = re.search(r"jump=\{\n(?P<body>.*?)\n\}", project_text, re.S)
	require(jump_block is not None, "Missing jump input block", failures)
	if jump_block:
		require('"keycode":87' in jump_block.group("body"), "Jump action must use W", failures)
		require('"keycode":32' not in jump_block.group("body"), "Jump action must not use Space", failures)
	for banned in BANNED_INPUT_ACTIONS:
		require(banned not in project_text, f"Banned co-op input/config found: {banned}", failures)


def check_scene_contracts(failures: list[str]) -> None:
	game_text = read(CLIENT_ROOT / "scenes" / "bootstrap" / "game.tscn")
	require("res://scripts/core/game_manager/game_manager.gd" in game_text, "Game missing game_manager script", failures)
	require('name="LevelRoot"' in game_text, "Game missing LevelRoot", failures)
	require("res://scenes/ui/hud.tscn" in game_text, "Game missing HUD instance", failures)

	player_text = read(CLIENT_ROOT / "scenes" / "players" / "fireboy.tscn")
	require('type="CharacterBody2D"' in player_text, "Player root is not CharacterBody2D", failures)
	require('name="Camera2D"' in player_text, "Player scene missing Camera2D", failures)
	require("res://scripts/player/movement/player.gd" in player_text, "Player scene missing movement script", failures)

	level_text = read(CLIENT_ROOT / "scenes" / "levels" / "prototype_level.tscn")
	for node_name in ["Players", "PlayerSpawn", "Terrain", "Hazards", "Goals", "ExitDoor", "HazardZone", "LavaPool", "PoisonPool"]:
		require(f'name="{node_name}"' in level_text, f"Level missing {node_name}", failures)
	real_level_text = read(CLIENT_ROOT / "scenes" / "levels" / "real_level_blank.tscn")
	for node_name in ["Players", "PlayerSpawn", "Terrain", "Objects", "Hazards", "Goals", "ExitDoor", "HazardZone", "LavaPool", "PoisonPool"]:
		require(f'name="{node_name}"' in real_level_text, f"Real blank level missing {node_name}", failures)
	require("res://scripts/gameplay/levels/prototype_level.gd" in real_level_text, "Real blank level missing level script", failures)
	require("res://scripts/gameplay/hazards/hazard_zone.gd" in real_level_text, "Real blank level missing hazard script", failures)

	game_real_text = read(CLIENT_ROOT / "scenes" / "bootstrap" / "game_real.tscn")
	require("res://scenes/levels/real_level_blank.tscn" in game_real_text, "Real game bootstrap missing blank level", failures)
	require("res://scripts/core/game_manager/game_manager.gd" in game_real_text, "Real game bootstrap missing game manager", failures)
	require('name="LevelRoot"' in game_real_text, "Real game bootstrap missing LevelRoot", failures)

	hud_text = read(CLIENT_ROOT / "scenes" / "ui" / "hud.tscn")
	require('type="CanvasLayer"' in hud_text, "HUD root is not CanvasLayer", failures)
	require("res://scenes/menus/pause_menu.tscn" in hud_text, "HUD missing pause menu", failures)


def check_scripts(failures: list[str]) -> None:
	player_text = read(CLIENT_ROOT / "scripts" / "player" / "movement" / "player.gd")
	for snippet in ["@export var speed: float", "@export var jump_velocity: float", 'Input.get_axis("move_left", "move_right")', 'is_action_just_pressed("jump")', "reset_to_spawn"]:
		require(snippet in player_text, f"Player script missing {snippet}", failures)
	for snippet in ["@export var air_acceleration: float", "@export var air_deceleration: float", "@export var run_jump_height_multiplier: float", "_get_run_jump_velocity", "clampf(absf(velocity.x) / speed"]:
		require(snippet in player_text, f"Player momentum jump missing {snippet}", failures)
	for snippet in ["@export var camera_path: NodePath", "make_current()", "reset_smoothing()"]:
		require(snippet in player_text, f"Player camera restart fix missing {snippet}", failures)

	game_manager_text = read(CLIENT_ROOT / "scripts" / "core" / "game_manager" / "game_manager.gd")
	for state in ["LOADING_LEVEL", "PLAYING", "PAUSED", "WON", "LOST", "RESTARTING"]:
		require(state in game_manager_text, f"Game manager missing state {state}", failures)
	for snippet in ["var _is_reloading: bool", "queue_free()", "await get_tree().process_frame", "call_deferred(\"_load_level\")", "_set_player_control_enabled(false)"]:
		require(snippet in game_manager_text, f"Game manager restart fix missing {snippet}", failures)

	for relative_path in [
		"scripts/gameplay/levels/prototype_level.gd",
		"scripts/gameplay/hazards/hazard_zone.gd",
		"scripts/gameplay/doors/exit_door.gd",
		"scripts/gameplay/objects/push_block.gd",
		"scripts/ui/hud/hud.gd",
		"scripts/ui/menus/pause_menu.gd",
	]:
		text = read(CLIENT_ROOT / relative_path)
		require("extends " in text, f"{relative_path} missing extends", failures)

	hazard_text = read(CLIENT_ROOT / "scripts" / "gameplay" / "hazards" / "hazard_zone.gd")
	require("POISON" in hazard_text, "Hazard zone missing poison pool type", failures)

	push_block_text = read(CLIENT_ROOT / "scripts" / "gameplay" / "objects" / "push_block.gd")
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

	player_text = read(CLIENT_ROOT / "scripts" / "player" / "movement" / "player.gd")
	for snippet in [
		"func get_push_direction() -> float:",
		"_register_push_block_contacts",
		"_register_push_block_probe",
		"PhysicsRayQueryParameters2D.create",
		"register_push_attempt",
	]:
		require(snippet in player_text, f"Player push contact missing {snippet}", failures)

	push_block_scene = read(CLIENT_ROOT / "scenes" / "gameplay" / "objects" / "push_block.tscn")
	for snippet in [
		'type="RigidBody2D"',
		'name="CollisionShape2D"',
		'name="Visual"',
		'name="PushDetector"',
		'name="GroundDetector"',
		"size = Vector2(16, 16)",
		"res://scripts/gameplay/objects/push_block.gd",
	]:
		require(snippet in push_block_scene, f"Push block scene missing {snippet}", failures)


def check_res_paths(failures: list[str]) -> None:
	for file_path in CLIENT_ROOT.rglob("*"):
		if file_path.suffix not in {".tscn", ".tres", ".import", ".godot"}:
			continue
		text = file_path.read_text(encoding="utf-8", errors="ignore")
		for match in re.finditer(r'res://[^"\]\)]+', text):
			res_path = match.group(0)
			if res_path.startswith("res://.godot/"):
				continue
			local_path = CLIENT_ROOT / res_path.removeprefix("res://")
			require(local_path.exists(), f"Broken res path in {file_path.relative_to(CLIENT_ROOT)}: {res_path}", failures)


def main() -> int:
	failures: list[str] = []
	check_required_files(failures)
	check_rules(failures)
	if (CLIENT_ROOT / "project.godot").exists():
		check_project_settings(failures)
	if not failures:
		check_scene_contracts(failures)
		check_scripts(failures)
		check_res_paths(failures)
	if failures:
		print("Prototype foundation verification failed:")
		for failure in failures:
			print(f"- {failure}")
		return 1
	print("Prototype foundation verification passed.")
	return 0


if __name__ == "__main__":
	sys.exit(main())
