# FireBoy WaterGirl Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the review findings from `C:/Users/HABAYAKKA/AppData/Local/Temp/fireboy-watergirl-handoff-2026-07-01.md`: connected-player collision bypass, gem compile failure, P2 start-game evidence, prediction ack ticks, bad resource paths, duplicate collision masks, and UI-plan scope drift.

**Architecture:** Make the immediate multiplayer gameplay path use the existing Godot `CharacterBody2D` motor and `move_and_slide()` as the source of local collision truth. Keep the current data-only prediction code as an offline contract/probe until it can be rebuilt with collision-aware simulation. Add small regression contracts before code changes, then fix one review item per task.

**Tech Stack:** Godot 4.6, typed GDScript with tabs, ENet RPCs, PowerShell on Windows, repo RTK command wrapper.

---

## File Structure

- Modify: `client/tests/verify_prototype_foundation.py`
  - Add regression checks for review findings that static verification can catch.
- Modify: `shared/scripts/gameplay/collectibles/collectible_gem.gd`
  - Fix `can_collect()` caller type, preserve player-based signal contract, stop overriding gem mask to World.
- Modify: `shared/scripts/gameplay/collectibles/gem_manager.gd`
  - Align collected signal handler signature with `CollectibleGem.collected(gem, player)`.
- Modify: `shared/scenes/gameplay/collectibles/collectible_gem.tscn`
  - Remove duplicate `collision_mask = 1`; keep Player mask.
- Modify: `shared/scripts/gameplay/objects/push_block.gd`
  - Reapply push block layer/mask and detector mask from constants at runtime.
- Modify: `shared/scenes/gameplay/objects/push_block.tscn`
  - Remove duplicate root mask override; keep combined World+Player mask.
- Modify: `client/scenes/levels/prototype_level.tscn`
  - Replace invalid `res://client/...` resource path with `res://scenes/...`.
- Modify: `client/scenes/levels/ladder_test_level.tscn`
  - Replace invalid `res://client/...` resource paths with `res://scenes/...`.
- Modify: `client/scripts/player/movement/player.gd`
  - Remove live collisionless prediction branch from `_physics_process`; never set `global_position` before returning from physics.
- Modify: `server/network_manager.gd`
  - Fix authoritative snapshot ack tick from input packet key `"t"` and add start-game broadcast evidence logs.
- Modify: `client/scripts/network_manager.gd`
  - Add start-game receive evidence log.
- Modify: `client/scripts/ui/lobby_ui.gd`
  - Log scene transition and report `change_scene_to_file()` error.
- Modify: `client/scripts/ui/host_waiting_room.gd`
  - Log SceneLoader transition from the host waiting room.
- Decision point: `client/scripts/network_manager.gd`, `server/network_manager.gd`, `plan.md`
  - Either revert real listen-server scope drift to UI-only stub, or mark the real listen-server as accepted new scope and create a follow-up plan for lifecycle/process cleanup.

---

## Task 1: Add Review Regression Contracts

**Files:**
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Add a failing review-regression verifier**

Add this function after `check_res_paths()`:

```python
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
```

- [ ] **Step 2: Call the new verifier**

In `main()`, after `check_res_paths(failures)`, add:

```python
	check_review_regressions(failures)
```

- [ ] **Step 3: Run verifier and confirm it fails for current review issues**

Run:

```powershell
rtk python client\tests\verify_prototype_foundation.py
```

Expected: FAIL with at least the current prediction, ack tick, `res://client`, and duplicate collision mask review messages.

- [ ] **Step 4: Commit**

```powershell
rtk git add client\tests\verify_prototype_foundation.py
rtk git commit -m "test: lock review regression contracts"
```

---

## Task 2: Fix Gem Compile Error And Gem Collision Mask

**Files:**
- Modify: `shared/scripts/gameplay/collectibles/collectible_gem.gd`
- Modify: `shared/scripts/gameplay/collectibles/gem_manager.gd`
- Modify: `shared/scenes/gameplay/collectibles/collectible_gem.tscn`

- [ ] **Step 1: Fix `CollectibleGem._ready()` and `_on_body_entered()`**

Replace lines 20-60 of `shared/scripts/gameplay/collectibles/collectible_gem.gd` with:

```gdscript
func _ready() -> void:
	collision_layer = GEM_COLLISION_LAYER
	collision_mask = GEM_COLLISION_MASK
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
		monitoring = true
		monitorable = true
	_apply_element_color()

func can_collect(player: PrototypePlayer) -> bool:
	return player != null and int(player.get("element")) == int(gem_element)

func _on_body_entered(body: Node2D) -> void:
	if _is_collected or not body.is_in_group("player"):
		return

	var player := body as PrototypePlayer
	if player == null:
		return

	var pid: int = 0
	if body.has_meta("player_id"):
		pid = int(body.get_meta("player_id"))
	elif "player_id" in body:
		pid = int(body.get("player_id"))

	if pid == 0:
		return

	if not can_collect(player):
		wrong_element_touched.emit(self, player)
		return

	var msg: String = "[Server] Player " + str(pid) + " collect gem: " + name
	print(msg)
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_method("s_print"):
		nm.s_print(msg)
	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	collected.emit(self, player)

	var rpc_node = get_node_or_null("/root/GameplayRPC")
	if rpc_node:
		rpc_node.rpc("sync_gem_collected", name, global_position)
```

- [ ] **Step 2: Align `GemManager` signal handler signature**

Change:

```gdscript
func _on_gem_collected(gem: CollectibleGem, _player_id: int) -> void:
```

to:

```gdscript
func _on_gem_collected(gem: CollectibleGem, _player: PrototypePlayer) -> void:
```

- [ ] **Step 3: Remove duplicate gem mask**

In `shared/scenes/gameplay/collectibles/collectible_gem.tscn`, keep this root collision block:

```text
collision_layer = 32
collision_mask = 2
```

Delete the later:

```text
collision_mask = 1
```

- [ ] **Step 4: Run verifier and Godot parse**

Run:

```powershell
rtk python client\tests\verify_prototype_foundation.py
rtk powershell -NoProfile -Command "& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --path 'D:\FireBoyandWaterGirl\Se315-FireBoy-Watergirl\client' --headless --quit"
```

Expected: verifier still fails on later tasks, but gem compile/type and gem duplicate-mask failures are gone. Godot client parse has no `can_collect(player: PrototypePlayer)` int-argument error.

- [ ] **Step 5: Commit**

```powershell
rtk git add shared\scripts\gameplay\collectibles\collectible_gem.gd shared\scripts\gameplay\collectibles\gem_manager.gd shared\scenes\gameplay\collectibles\collectible_gem.tscn
rtk git commit -m "fix: align gem collection contract"
```

---

## Task 3: Fix PushBlock Collision Mask Override

**Files:**
- Modify: `shared/scripts/gameplay/objects/push_block.gd`
- Modify: `shared/scenes/gameplay/objects/push_block.tscn`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Reapply collision constants at runtime**

At the top of `func _ready() -> void:` in `shared/scripts/gameplay/objects/push_block.gd`, immediately after `add_to_group("push_block")`, add:

```gdscript
	collision_layer = PUSH_BLOCK_COLLISION_LAYER
	collision_mask = PUSH_BLOCK_COLLISION_MASK
	if _push_detector != null:
		_push_detector.collision_mask = PUSH_DETECTOR_COLLISION_MASK
```

- [ ] **Step 2: Remove duplicate root mask**

In `shared/scenes/gameplay/objects/push_block.tscn`, keep this root block:

```text
collision_layer = 4
collision_mask = 3
```

Delete the later root-level:

```text
collision_mask = 1
```

Keep the `PushDetector` node mask:

```text
collision_mask = 2
```

- [ ] **Step 3: Update verifier scene contract**

In `COLLISION_SCENE_SNIPPETS`, change the push block entry from:

```python
"shared/scenes/gameplay/objects/push_block.tscn": ["collision_layer = 4", "collision_mask = 3", "collision_mask = 2", "collision_mask = 1"],
```

to:

```python
"shared/scenes/gameplay/objects/push_block.tscn": ["collision_layer = 4", "collision_mask = 3", "collision_mask = 2"],
```

- [ ] **Step 4: Run verifier**

Run:

```powershell
rtk python client\tests\verify_prototype_foundation.py
```

Expected: push block duplicate-mask failure is gone.

- [ ] **Step 5: Commit**

```powershell
rtk git add shared\scripts\gameplay\objects\push_block.gd shared\scenes\gameplay\objects\push_block.tscn client\tests\verify_prototype_foundation.py
rtk git commit -m "fix: restore push block collision mask"
```

---

## Task 4: Fix Invalid `res://client/...` Resource Paths

**Files:**
- Modify: `client/scenes/levels/prototype_level.tscn`
- Modify: `client/scenes/levels/ladder_test_level.tscn`

- [ ] **Step 1: Replace paths in prototype level**

In `client/scenes/levels/prototype_level.tscn`, replace:

```text
path="res://client/scenes/gameplay/objects/ladder.tscn"
```

with:

```text
path="res://scenes/gameplay/objects/ladder.tscn"
```

- [ ] **Step 2: Replace paths in ladder test level**

In `client/scenes/levels/ladder_test_level.tscn`, replace:

```text
path="res://client/scenes/gameplay/objects/ladder.tscn"
path="res://client/scenes/gameplay/objects/pressure_button.tscn"
path="res://client/scenes/gameplay/collectibles/fire_gem.tscn"
```

with:

```text
path="res://scenes/gameplay/objects/ladder.tscn"
path="res://scenes/gameplay/objects/pressure_button.tscn"
path="res://scenes/gameplay/collectibles/fire_gem.tscn"
```

- [ ] **Step 3: Run targeted search**

Run:

```powershell
rtk rg -n "res://client" client server shared
```

Expected: only verifier code may mention the string as a banned-pattern check. No scene/resource file should still use it.

- [ ] **Step 4: Run verifier**

```powershell
rtk python client\tests\verify_prototype_foundation.py
```

Expected: `res://client` review failures are gone.

- [ ] **Step 5: Commit**

```powershell
rtk git add client\scenes\levels\prototype_level.tscn client\scenes\levels\ladder_test_level.tscn
rtk git commit -m "fix: correct client scene resource paths"
```

---

## Task 5: Restore Connected Player Physics Collision

**Files:**
- Modify: `client/scripts/player/movement/player.gd`

- [ ] **Step 1: Remove collisionless live prediction branch**

In `client/scripts/player/movement/player.gd`, replace the current `_physics_process()` body with:

```gdscript
func _physics_process(delta: float) -> void:
	if not is_local:
		return

	if _state_machine == null or _input_reader == null:
		return

	_input_reader.update_from_input(_control_enabled)
	_state_machine.transition_from_player_context()
	_state_machine.physics_update(delta)
	move_and_slide()
	_register_push_block_contacts()
	_update_player_state(false)
	_send_network_state()
	_state_machine.transition_from_player_context()
```

- [ ] **Step 2: Stop authoritative snapshots from teleporting the local `CharacterBody2D`**

Replace `apply_authoritative_snapshot()` with:

```gdscript
func apply_authoritative_snapshot(snapshot: Dictionary) -> void:
	if _prediction_controller == null:
		return
	_prediction_controller.reconcile(snapshot, _last_prediction_delta)
```

This keeps ack/reconciliation bookkeeping alive for tests and future work, but does not set `global_position` from the collisionless server simulator.

- [ ] **Step 3: Leave prediction helpers in place**

Do not delete `_create_prediction_input_packet()` or `_apply_prediction_state()` in this task. They are referenced by the client prediction contract probe and will be revisited when server-authoritative collision is designed.

- [ ] **Step 4: Run verifier and prediction probe**

Run:

```powershell
rtk python client\tests\verify_prototype_foundation.py
rtk powershell -NoProfile -Command "& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\FireBoyandWaterGirl\Se315-FireBoy-Watergirl\client' -s res://tests/client_prediction_contract_probe.gd"
```

Expected: prediction bypass failures are gone, and the existing prediction contract probe still prints `Client prediction contract probe passed.`

- [ ] **Step 5: Manual smoke check**

Run two clients against a server. Expected: connected local player uses `move_and_slide()` and collides with level terrain instead of falling through the ground.

- [ ] **Step 6: Commit**

```powershell
rtk git add client\scripts\player\movement\player.gd
rtk git commit -m "fix: keep connected player on Godot physics motor"
```

---

## Task 6: Fix Server Prediction Ack Tick

**Files:**
- Modify: `server/network_manager.gd`

- [ ] **Step 1: Use the input packet tick as ack tick**

Replace lines 173-177 in `server/network_manager.gd` with:

```gdscript
	var ack_tick := int(packet.get("t", 0))
	var snapshot := next_state.to_snapshot(ack_tick)
	rpc_id(sender_id, "receive_authoritative_player_snapshot", player_id, snapshot)
	for pid in connected_players:
		if pid != sender_id:
			rpc_id(pid, "receive_player_snapshot", player_id, snapshot, ack_tick)
```

- [ ] **Step 2: Run verifier and server parse on a non-default port**

Run:

```powershell
rtk python client\tests\verify_prototype_foundation.py
rtk powershell -NoProfile -Command "& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --path 'D:\FireBoyandWaterGirl\Se315-FireBoy-Watergirl\server' --headless --quit --port=19099"
```

Expected: ack tick failures are gone. If the server parse prints an ENet bind error, rerun with another free port and record the occupied port in the task notes.

- [ ] **Step 3: Commit**

```powershell
rtk git add server\network_manager.gd
rtk git commit -m "fix: ack server snapshots with input tick"
```

---

## Task 7: Add Start-Game Flow Evidence For P2 Waiting Room

**Files:**
- Modify: `server/network_manager.gd`
- Modify: `client/scripts/network_manager.gd`
- Modify: `client/scripts/ui/lobby_ui.gd`
- Modify: `client/scripts/ui/host_waiting_room.gd`

- [ ] **Step 1: Add server broadcast evidence**

Replace `_broadcast_game_start()` in `server/network_manager.gd` with:

```gdscript
func _broadcast_game_start() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	print("[Server] Host started game; request_sender=%d connected_players=%s" % [sender_id, str(connected_players)])
	for pid in connected_players:
		print("[Server] notify_game_start -> peer %d" % pid)
		rpc_id(pid, "notify_game_start")
```

- [ ] **Step 2: Add client receive evidence**

Replace `notify_game_start()` in `client/scripts/network_manager.gd` with:

```gdscript
@rpc("authority", "call_remote", "reliable")
func notify_game_start() -> void:
	var current_scene_path := "<none>"
	if get_tree().current_scene != null:
		current_scene_path = get_tree().current_scene.scene_file_path
	print("[Client] Game starting! peer=%d current_scene=%s" % [multiplayer.get_unique_id(), current_scene_path])
	game_started.emit()
```

- [ ] **Step 3: Report lobby scene-load failures**

Replace `_on_game_started()` in `client/scripts/ui/lobby_ui.gd` with:

```gdscript
func _on_game_started() -> void:
	print("[LobbyUI] Loading gameplay scene res://scenes/bootstrap/game.tscn")
	var error := get_tree().change_scene_to_file("res://scenes/bootstrap/game.tscn")
	if error != OK:
		printerr("[LobbyUI] Failed to load gameplay scene: %s" % error_string(error))
```

- [ ] **Step 4: Log host waiting room transition**

Replace `_on_game_started()` in `client/scripts/ui/host_waiting_room.gd` with:

```gdscript
func _on_game_started() -> void:
	print("[HostWaitingRoom] Loading gameplay scene %s" % GAME_SCENE_PATH)
	SceneLoader.load_scene(GAME_SCENE_PATH)
```

- [ ] **Step 5: Manual two-client start-game check**

Run P1 create room, P2 join, then P1 start game.

Expected logs:

```text
[Server] Host started game; request_sender=<P1 id> connected_players=[<P1 id>, <P2 id>]
[Server] notify_game_start -> peer <P1 id>
[Server] notify_game_start -> peer <P2 id>
[Client] Game starting! peer=<P1 id> current_scene=...
[Client] Game starting! peer=<P2 id> current_scene=...
```

If P2 has no client log, investigate RPC/broadcast membership next. If P2 has the client log but stays in waiting room, investigate scene load or SceneLoader next.

- [ ] **Step 6: Commit**

```powershell
rtk git add server\network_manager.gd client\scripts\network_manager.gd client\scripts\ui\lobby_ui.gd client\scripts\ui\host_waiting_room.gd
rtk git commit -m "chore: add start game flow diagnostics"
```

---

## Task 8: Decide And Resolve UI-Only Scope Drift

**Files:**
- Read: `plan.md`
- Inspect: `client/scripts/network_manager.gd`
- Inspect: `server/network_manager.gd`
- Optional modify: `client/scripts/network_manager.gd`
- Optional modify: `server/network_manager.gd`
- Optional create: `docs/superpowers/plans/2026-07-01-listen-server-lifecycle.md`

- [ ] **Step 1: Choose scope**

Choose one path before editing:

```text
Path A: Continue original UI-only plan.
Path B: Accept real listen-server as new scope and make a separate lifecycle plan.
```

- [ ] **Step 2A: If Path A, restore `host_room()` to stub contract**

In `client/scripts/network_manager.gd`, replace real server process spawning with:

```gdscript
signal room_created
signal room_creation_failed(reason: String)

func host_room(port: int = DEFAULT_PORT) -> void:
	push_warning("[NetworkManager] host_room(%d) is a UI-only contract stub; server hosting is not implemented in this task" % port)
	room_creation_failed.emit("Server hosting not yet implemented")
```

Remove helper functions that only support real process spawning:

```gdscript
func _start_server_process(port: int) -> Error:
func _get_server_project_path() -> String:
```

Do not touch `server/network_manager.gd` for UI-only cleanup beyond fixes already made in previous tasks.

- [ ] **Step 2B: If Path B, keep real listen-server and write follow-up lifecycle plan**

Create `docs/superpowers/plans/2026-07-01-listen-server-lifecycle.md` with a separate goal covering:

```text
- hosted process readiness instead of fixed 0.5s wait
- stale hosted_server_pid cleanup
- port busy handling
- process shutdown when host disconnects/exits
- role/authority behavior for host peer
- manual and automated smoke tests
```

- [ ] **Step 3: Run verifier**

```powershell
rtk python client\tests\verify_prototype_foundation.py
```

Expected: no verifier regression from whichever scope path is chosen. If Path A is chosen, update verifier expectations that currently require `OS.create_process`.

- [ ] **Step 4: Commit**

For Path A:

```powershell
rtk git add client\scripts\network_manager.gd client\tests\verify_prototype_foundation.py
rtk git commit -m "fix: restore create room ui contract"
```

For Path B:

```powershell
rtk git add docs\superpowers\plans\2026-07-01-listen-server-lifecycle.md
rtk git commit -m "docs: plan listen server lifecycle"
```

---

## Task 9: Final Verification And Godot Review

**Files:**
- Read/verify all modified files above.

- [ ] **Step 1: Run static verifier**

```powershell
rtk python client\tests\verify_prototype_foundation.py
```

Expected: pass.

- [ ] **Step 2: Run Godot client parse**

```powershell
rtk powershell -NoProfile -Command "& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --path 'D:\FireBoyandWaterGirl\Se315-FireBoy-Watergirl\client' --headless --quit"
```

Expected: exit 0, no GDScript parse errors.

- [ ] **Step 3: Run Godot server parse on a free port**

```powershell
rtk powershell -NoProfile -Command "& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --path 'D:\FireBoyandWaterGirl\Se315-FireBoy-Watergirl\server' --headless --quit --port=19099"
```

Expected: exit 0. If port 19099 is busy, rerun with another free port and record it.

- [ ] **Step 4: Run prediction probe**

```powershell
rtk powershell -NoProfile -Command "& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\FireBoyandWaterGirl\Se315-FireBoy-Watergirl\client' -s res://tests/client_prediction_contract_probe.gd"
```

Expected: `Client prediction contract probe passed.`

- [ ] **Step 5: Manual two-client smoke test**

Use the user repro:

```text
1. Start/create room as P1.
2. Connect P2.
3. Start game.
4. Confirm both clients print [Client] Game starting!
5. Confirm both clients leave waiting/lobby and load res://scenes/bootstrap/game.tscn.
6. Confirm local connected player collides with floor/world and no longer falls through terrain.
```

- [ ] **Step 6: Run GodotPrompter code review**

Load `godot-prompter:godot-code-review` and review the final diff against:

```text
- CharacterBody2D movement calls move_and_slide() after velocity updates.
- Area2D gem mask scans Player layer.
- RigidBody2D push block mask scans intended layers.
- RPC modes remain reliable for start-game events.
- No scene path uses res://client inside client project.
- Signal signatures match connected methods.
```

- [ ] **Step 7: Final commit**

Only if any final verification-only changes were made:

```powershell
rtk git add <changed-files>
rtk git commit -m "test: verify review fixes"
```

---

## Self-Review

- Spec coverage: every handoff review finding maps to a task: gem compile Task 2, collision masks Tasks 2-3, bad resource paths Task 4, connected collision bypass Task 5, ack tick Task 6, P2 waiting-room evidence Task 7, UI scope drift Task 8, final parse/check/review Task 9.
- Placeholder scan: no `TBD`, no "add appropriate", no "similar to". The one decision point in Task 8 has concrete Path A and Path B steps.
- Type consistency: `CollectibleGem.collected(gem: CollectibleGem, player: PrototypePlayer)` matches `GemManager._on_gem_collected(gem: CollectibleGem, _player: PrototypePlayer)`. Server ack uses input packet `"t"`, matching `InputPacket.create(...)` and `ClientPredictionController.predict(...)`.

