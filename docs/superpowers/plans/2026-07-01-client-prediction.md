# Client Prediction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add phase-one client prediction for horizontal movement and jump, backed by a shared movement simulator used by both client and server.

**Architecture:** Create a data-only movement core under `shared/` and bridge it into the existing Godot player, networking, and server code. The client predicts local movement and buffers inputs; the server validates the same input stream with the shared simulator and returns authoritative snapshots; remote players continue using snapshot interpolation.

**Tech Stack:** Godot 4.x, typed GDScript, ENet RPC, existing `client/`, `server/`, and `shared/` project layout.

---

## File Structure

- Create `shared/scripts/multiplayer/movement/player_movement_config.gd`: numeric tuning values for phase-one movement.
- Create `shared/scripts/multiplayer/movement/player_movement_state.gd`: plain movement state with `position`, `velocity`, `on_floor`, and duplication helpers.
- Create `shared/scripts/multiplayer/movement/player_movement_simulator.gd`: deterministic horizontal+jump step function shared by client and server.
- Create `client/scripts/multiplayer/prediction/client_prediction_controller.gd`: local input/state buffers, prediction, reconciliation, and replay.
- Modify `shared/packets/input_packet.gd`: keep packet creation as the canonical input contract and add typed helpers if useful.
- Modify `client/scripts/network_manager.gd`: add input send RPC and authoritative snapshot receive signal.
- Modify `server/network_manager.gd`: add authoritative movement state per peer, process input packets, return snapshots.
- Modify `client/scripts/player/movement/player.gd`: delegate connected local horizontal+jump prediction to `ClientPredictionController`.
- Modify `client/scripts/core/game_manager/game_manager.gd`: route local authoritative snapshots to the local player and keep remote snapshots on `RemotePlayer`.
- Modify `client/tests/verify_prototype_foundation.py`: align path checks with the new `shared/` layout and add prediction contract checks.
- Add or update probe tests under `client/tests/` for simulator and reconciliation contracts.

GodotPrompter skills to load during implementation: `using-godot-prompter`, `multiplayer-sync`, `player-controller`, `input-handling`, `godot-testing`, and final `godot-code-review`.

---

### Task 1: Stabilize Verification After Shared Refactor

**Files:**
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Update required path checks for shared gameplay files**

Replace gameplay entries in `REQUIRED_FILES` that moved out of `client/` with repo-root shared paths. Use this shape:

```python
REQUIRED_FILES = [
	"project.godot",
	"scenes/bootstrap/game.tscn",
	"scenes/bootstrap/game_real.tscn",
	"scenes/players/fireboy.tscn",
	"scenes/players/watergirl.tscn",
	"scenes/levels/prototype_level.tscn",
	"scenes/levels/real_level_blank.tscn",
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
	"scripts/ui/host_waiting_room.gd",
	"scripts/ui/menus/pause_menu.gd",
	"scenes/gameplay/objects/ladder.tscn",
	"scenes/levels/ladder_test_level.tscn",
	"docs/level_workflow.md",
	"docs/player_state_machine.md",
	"tests/player_state_machine_probe.gd",
	"tests/button_ladder_interactions_probe.gd",
	"tests/precision_player_movement_probe.gd",
]

REQUIRED_REPO_FILES = [
	"shared/scripts/gameplay/levels/prototype_level.gd",
	"shared/scripts/gameplay/hazards/hazard_zone.gd",
	"shared/scripts/gameplay/doors/exit_door.gd",
	"shared/scripts/gameplay/collectibles/collectible_gem.gd",
	"shared/scripts/gameplay/collectibles/gem_manager.gd",
	"shared/scripts/gameplay/objects/push_block.gd",
	"shared/scripts/gameplay/objects/ladder.gd",
	"shared/scenes/gameplay/collectibles/collectible_gem.tscn",
	"shared/scenes/gameplay/objects/push_block.tscn",
]
```

- [ ] **Step 2: Extend `check_required_files` to check repo-level files**

```python
def check_required_files(failures: list[str]) -> None:
	for relative_path in REQUIRED_FILES:
		require((CLIENT_ROOT / relative_path).exists(), f"Missing {relative_path}", failures)
	for relative_path in REQUIRED_REPO_FILES:
		require((REPO_ROOT / relative_path).exists(), f"Missing {relative_path}", failures)
```

- [ ] **Step 3: Update scene/script contract paths for shared files**

In collision and script checks, read moved files from `REPO_ROOT / "shared" / ...` instead of `CLIENT_ROOT / "scripts" / "gameplay" / ...`. Keep client-only objects, such as `client/scenes/gameplay/objects/ladder.tscn`, under `CLIENT_ROOT`.

```python
SHARED_SCRIPT_SNIPPETS = {
	"shared/scripts/gameplay/objects/ladder.gd": ["LADDER_COLLISION_LAYER: int = 8", "LADDER_COLLISION_MASK: int = 0"],
	"shared/scripts/gameplay/objects/pressure_button.gd": ["PRESSURE_BUTTON_COLLISION_LAYER: int = 128", "PRESSURE_BUTTON_COLLISION_MASK: int = 2"],
	"shared/scripts/gameplay/objects/push_block.gd": ["PUSH_BLOCK_COLLISION_LAYER: int = 4", "PUSH_BLOCK_COLLISION_MASK: int = 3", "PUSH_DETECTOR_COLLISION_MASK: int = 2"],
	"shared/scripts/gameplay/objects/bridge_platform.gd": ["WORLD_COLLISION_LAYER: int = 1", "WORLD_COLLISION_MASK: int = 6"],
	"shared/scripts/gameplay/collectibles/collectible_gem.gd": ["GEM_COLLISION_LAYER: int = 32", "GEM_COLLISION_MASK: int = 2"],
	"shared/scripts/gameplay/hazards/hazard_zone.gd": ["HAZARD_COLLISION_LAYER: int = 16", "HAZARD_COLLISION_MASK: int = 2"],
	"shared/scripts/gameplay/doors/exit_door.gd": ["EXIT_COLLISION_LAYER: int = 64", "EXIT_COLLISION_MASK: int = 2"],
}
```

- [ ] **Step 4: Run verification and confirm the shared-path failure is gone**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: either `Prototype foundation verification passed.` or a smaller failure list unrelated to missing moved shared files.

- [ ] **Step 5: Commit**

```powershell
git add client\tests\verify_prototype_foundation.py
git commit -m "test: align verification with shared gameplay paths"
```

---

### Task 2: Add Shared Movement Simulator

**Files:**
- Create: `shared/scripts/multiplayer/movement/player_movement_config.gd`
- Create: `shared/scripts/multiplayer/movement/player_movement_state.gd`
- Create: `shared/scripts/multiplayer/movement/player_movement_simulator.gd`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Add contract checks for the new shared movement files**

Add these paths to `REQUIRED_REPO_FILES`:

```python
"shared/scripts/multiplayer/movement/player_movement_config.gd",
"shared/scripts/multiplayer/movement/player_movement_state.gd",
"shared/scripts/multiplayer/movement/player_movement_simulator.gd",
```

- [ ] **Step 2: Run verification to confirm it fails before implementation**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: FAIL listing the three missing movement files.

- [ ] **Step 3: Create `player_movement_config.gd`**

```gdscript
class_name PlayerMovementConfig
extends RefCounted

var speed: float = 110.0
var jump_velocity: float = -236.0
var gravity: float = 450.0
var acceleration: float = 1500.0
var deceleration: float = 1250.0
var air_acceleration: float = 1000.0
var air_deceleration: float = 420.0
var max_fall_speed: float = 330.0

static func create_default() -> PlayerMovementConfig:
	return PlayerMovementConfig.new()
```

- [ ] **Step 4: Create `player_movement_state.gd`**

```gdscript
class_name PlayerMovementState
extends RefCounted

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var on_floor: bool = false

func duplicate_state() -> PlayerMovementState:
	var state := PlayerMovementState.new()
	state.position = position
	state.velocity = velocity
	state.on_floor = on_floor
	return state

func to_snapshot(ack_tick: int) -> Dictionary:
	return {
		"ack_tick": ack_tick,
		"pos": position,
		"vel": velocity,
		"on_floor": on_floor,
	}

static func from_snapshot(snapshot: Dictionary) -> PlayerMovementState:
	var state := PlayerMovementState.new()
	state.position = snapshot.get("pos", Vector2.ZERO)
	state.velocity = snapshot.get("vel", Vector2.ZERO)
	state.on_floor = snapshot.get("on_floor", false)
	return state
```

- [ ] **Step 5: Create `player_movement_simulator.gd`**

```gdscript
class_name PlayerMovementSimulator
extends RefCounted

static func step(state: PlayerMovementState, input_packet: Dictionary, config: PlayerMovementConfig, delta: float) -> PlayerMovementState:
	var next := state.duplicate_state()
	var direction: float = clampf(float(input_packet.get("x", 0.0)), -1.0, 1.0)
	var jump_pressed: bool = bool(input_packet.get("j", false))
	var horizontal_accel: float = config.acceleration if next.on_floor else config.air_acceleration
	var horizontal_decel: float = config.deceleration if next.on_floor else config.air_deceleration

	if direction != 0.0:
		next.velocity.x = move_toward(next.velocity.x, direction * config.speed, horizontal_accel * delta)
	else:
		next.velocity.x = move_toward(next.velocity.x, 0.0, horizontal_decel * delta)

	if jump_pressed and next.on_floor:
		next.velocity.y = config.jump_velocity
		next.on_floor = false

	if not next.on_floor:
		next.velocity.y = minf(next.velocity.y + config.gravity * delta, config.max_fall_speed)

	next.position += next.velocity * delta
	return next
```

- [ ] **Step 6: Run verification**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: PASS for the new movement file existence checks.

- [ ] **Step 7: Commit**

```powershell
git add shared\scripts\multiplayer\movement client\tests\verify_prototype_foundation.py
git commit -m "feat: add shared player movement simulator"
```

---

### Task 3: Add Authoritative Input RPC Contract

**Files:**
- Modify: `client/scripts/network_manager.gd`
- Modify: `server/network_manager.gd`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Add verification snippets for new RPC names**

Add checks in `check_scripts`:

```python
for snippet in [
	"signal authoritative_player_snapshot_received(player_id: int, snapshot: Dictionary)",
	"func send_player_input(packet: Dictionary) -> void:",
	"rpc_id(1, \"receive_player_input\", multiplayer.get_unique_id(), packet)",
	"func receive_authoritative_player_snapshot(player_id: int, snapshot: Dictionary) -> void:",
]:
	require(snippet in network_manager_text, f"Network manager prediction contract missing {snippet}", failures)

for snippet in [
	"var _authoritative_states: Dictionary = {}",
	"func receive_player_input(player_id: int, packet: Dictionary) -> void:",
	"PlayerMovementSimulator.step",
	"rpc_id(sender_id, \"receive_authoritative_player_snapshot\", player_id, snapshot)",
]:
	require(snippet in server_network_manager_text, f"Server prediction contract missing {snippet}", failures)
```

- [ ] **Step 2: Run verification to confirm it fails**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: FAIL listing missing prediction contract snippets.

- [ ] **Step 3: Add client RPC methods**

Add to `client/scripts/network_manager.gd`:

```gdscript
signal authoritative_player_snapshot_received(player_id: int, snapshot: Dictionary)

func send_player_input(packet: Dictionary) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "receive_player_input", multiplayer.get_unique_id(), packet)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_authoritative_player_snapshot(player_id: int, snapshot: Dictionary) -> void:
	authoritative_player_snapshot_received.emit(player_id, snapshot)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func receive_player_input(_player_id: int, _packet: Dictionary) -> void:
	pass
```

- [ ] **Step 4: Add server authoritative state and input processing**

Add near the top of `server/network_manager.gd`:

```gdscript
const PlayerMovementConfigScript: Script = preload("res://shared/scripts/multiplayer/movement/player_movement_config.gd")
const PlayerMovementStateScript: Script = preload("res://shared/scripts/multiplayer/movement/player_movement_state.gd")
const PlayerMovementSimulatorScript: Script = preload("res://shared/scripts/multiplayer/movement/player_movement_simulator.gd")

var _authoritative_states: Dictionary = {}
var _movement_config: PlayerMovementConfig = PlayerMovementConfig.create_default()
var _server_tick_delta: float = 1.0 / 60.0
```

Add on peer connect and disconnect:

```gdscript
func _on_peer_connected(id: int) -> void:
	connected_players.append(id)
	_authoritative_states[id] = PlayerMovementState.new()
	print("[Server] Player connected: %d (total: %d)" % [id, connected_players.size()])
	# keep the existing role assignment body after this line

func _on_peer_disconnected(id: int) -> void:
	connected_players.erase(id)
	player_roles.erase(id)
	_authoritative_states.erase(id)
	# keep the existing disconnect body after this line
```

Add RPCs:

```gdscript
@rpc("any_peer", "call_remote", "unreliable_ordered")
func receive_player_input(player_id: int, packet: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != player_id:
		return
	if not _authoritative_states.has(player_id):
		_authoritative_states[player_id] = PlayerMovementState.new()

	var state: PlayerMovementState = _authoritative_states[player_id]
	var next_state: PlayerMovementState = PlayerMovementSimulator.step(state, packet, _movement_config, _server_tick_delta)
	_authoritative_states[player_id] = next_state

	var tick := int(packet.get("t", 0))
	var snapshot := next_state.to_snapshot(tick)
	rpc_id(sender_id, "receive_authoritative_player_snapshot", player_id, snapshot)
	for pid in connected_players:
		if pid != sender_id:
			rpc_id(pid, "receive_player_snapshot", player_id, snapshot, tick)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_authoritative_player_snapshot(_player_id: int, _snapshot: Dictionary) -> void:
	pass
```

- [ ] **Step 5: Run verification**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: PASS for prediction RPC contract checks.

- [ ] **Step 6: Commit**

```powershell
git add client\scripts\network_manager.gd server\network_manager.gd client\tests\verify_prototype_foundation.py
git commit -m "feat: add authoritative input rpc contract"
```

---

### Task 4: Add Client Prediction Controller

**Files:**
- Create: `client/scripts/multiplayer/prediction/client_prediction_controller.gd`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Add verification for controller file and core methods**

Add to `REQUIRED_FILES`:

```python
"scripts/multiplayer/prediction/client_prediction_controller.gd",
```

Add snippet checks:

```python
prediction_text = read(CLIENT_ROOT / "scripts" / "multiplayer" / "prediction" / "client_prediction_controller.gd")
for snippet in [
	"class_name ClientPredictionController",
	"const MAX_PENDING_INPUTS: int = 128",
	"func predict(packet: Dictionary, delta: float) -> PlayerMovementState:",
	"func reconcile(snapshot: Dictionary, delta: float) -> PlayerMovementState:",
	"func _replay_pending_inputs(delta: float) -> PlayerMovementState:",
]:
	require(snippet in prediction_text, f"Client prediction controller missing {snippet}", failures)
```

- [ ] **Step 2: Run verification to confirm it fails**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: FAIL listing missing `client_prediction_controller.gd`.

- [ ] **Step 3: Create controller**

```gdscript
class_name ClientPredictionController
extends RefCounted

const MAX_PENDING_INPUTS: int = 128
const SNAP_THRESHOLD: float = 12.0
const IGNORE_THRESHOLD: float = 2.0

var config: PlayerMovementConfig = PlayerMovementConfig.create_default()
var current_state: PlayerMovementState = PlayerMovementState.new()
var last_ack_tick: int = -1
var pending_inputs: Array[Dictionary] = []
var predicted_states: Dictionary = {}

func reset(position: Vector2, velocity: Vector2, on_floor: bool) -> void:
	current_state.position = position
	current_state.velocity = velocity
	current_state.on_floor = on_floor
	last_ack_tick = -1
	pending_inputs.clear()
	predicted_states.clear()

func predict(packet: Dictionary, delta: float) -> PlayerMovementState:
	current_state = PlayerMovementSimulator.step(current_state, packet, config, delta)
	pending_inputs.append(packet)
	predicted_states[int(packet.get("t", 0))] = current_state.duplicate_state()
	_trim_buffers()
	return current_state

func reconcile(snapshot: Dictionary, delta: float) -> PlayerMovementState:
	var ack_tick := int(snapshot.get("ack_tick", -1))
	if ack_tick <= last_ack_tick:
		return current_state

	last_ack_tick = ack_tick
	var server_state := PlayerMovementState.from_snapshot(snapshot)
	var predicted: PlayerMovementState = predicted_states.get(ack_tick, current_state)
	var error := predicted.position.distance_to(server_state.position)

	_drop_acknowledged_inputs(ack_tick)
	for tick in predicted_states.keys():
		if int(tick) <= ack_tick:
			predicted_states.erase(tick)

	if error < IGNORE_THRESHOLD:
		return current_state

	current_state = server_state
	if error >= SNAP_THRESHOLD:
		return _replay_pending_inputs(delta)

	current_state.position = current_state.position.lerp(predicted.position, 0.5)
	current_state.velocity = server_state.velocity
	return _replay_pending_inputs(delta)

func _replay_pending_inputs(delta: float) -> PlayerMovementState:
	for packet in pending_inputs:
		current_state = PlayerMovementSimulator.step(current_state, packet, config, delta)
		predicted_states[int(packet.get("t", 0))] = current_state.duplicate_state()
	return current_state

func _drop_acknowledged_inputs(ack_tick: int) -> void:
	pending_inputs = pending_inputs.filter(func(packet: Dictionary) -> bool:
		return int(packet.get("t", 0)) > ack_tick
	)

func _trim_buffers() -> void:
	while pending_inputs.size() > MAX_PENDING_INPUTS:
		var removed := pending_inputs.pop_front()
		predicted_states.erase(int(removed.get("t", 0)))
```

- [ ] **Step 4: Run verification**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: PASS for controller file and method checks.

- [ ] **Step 5: Commit**

```powershell
git add client\scripts\multiplayer\prediction\client_prediction_controller.gd client\tests\verify_prototype_foundation.py
git commit -m "feat: add client prediction controller"
```

---

### Task 5: Integrate Prediction Into Local Player

**Files:**
- Modify: `client/scripts/player/movement/player.gd`
- Modify: `client/scripts/core/game_manager/game_manager.gd`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Add verification snippets for player integration**

Add checks:

```python
for snippet in [
	"var _prediction_controller: ClientPredictionController",
	"func apply_authoritative_snapshot(snapshot: Dictionary) -> void:",
	"NetworkManager.send_player_input(input_packet)",
	"_prediction_controller.predict(input_packet, delta)",
]:
	require(snippet in player_text, f"Player prediction integration missing {snippet}", failures)
```

- [ ] **Step 2: Run verification to confirm it fails**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: FAIL listing player prediction integration snippets.

- [ ] **Step 3: Add prediction fields and initialization to `PrototypePlayer`**

Add fields:

```gdscript
var _prediction_controller: ClientPredictionController
var _last_prediction_delta: float = 1.0 / 60.0
```

Initialize after `_configure_components()` in `_ready()`:

```gdscript
_prediction_controller = ClientPredictionController.new()
_prediction_controller.reset(global_position, velocity, is_on_floor())
```

- [ ] **Step 4: Add helper to create input packets**

```gdscript
func _create_prediction_input_packet() -> Dictionary:
	return InputPacket.create(
		NetworkManager.current_tick,
		_input_reader.horizontal_direction if _input_reader != null else 0.0,
		_input_reader.jump_just_pressed if _input_reader != null else false
	)
```

- [ ] **Step 5: Bridge predicted state back to the player**

```gdscript
func _apply_prediction_state(state: PlayerMovementState) -> void:
	global_position = state.position
	velocity = state.velocity
```

- [ ] **Step 6: Use prediction only for connected local players**

In `_physics_process(delta)`, after `_input_reader.update_from_input(_control_enabled)` and before the normal state-machine movement path, add:

```gdscript
if NetworkManager.is_connected_to_server() and _prediction_controller != null:
	_last_prediction_delta = delta
	var input_packet := _create_prediction_input_packet()
	var predicted_state := _prediction_controller.predict(input_packet, delta)
	_apply_prediction_state(predicted_state)
	NetworkManager.send_player_input(input_packet)
	_update_player_state(false)
	_send_network_state()
	return
```

- [ ] **Step 7: Add authoritative snapshot hook**

```gdscript
func apply_authoritative_snapshot(snapshot: Dictionary) -> void:
	if _prediction_controller == null:
		return
	var reconciled_state := _prediction_controller.reconcile(snapshot, _last_prediction_delta)
	_apply_prediction_state(reconciled_state)
```

- [ ] **Step 8: Route local authoritative snapshots in `GameManager`**

Connect in `_ready()`:

```gdscript
NetworkManager.authoritative_player_snapshot_received.connect(_on_authoritative_player_snapshot_received)
```

Add handler:

```gdscript
func _on_authoritative_player_snapshot_received(player_id: int, snapshot: Dictionary) -> void:
	if not is_instance_valid(_player):
		return
	var my_id := multiplayer.get_unique_id() if NetworkManager.is_connected_to_server() else 1
	if player_id != my_id:
		return
	if _player.has_method("apply_authoritative_snapshot"):
		_player.call("apply_authoritative_snapshot", snapshot)
```

- [ ] **Step 9: Run verification**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: PASS for prediction integration snippets.

- [ ] **Step 10: Commit**

```powershell
git add client\scripts\player\movement\player.gd client\scripts\core\game_manager\game_manager.gd client\tests\verify_prototype_foundation.py
git commit -m "feat: wire client prediction into local player"
```

---

### Task 6: Add Prediction Probe Coverage

**Files:**
- Create: `client/tests/client_prediction_contract_probe.gd`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Add probe to required files**

```python
"tests/client_prediction_contract_probe.gd",
```

- [ ] **Step 2: Create probe script**

```gdscript
extends SceneTree

func _init() -> void:
	var config := PlayerMovementConfig.create_default()
	var state := PlayerMovementState.new()
	state.on_floor = true

	var right_input := InputPacket.create(1, 1.0, false)
	var moved := PlayerMovementSimulator.step(state, right_input, config, 1.0 / 60.0)
	assert(moved.position.x > state.position.x)

	var jump_input := InputPacket.create(2, 0.0, true)
	var jumped := PlayerMovementSimulator.step(moved, jump_input, config, 1.0 / 60.0)
	assert(jumped.velocity.y < 0.0)
	assert(not jumped.on_floor)

	var controller := ClientPredictionController.new()
	controller.reset(Vector2.ZERO, Vector2.ZERO, true)
	controller.predict(InputPacket.create(1, 1.0, false), 1.0 / 60.0)
	controller.predict(InputPacket.create(2, 1.0, false), 1.0 / 60.0)

	var correction := {
		"ack_tick": 1,
		"pos": Vector2.ZERO,
		"vel": Vector2.ZERO,
		"on_floor": true,
	}
	controller.reconcile(correction, 1.0 / 60.0)
	assert(controller.last_ack_tick == 1)
	assert(controller.pending_inputs.size() == 1)

	print("Client prediction contract probe passed.")
	quit(0)
```

- [ ] **Step 3: Run static verification**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: PASS for probe file existence.

- [ ] **Step 4: Run Godot probe when an executable is available**

Run from `client/` when `godot` is installed or available by absolute path:

```powershell
godot --headless --path client -s res://tests/client_prediction_contract_probe.gd
```

Expected: `Client prediction contract probe passed.`

- [ ] **Step 5: Commit**

```powershell
git add client\tests\client_prediction_contract_probe.gd client\tests\verify_prototype_foundation.py
git commit -m "test: add client prediction contract probe"
```

---

### Task 7: Final Verification And Godot Review

**Files:**
- Review only unless verification reveals a root cause.

- [ ] **Step 1: Run repository structural verification**

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: `Prototype foundation verification passed.`

- [ ] **Step 2: Run Godot parse checks if available**

Check executable:

```powershell
Get-Command godot -ErrorAction SilentlyContinue
Get-Command godot4 -ErrorAction SilentlyContinue
```

If available:

```powershell
godot --headless --path client --quit
godot --headless --path server --quit
```

Expected: both commands exit with code `0`.

- [ ] **Step 3: Use GodotPrompter code review**

Load `godot-prompter:godot-code-review` and review:

- shared simulator has no Node or scene dependency.
- prediction is local-player only.
- remote interpolation path is unchanged.
- pending input buffer is bounded.
- server validates sender id before processing input.
- ladder, push block, gem, hazard, and puzzle systems are not included in prediction phase one.

- [ ] **Step 4: Commit any verification-only fixes**

If verification exposed a root cause and a fix was made:

```powershell
git add <fixed-files>
git commit -m "fix: stabilize client prediction integration"
```

If no fix was made, do not create an empty commit.

---

## Self-Review

- Spec coverage: The plan covers shared simulator, client input buffering, server authoritative snapshots, local reconciliation, remote interpolation preservation, and phase-one scope exclusion for ladder/push/gem/hazard/puzzle.
- Placeholder scan: The plan avoids unspecified implementation steps; every code-producing step includes concrete snippets and paths.
- Type consistency: `PlayerMovementConfig`, `PlayerMovementState`, `PlayerMovementSimulator`, `ClientPredictionController`, `send_player_input`, and `receive_authoritative_player_snapshot` are introduced before use.
- Known verification constraint: `godot` and `godot4` were not present in PATH during planning. Godot headless commands are included as conditional verification steps.
