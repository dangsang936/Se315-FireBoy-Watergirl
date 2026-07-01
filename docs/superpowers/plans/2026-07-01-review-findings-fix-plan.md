# Review Findings Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the runtime, multiplayer, shared-resource, and test-suite defects found in the 2026-07-01 code review.

**Architecture:** Preserve the existing Godot 4.x client/server/shared split. Fix portability first so `res://shared/...` resolves from both Godot projects, then make tests trustworthy, then repair gameplay RPC/prediction/gem-gate behavior with focused changes.

**Tech Stack:** Godot 4.6.2, typed GDScript, ENet multiplayer RPCs, existing headless probe scripts, Python contract test.

---

## File Structure

- `client/shared`, `server/shared`: restore portable shared links or otherwise ensure `res://shared/...` exists inside both Godot projects.
- `client/tests/verify_prototype_foundation.py`: add checks that shared paths resolve to the repo `shared/` directory and that renamed resources/tests stay aligned.
- `client/tests/prototype_runtime_probe.gd`: update stale resource paths and `GameManager.ManagerState` enum names.
- `client/tests/player_state_machine_probe.gd`, `client/tests/precision_player_movement_probe.gd`, `client/tests/button_ladder_interactions_probe.gd`: make probes fail non-zero when script compilation or scene instantiation fails.
- `client/scripts/core/game_manager/game_manager.gd`: replace compile-time `NetworkManager` singleton references with test-safe `/root/NetworkManager` lookup; apply authoritative snapshots to the local player.
- `client/scripts/player/movement/player.gd`: replace compile-time `NetworkManager` singleton references with test-safe lookup; wire input packet send, prediction record, and reconciliation application.
- `client/scripts/network_manager.gd`, `server/network_manager.gd`: keep RPC names/modes aligned and initialize server authoritative state from the first client movement packet.
- `shared/scripts/gameplay/collectibles/collectible_gem.gd`, `shared/scripts/gameplay/collectibles/gem_manager.gd`, `shared/scripts/gameplay/objects/push_block.gd`: fix `GameplayRpc` autoload lookup and gem filtering.

---

### Task 1: Restore Shared Resource Portability

**Files:**
- Modify/restore: `client/shared`
- Modify/restore: `server/shared`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Confirm the failure condition**

Run:

```powershell
git status --short client/shared server/shared
git diff -- client/shared server/shared
```

Expected before fix: both paths are reported as deleted, while project files still reference `res://shared/...`.

- [ ] **Step 2: Restore portable shared links**

Replace the deleted tracked links with portable links to the repo `shared/` directory. On Windows, use junctions locally if symlink creation is blocked, but do not commit deleted paths.

Run:

```powershell
git restore -- client/shared server/shared
```

If restored links still point to the old absolute `C:/Project/WaterFire/shared`, replace their contents/targets with relative `../shared` for both projects.

- [ ] **Step 3: Add a contract check**

In `client/tests/verify_prototype_foundation.py`, add this helper:

```python
def check_shared_project_links(failures: list[str]) -> None:
	client_shared = CLIENT_ROOT / "shared"
	server_shared = REPO_ROOT / "server" / "shared"
	expected = (REPO_ROOT / "shared").resolve()
	for label, path in [("client/shared", client_shared), ("server/shared", server_shared)]:
		require(path.exists(), f"Missing {label}; res://shared paths will not resolve", failures)
		if path.exists():
			require(path.resolve() == expected, f"{label} must resolve to {expected}", failures)
```

Call it from `main()` before scene/script checks:

```python
check_shared_project_links(failures)
```

- [ ] **Step 4: Verify**

Run:

```powershell
python client/tests/verify_prototype_foundation.py
git status --short client/shared server/shared
```

Expected: Python check passes; `client/shared` and `server/shared` are no longer deleted.

---

### Task 2: Make Runtime Probes Compile Against Current Names and Paths

**Files:**
- Modify: `client/tests/prototype_runtime_probe.gd`

- [ ] **Step 1: Update stale collectible preload**

Change:

```gdscript
const GEM_SCENE: PackedScene = preload("res://scenes/gameplay/collectibles/collectible_gem.tscn")
```

to:

```gdscript
const GEM_SCENE: PackedScene = preload("res://shared/scenes/gameplay/collectibles/collectible_gem.tscn")
```

- [ ] **Step 2: Update GameManager enum references**

Replace all `GameManager.GameState` references with `GameManager.ManagerState`.

Example change:

```gdscript
var state: GameManager.ManagerState = game.get("_state") as GameManager.ManagerState
var state_name: String = GameManager.ManagerState.keys()[state]
_require(state == GameManager.ManagerState.PLAYING, "Game should stay playable.")
```

- [ ] **Step 3: Verify the probe now reaches behavior failures instead of parse failures**

Run:

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/prototype_runtime_probe.gd
```

Expected: no `Parse Error: Preload file ... collectible_gem.tscn does not exist`; no `GameManager.GameState` parse errors.

---

### Task 3: Make NetworkManager Access Test-Safe

**Files:**
- Modify: `client/scripts/core/game_manager/game_manager.gd`
- Modify: `client/scripts/player/movement/player.gd`

- [ ] **Step 1: Add a typed lookup helper to GameManager**

In `client/scripts/core/game_manager/game_manager.gd`, add:

```gdscript
func _network_manager() -> Node:
	return get_node_or_null("/root/NetworkManager")
```

Replace direct `NetworkManager` references in `game_manager.gd` with local guarded access. Example for `_ready()`:

```gdscript
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud.restart_requested.connect(_on_restart_requested)
	_hud.resume_requested.connect(_resume_game)

	var network_manager := _network_manager()
	if network_manager != null:
		network_manager.peer_disconnected.connect(_on_peer_disconnected)
		network_manager.disconnected_from_server.connect(_on_disconnected_from_server)
		network_manager.remote_player_snapshot_received.connect(_on_remote_snapshot_received)
		network_manager.gem_collected_received.connect(_on_gem_collected_received)
		network_manager.player_failed_received.connect(_on_player_failed_received)
		network_manager.level_completed_received.connect(_on_level_completed_received)
		network_manager.restart_level_received.connect(_on_restart_level_received)
		network_manager.role_assigned.connect(_on_role_assigned)
		network_manager.player_list_updated.connect(_on_player_list_updated)
		network_manager.authoritative_player_snapshot_received.connect(_on_authoritative_player_snapshot_received)

	if network_manager != null and network_manager.call("is_connected_to_server") and int(network_manager.get("my_role")) != -1:
		_load_level()
	else:
		_show_connect_ui()
```

Use the same local `network_manager` pattern for restart, load, remote spawn, and authoritative snapshot handlers.

- [ ] **Step 2: Add a lookup helper to PrototypePlayer**

In `client/scripts/player/movement/player.gd`, add:

```gdscript
func _network_manager() -> Node:
	return get_node_or_null("/root/NetworkManager")
```

Replace direct `NetworkManager` reads/calls with guarded access. Example:

```gdscript
func _send_network_state() -> void:
	var network_manager := _network_manager()
	if network_manager == null or not bool(network_manager.call("is_connected_to_server")):
		return
	# keep existing snapshot construction
	network_manager.call("send_snapshot", snapshot, int(network_manager.get("current_tick")))
```

- [ ] **Step 3: Verify compile errors are gone**

Run:

```powershell
rg -n "\bNetworkManager\b" client/scripts/core/game_manager/game_manager.gd client/scripts/player/movement/player.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/player_state_machine_probe.gd
```

Expected: `rg` finds no direct `NetworkManager` identifier in the two gameplay scripts; probe no longer logs `Compile Error: Identifier not found: NetworkManager`.

---

### Task 4: Make Godot Probe Failures Trustworthy

**Files:**
- Modify: `client/tests/prototype_runtime_probe.gd`
- Modify: `client/tests/player_state_machine_probe.gd`
- Modify: `client/tests/precision_player_movement_probe.gd`
- Modify: `client/tests/button_ladder_interactions_probe.gd`

- [ ] **Step 1: Add a strict require helper to each probe**

Ensure each probe stores failures and exits non-zero:

```gdscript
var _failures: Array[String] = []

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _finish() -> void:
	if _failures.is_empty():
		print("%s passed." % get_script().resource_path.get_file().get_basename())
		quit(0)
		return
	for failure in _failures:
		printerr(failure)
	quit(1)
```

- [ ] **Step 2: Guard scene instantiation**

Where a scene is instantiated and cast, immediately require it before using it:

```gdscript
var player := PLAYER_SCENE.instantiate() as PrototypePlayer
_require(player != null, "PLAYER_SCENE must instantiate PrototypePlayer.")
if player == null:
	_finish()
	return
```

- [ ] **Step 3: Verify probes do not print pass after script errors**

Run:

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/player_state_machine_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/precision_player_movement_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/button_ladder_interactions_probe.gd
```

Expected: if a player or scene is `null`, command exits `1`; no misleading `passed` line.

---

### Task 5: Fix GameplayRpc Autoload Lookup

**Files:**
- Modify: `shared/scripts/gameplay/collectibles/collectible_gem.gd`
- Modify: `shared/scripts/gameplay/collectibles/gem_manager.gd`
- Modify: `shared/scripts/gameplay/objects/push_block.gd`

- [ ] **Step 1: Replace wrong autoload path**

In all three files, change:

```gdscript
var rpc_node = get_node_or_null("/root/GameplayRPC")
```

to:

```gdscript
var rpc_node = get_node_or_null("/root/GameplayRpc")
```

- [ ] **Step 2: Add a fallback only if needed for old scenes**

If any old local scene still uses the uppercase autoload name during manual testing, use:

```gdscript
var rpc_node := get_node_or_null("/root/GameplayRpc")
if rpc_node == null:
	rpc_node = get_node_or_null("/root/GameplayRPC")
```

Use the fallback consistently in the three touched files.

- [ ] **Step 3: Verify**

Run:

```powershell
rg -n "/root/GameplayRPC" shared/scripts
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --quit
```

Expected: no stale uppercase-only lookup remains; Godot client project loads without script errors.

---

### Task 6: Wire Local Input Prediction and Authoritative Reconciliation

**Files:**
- Modify: `client/scripts/player/movement/player.gd`
- Modify: `client/scripts/network_manager.gd`
- Modify: `server/network_manager.gd`
- Test: `client/tests/client_prediction_contract_probe.gd`

- [ ] **Step 1: Send input packets from the local player**

In `client/scripts/player/movement/player.gd`, update `_physics_process()` so it records delta and sends a compact movement packet once per physics tick after input is read:

```gdscript
func _physics_process(delta: float) -> void:
	if not is_local:
		return

	if _state_machine == null or _input_reader == null:
		return

	_last_prediction_delta = delta
	_input_reader.update_from_input(_control_enabled)
	var prediction_packet := _create_prediction_input_packet()
	_send_prediction_input(prediction_packet)
	_state_machine.transition_from_player_context()
	_state_machine.physics_update(delta)
	move_and_slide()
	_register_push_block_contacts()
	_update_player_state(false)
	_send_network_state()
	_state_machine.transition_from_player_context()
```

Add:

```gdscript
func _send_prediction_input(packet: Dictionary) -> void:
	if _prediction_controller != null:
		_prediction_controller.predict(packet, _last_prediction_delta)
	var network_manager := get_node_or_null("/root/NetworkManager")
	if network_manager != null and network_manager.has_method("send_player_input"):
		network_manager.call("send_player_input", packet)
```

- [ ] **Step 2: Include initial state in packets**

Update `_create_prediction_input_packet()`:

```gdscript
func _create_prediction_input_packet() -> Dictionary:
	var horizontal_direction: float = _input_reader.horizontal_direction if _input_reader != null else 0.0
	var jump_just_pressed: bool = _input_reader.jump_just_pressed if _input_reader != null else false
	var network_manager := _network_manager()
	var tick := int(network_manager.get("current_tick")) if network_manager != null else 0
	var packet := InputPacket.create(tick, horizontal_direction, jump_just_pressed)
	packet["pos"] = global_position
	packet["vel"] = velocity
	packet["on_floor"] = is_on_floor()
	return packet
```

- [ ] **Step 3: Apply reconciliation output**

Change `apply_authoritative_snapshot()`:

```gdscript
func apply_authoritative_snapshot(snapshot: Dictionary) -> void:
	if _prediction_controller == null:
		return
	var corrected_state := _prediction_controller.reconcile(snapshot, _last_prediction_delta)
	_apply_prediction_state(corrected_state)
```

- [ ] **Step 4: Initialize server authoritative state from first packet**

In `server/network_manager.gd`, update `receive_player_input()`:

```gdscript
if not _authoritative_states.has(player_id):
	var initial_state := PlayerMovementStateScript.new()
	initial_state.position = packet.get("pos", Vector2.ZERO)
	initial_state.velocity = packet.get("vel", Vector2.ZERO)
	initial_state.on_floor = packet.get("on_floor", false)
	_authoritative_states[player_id] = initial_state
```

Also avoid pre-creating zero states in `_on_peer_connected()`; remove:

```gdscript
_authoritative_states[id] = PlayerMovementStateScript.new()
```

- [ ] **Step 5: Verify prediction contract**

Run:

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/client_prediction_contract_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path server --quit
```

Expected: prediction contract passes; server project loads and starts without parse errors.

---

### Task 7: Fix Gem Gate Counting by Active Element

**Files:**
- Modify: `shared/scripts/gameplay/collectibles/gem_manager.gd`
- Test: `client/tests/prototype_runtime_probe.gd`
- Test: `client/tests/button_ladder_interactions_probe.gd`

- [ ] **Step 1: Filter required gems by player element**

Inside `configure_for_player(player: PrototypePlayer)`, change the gem append loop to:

```gdscript
for gem in get_tree().get_nodes_in_group("collectible_gem"):
	if gem is CollectibleGem and int(gem.gem_element) == _active_gem_element:
		_required_gems.append(gem)
		if multiplayer.is_server():
			if not gem.collected.is_connected(_on_gem_collected):
				gem.collected.connect(_on_gem_collected)
```

- [ ] **Step 2: Keep no-collectible levels unlocked**

Keep the current unlock rule:

```gdscript
func is_unlocked() -> bool:
	if not _is_configured:
		return true
	return required_count == 0 or _collected_gems.size() >= required_count
```

- [ ] **Step 3: Verify gem behavior**

Run:

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/button_ladder_interactions_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/prototype_runtime_probe.gd
```

Expected: wrong-element gem remains available; exit gate counts only active-element gems.

---

### Task 8: Final Verification and Review

**Files:**
- Read/review changed files only.

- [ ] **Step 1: Run full available verification**

Run:

```powershell
python client/tests/verify_prototype_foundation.py
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --quit
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path server --quit
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/client_prediction_contract_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/prototype_runtime_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/player_state_machine_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/precision_player_movement_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/button_ladder_interactions_probe.gd
```

Expected: all commands exit `0`; no `SCRIPT ERROR`, `Parse Error`, or misleading pass after failures.

- [ ] **Step 2: Run GodotPrompter code review checklist**

Review changed files against:

- RPC mode correctness: client-to-server methods use `"any_peer"`, server-to-client methods use `"authority"`.
- High-frequency movement uses unreliable channels where possible; reliable remains for role/start/gameplay events.
- No stale `/root/GameplayRPC` lookup.
- No `res://shared` dependency without a valid `client/shared` and `server/shared` path.
- No probe prints `passed` after `_failures` contains entries.

- [ ] **Step 3: Commit in focused groups**

Recommended commit order:

```powershell
git add client/shared server/shared client/tests/verify_prototype_foundation.py
git commit -m "fix: restore shared project resource links"

git add client/tests
git commit -m "test: repair Godot runtime probes"

git add shared/scripts/gameplay client/scripts/player/movement/player.gd client/scripts/network_manager.gd server/network_manager.gd
git commit -m "fix: repair gameplay rpc and prediction wiring"
```

---

## Self-Review

- Spec coverage: every reviewed issue has a task: shared path deletion, stale test paths/enums, false-positive probes, `GameplayRpc` lookup, prediction dead wiring, server zero-state initialization, and gem gate filtering.
- Placeholder scan: no `TBD`, `TODO`, or vague “add tests” steps remain.
- Type consistency: uses current `GameManager.ManagerState`, `CollectibleGem`, `PrototypePlayer`, `PlayerMovementState`, and existing `InputPacket.create()` contract.
