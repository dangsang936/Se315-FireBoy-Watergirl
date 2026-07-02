# Multiplayer Gameplay Sync Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the current online gameplay desync where bridge/button state does not reliably reach the joining peer, push blocks cannot be pushed, and gems cannot be collected by either player.

**Architecture:** Use the existing local `CharacterBody2D` gameplay collision as the short-term source of interaction truth, because the dedicated server simulation is not yet collision-aware enough to validate level gameplay. The server remains the reliable relay for gameplay events: pressure button state, gem collection, level fail/win, restart, and push block transforms. Restore the `shared/` contract first so client and server run the same scripts/resources before changing behavior.

**Tech Stack:** Godot 4.6.2, typed GDScript with tabs, ENet RPC, existing `client/`, `server/`, and `shared/` layout.

---

## File Structure

- Modify or restore: `client/shared`, `server/shared`
  - These must be directory symlinks to repo `shared/`, not physical copies.
- Modify: `shared/scripts/gameplay/collectibles/collectible_gem.gd`
  - Let local clients detect their own gem touches and ask `NetworkManager` to relay collection.
- Modify: `shared/scripts/gameplay/collectibles/gem_manager.gd`
  - Let remote gem collection update local progress.
- Modify: `client/scripts/network_manager.gd`
  - Make gameplay event RPCs consistently relay through the dedicated server and emit local signals.
- Modify: `server/network_manager.gd`
  - Relay gameplay event RPCs with enough identifiers for both peers to resolve nodes.
- Modify: `client/scripts/core/game_manager/game_manager.gd`
  - Add diagnostics and robust handling for pressure button state and gem collection.
- Modify: `shared/scripts/gameplay/objects/pressure_button.gd`
  - Preserve local-only trigger detection, but support remote state application without re-emitting network loops.
- Modify: `shared/scripts/gameplay/objects/push_block.gd`
  - Replace `multiplayer.is_server()`-only push behavior with a short-term client-authority sync path.
- Modify: `shared/rpc/gameplay_rpc.gd`
  - Either remove from active gameplay sync or keep only as a compatibility wrapper around `NetworkManager`; avoid split RPC ownership.
- Modify: `client/scenes/levels/real_level_blank.tscn`
  - Ensure the currently loaded level contains the intended gems and push block if those mechanics are required in this level.
- Modify: `client/tests/verify_prototype_foundation.py`
  - Add static checks for shared symlinks and banned split-RPC patterns.
- Create or modify: `client/tests/multiplayer_gameplay_sync_probe.gd`
  - Focused local probe for gem, pressure button, and push block remote state application.

---

## Task 1: Restore Shared Folder Contract

**Skills during implementation:** `godot-prompter:assets-pipeline`, `godot-prompter:scene-organization`

**Files:**
- Modify filesystem entry: `client/shared`
- Modify filesystem entry: `server/shared`
- Verify: `shared/`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Inspect copy-only shared folders before changing them**

Run:

```powershell
Get-Item client\shared, server\shared, shared | Format-List FullName,LinkType,Target,Attributes
git status --short
```

Expected before fix: `client/shared` and `server/shared` are directories with empty `LinkType`, not symlinks.

- [ ] **Step 2: Preserve any unmerged shared-copy-only files**

Run this comparison:

```powershell
$paths = @(
  "scripts/gameplay/collectibles/collectible_gem.gd",
  "scripts/gameplay/collectibles/gem_manager.gd",
  "scripts/gameplay/hazards/hazard_zone.gd",
  "scripts/gameplay/objects/push_block.gd",
  "scripts/gameplay/objects/pressure_button.gd",
  "scripts/gameplay/objects/bridge_platform.gd",
  "scripts/gameplay/levels/prototype_level.gd",
  "scenes/gameplay/objects/push_block.tscn",
  "scenes/gameplay/collectibles/collectible_gem.tscn",
  "scenes/levels/prototype_level.tscn",
  "scenes/levels/prototype_level_physics.tscn"
)
foreach ($path in $paths) {
  Write-Output "--- $path"
  foreach ($root in @("client/shared", "server/shared", "shared")) {
    $file = Join-Path $root $path
    if (Test-Path $file) {
      $hash = (Get-FileHash $file -Algorithm SHA256).Hash.Substring(0, 12)
      Write-Output "$hash $file"
    } else {
      Write-Output "MISSING $file"
    }
  }
}
```

Expected: current output shows mismatched hashes. Decide the winning content per file by preserving the version that matches the intended current gameplay. In this bugfix, prefer the `client/shared` behavior for pressure-button remote-state guards, then merge it into repo `shared/`.

- [ ] **Step 3: Convert physical copies to symlinks**

After preserving needed content into `shared/`, run from repo root:

```powershell
Remove-Item client\shared -Recurse -Force
Remove-Item server\shared -Recurse -Force
New-Item -ItemType SymbolicLink -Path "client\shared" -Target "..\shared"
New-Item -ItemType SymbolicLink -Path "server\shared" -Target "..\shared"
```

Expected:

```text
client/shared -> ../shared
server/shared -> ../shared
```

- [ ] **Step 4: Verify shared path contract**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: shared-link failures are gone. Other gameplay failures may remain until later tasks.

- [ ] **Step 5: Commit**

```powershell
git add shared client\shared server\shared client\tests\verify_prototype_foundation.py
git commit -m "fix: restore shared folder contract"
```

---

## Task 2: Centralize Gameplay RPC Ownership In NetworkManager

**Skills during implementation:** `godot-prompter:multiplayer-basics`, `godot-prompter:multiplayer-sync`

**Files:**
- Modify: `client/scripts/network_manager.gd`
- Modify: `server/network_manager.gd`
- Modify: `shared/rpc/gameplay_rpc.gd`
- Modify: `client/tests/verify_prototype_foundation.py`

- [ ] **Step 1: Add static regression checks against split gameplay RPC ownership**

In `client/tests/verify_prototype_foundation.py`, add checks that fail if gem or push logic calls `/root/GameplayRpc` directly:

```python
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
```

Call it from `main()` after the existing script checks:

```python
check_multiplayer_gameplay_sync_contracts(failures)
```

- [ ] **Step 2: Run verifier to confirm it fails**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: FAIL on direct `GameplayRpc` usage in gem/push files.

- [ ] **Step 3: Keep server relay methods as the canonical path**

In `server/network_manager.gd`, gameplay event methods should relay through the `NetworkManager` RPC surface:

```gdscript
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_collect_gem(gem_path: String) -> void:
	rpc("sync_collect_gem", gem_path)

@rpc("authority", "call_local", "reliable")
func sync_collect_gem(_gem_path: String) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pressure_button_state(button_path: String, is_pressed: bool) -> void:
	rpc("sync_pressure_button_state", button_path, is_pressed)

@rpc("authority", "call_local", "reliable")
func sync_pressure_button_state(_button_path: String, _is_pressed: bool) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_request_push_block_state(block_path: String, pos: Vector2, rot: float, linear_velocity: Vector2, angular_velocity: float) -> void:
	rpc("sync_push_block_state", block_path, pos, rot, linear_velocity, angular_velocity)

@rpc("authority", "call_local", "unreliable_ordered")
func sync_push_block_state(_block_path: String, _pos: Vector2, _rot: float, _linear_velocity: Vector2, _angular_velocity: float) -> void:
	pass
```

- [ ] **Step 4: Add matching client signals and send/receive methods**

In `client/scripts/network_manager.gd`, add:

```gdscript
signal push_block_state_received(block_path: String, pos: Vector2, rot: float, linear_velocity: Vector2, angular_velocity: float)
```

Add:

```gdscript
func send_push_block_state(block_path: String, pos: Vector2, rot: float, linear_velocity: Vector2, angular_velocity: float) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_push_block_state", block_path, pos, rot, linear_velocity, angular_velocity)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_request_push_block_state(_block_path: String, _pos: Vector2, _rot: float, _linear_velocity: Vector2, _angular_velocity: float) -> void:
	pass

@rpc("authority", "call_local", "unreliable_ordered")
func sync_push_block_state(block_path: String, pos: Vector2, rot: float, linear_velocity: Vector2, angular_velocity: float) -> void:
	push_block_state_received.emit(block_path, pos, rot, linear_velocity, angular_velocity)
```

- [ ] **Step 5: Make `GameplayRpc` compatibility-only**

In `shared/rpc/gameplay_rpc.gd`, remove active gameplay authority from this autoload. Keep a minimal compatibility shell:

```gdscript
class_name GameplayRPC
extends Node

func _ready() -> void:
	push_warning("GameplayRpc is deprecated for gameplay sync. Use NetworkManager gameplay relay methods.")
```

- [ ] **Step 6: Verify**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --quit
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path server --quit --port=19099
```

Expected: no parse errors; static check no longer fails on direct `GameplayRpc` calls after later tasks update gem/push files.

- [ ] **Step 7: Commit**

```powershell
git add client\scripts\network_manager.gd server\network_manager.gd shared\rpc\gameplay_rpc.gd client\tests\verify_prototype_foundation.py
git commit -m "fix: centralize gameplay sync relay"
```

---

## Task 3: Fix Pressure Button And Bridge Sync Diagnostics

**Skills during implementation:** `godot-prompter:multiplayer-sync`, `godot-prompter:physics-system`

**Files:**
- Modify: `client/scripts/core/game_manager/game_manager.gd`
- Modify: `shared/scripts/gameplay/objects/pressure_button.gd`
- Test: `client/tests/multiplayer_puzzle_sync_probe.gd`

- [ ] **Step 1: Add deterministic button path logging**

In `client/scripts/core/game_manager/game_manager.gd`, update `_on_pressure_button_state_changed`:

```gdscript
func _on_pressure_button_state_changed(is_pressed: bool, button: PressureButton) -> void:
	var network_manager := _network_manager()
	if network_manager == null or not bool(network_manager.call("is_connected_to_server")):
		return
	if not is_instance_valid(_current_level) or not is_instance_valid(button):
		return
	var button_path := str(_current_level.get_path_to(button))
	print("[GameManager] send pressure button state path=%s pressed=%s" % [button_path, str(is_pressed)])
	network_manager.call("send_pressure_button_state", button_path, is_pressed)
```

- [ ] **Step 2: Add receive-side diagnostics**

Update `_on_pressure_button_state_received`:

```gdscript
func _on_pressure_button_state_received(button_path: String, is_pressed: bool) -> void:
	if not is_instance_valid(_current_level):
		push_warning("[GameManager] pressure state received without current level: %s" % button_path)
		return
	var button := _current_level.get_node_or_null(NodePath(button_path)) as PressureButton
	if button == null:
		push_warning("[GameManager] pressure button path not found: %s" % button_path)
		return
	if not button.has_method("apply_remote_pressed_state"):
		push_warning("[GameManager] pressure button missing apply_remote_pressed_state: %s" % button_path)
		return
	print("[GameManager] apply pressure button state path=%s pressed=%s" % [button_path, str(is_pressed)])
	button.call("apply_remote_pressed_state", is_pressed)
```

- [ ] **Step 3: Keep remote application non-looping**

In `shared/scripts/gameplay/objects/pressure_button.gd`, keep this behavior:

```gdscript
func apply_remote_pressed_state(next_pressed: bool) -> void:
	_set_pressed_state(next_pressed, false)
```

And keep `_can_press_with_player` local-only:

```gdscript
func _can_press_with_player(player: PrototypePlayer) -> bool:
	if player.get("is_local") == false:
		return false
	if not _matches_required_element(player):
		return false
	if require_player_on_floor and not player.is_on_floor():
		return false
	return true
```

- [ ] **Step 4: Verify puzzle probe**

Run:

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/multiplayer_puzzle_sync_probe.gd
```

Expected:

```text
Multiplayer puzzle sync probe passed.
```

- [ ] **Step 5: Manual two-client check**

Run host waiting room path:

```text
1. P1 starts room from main menu.
2. P2 joins.
3. P1 starts game.
4. P1 steps on PressureButton.
5. Confirm P1 prints send pressure state.
6. Confirm P2 prints apply pressure state.
7. Confirm P2 sees LavaBridge active before Watergirl crosses lava.
```

- [ ] **Step 6: Commit**

```powershell
git add client\scripts\core\game_manager\game_manager.gd shared\scripts\gameplay\objects\pressure_button.gd
git commit -m "fix: trace and apply pressure button sync"
```

---

## Task 4: Fix Gem Collection Under Current Client-Local Gameplay

**Skills during implementation:** `godot-prompter:multiplayer-sync`, `godot-prompter:physics-system`

**Files:**
- Modify: `shared/scripts/gameplay/collectibles/collectible_gem.gd`
- Modify: `shared/scripts/gameplay/collectibles/gem_manager.gd`
- Modify: `client/scripts/core/game_manager/game_manager.gd`
- Modify: `client/scenes/levels/real_level_blank.tscn`
- Test: `client/tests/multiplayer_gameplay_sync_probe.gd`

- [ ] **Step 1: Ensure active level contains Collectibles if gems are required**

Inspect:

```powershell
rg -n "Collectibles|FireGem|WaterGem|gem_element" client\scenes\levels\real_level_blank.tscn
```

If empty, add a `Collectibles` node and matching fire/water gem instances to `client/scenes/levels/real_level_blank.tscn`. Use existing gem scene:

```text
[node name="Collectibles" type="Node2D" parent="."]
script = ExtResource("gem_manager_script")

[node name="FireGem" parent="Collectibles" instance=ExtResource("collectible_gem_scene")]
position = Vector2(<safe_fire_gem_position>)
gem_element = 0

[node name="WaterGem" parent="Collectibles" instance=ExtResource("collectible_gem_scene")]
position = Vector2(<safe_water_gem_position>)
gem_element = 1
```

Pick positions that exist in the current level and do not overlap lava or terrain.

- [ ] **Step 2: Let local players request gem collection**

In `shared/scripts/gameplay/collectibles/collectible_gem.gd`, replace the server-only `_ready()` connection with:

```gdscript
func _ready() -> void:
	add_to_group("collectible_gem")
	collision_layer = GEM_COLLISION_LAYER
	collision_mask = GEM_COLLISION_MASK
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = true
	_apply_element_color()
```

Update `_on_body_entered` to only react to the local player on clients:

```gdscript
func _on_body_entered(body: Node2D) -> void:
	if _is_collected or not body.is_in_group("player"):
		return

	var player := body as PrototypePlayer
	if player == null:
		return
	if player.get("is_local") == false:
		return

	if not can_collect(player):
		wrong_element_touched.emit(self, player)
		return

	var network_manager := get_node_or_null("/root/NetworkManager")
	if network_manager != null and bool(network_manager.call("is_connected_to_server")):
		var level := _find_level_root()
		var gem_path := str(level.get_path_to(self)) if level != null else str(get_path())
		network_manager.call("send_collect_gem", gem_path)
		return

	_collect_locally(player)
```

Add helpers:

```gdscript
func _find_level_root() -> Node:
	var node: Node = self
	while node != null:
		if node is PrototypeLevel:
			return node
		node = node.get_parent()
	return null

func _collect_locally(player: PrototypePlayer) -> void:
	if _is_collected:
		return
	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	collected.emit(self, player)

func collect_remotely() -> void:
	if _is_collected:
		return
	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
```

- [ ] **Step 3: Emit progress when remote gem collection is applied**

In `client/scripts/core/game_manager/game_manager.gd`, update `_on_gem_collected_received`:

```gdscript
func _on_gem_collected_received(gem_path: String) -> void:
	if not is_instance_valid(_current_level):
		return
	var gem_node = _current_level.get_node_or_null(NodePath(gem_path))
	if gem_node and gem_node.has_method("collect_remotely"):
		gem_node.collect_remotely()
	if _current_level.has_method("_connect_collectibles"):
		pass
	if _current_level.has_signal("gem_progress_changed"):
		var manager := _current_level.get_node_or_null("Collectibles") as GemManager
		if manager != null and manager.has_method("client_mark_collected_by_path"):
			manager.call("client_mark_collected_by_path", gem_path)
```

In `shared/scripts/gameplay/collectibles/gem_manager.gd`, add:

```gdscript
func client_mark_collected_by_path(gem_path: String) -> void:
	var gem := get_node_or_null(NodePath("../" + gem_path)) as CollectibleGem
	if gem != null and _required_gems.has(gem) and not _collected_gems.has(gem):
		_collected_gems.append(gem)
	_emit_progress()
```

If the relative path above does not resolve in the level tree, adjust during implementation to resolve from `PrototypeLevel`, then lock it with the probe in Step 4.

- [ ] **Step 4: Add probe for remote gem application**

Create or extend `client/tests/multiplayer_gameplay_sync_probe.gd`:

```gdscript
extends SceneTree

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_remote_gem_collection_hides_gem()
	if _failures.is_empty():
		print("Multiplayer gameplay sync probe passed.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	quit(1)

func _verify_remote_gem_collection_hides_gem() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame
	var gems := get_nodes_in_group("collectible_gem")
	_require(not gems.is_empty(), "real_level_blank must contain at least one collectible gem.")
	if gems.is_empty():
		level.queue_free()
		return
	var gem := gems[0] as CollectibleGem
	_require(gem != null, "collectible_gem group member must be CollectibleGem.")
	if gem != null:
		gem.collect_remotely()
		_require(not gem.visible, "Remote gem collection should hide the gem.")
	level.queue_free()
	await process_frame

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
```

- [ ] **Step 5: Verify**

Run:

```powershell
python client\tests\verify_prototype_foundation.py
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/multiplayer_gameplay_sync_probe.gd
```

Expected:

```text
Multiplayer gameplay sync probe passed.
```

- [ ] **Step 6: Commit**

```powershell
git add shared\scripts\gameplay\collectibles\collectible_gem.gd shared\scripts\gameplay\collectibles\gem_manager.gd client\scripts\core\game_manager\game_manager.gd client\scenes\levels\real_level_blank.tscn client\tests\multiplayer_gameplay_sync_probe.gd
git commit -m "fix: sync local gem collection"
```

---

## Task 5: Restore Push Block Gameplay With Short-Term Client Authority

**Skills during implementation:** `godot-prompter:physics-system`, `godot-prompter:multiplayer-sync`

**Files:**
- Modify: `shared/scripts/gameplay/objects/push_block.gd`
- Modify: `client/scripts/core/game_manager/game_manager.gd`
- Modify: `client/scenes/levels/real_level_blank.tscn`
- Test: `client/tests/push_block_gameplay_probe.gd`
- Test: `client/tests/multiplayer_gameplay_sync_probe.gd`

- [ ] **Step 1: Ensure the active level contains PushBlock if push is required**

Run:

```powershell
rg -n "PushBlock" client\scenes\levels\real_level_blank.tscn
```

If missing, add a `PushBlock` instance under `Objects` in `client/scenes/levels/real_level_blank.tscn`, using the existing push block scene. Place it on a stable floor, not inside lava.

- [ ] **Step 2: Remove server-only freeze from push block**

In `shared/scripts/gameplay/objects/push_block.gd`, replace the early server-only block in `_ready()`:

```gdscript
	if not multiplayer.is_server():
		freeze = true
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		if _push_detector != null:
			_push_detector.monitoring = false
		if _ground_detector != null:
			_ground_detector.enabled = false
		return
```

With:

```gdscript
	freeze = false
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
```

Keep detector setup active on clients:

```gdscript
	if _push_detector != null:
		_push_detector.collision_mask = PUSH_DETECTOR_COLLISION_MASK
		if not _push_detector.body_entered.is_connected(_on_push_detector_body_entered):
			_push_detector.body_entered.connect(_on_push_detector_body_entered)
```

- [ ] **Step 3: Allow local push attempts**

In `register_push_attempt`, remove the `multiplayer.is_server()` return and add local-player guard:

```gdscript
func register_push_attempt(body: Node2D, push_direction: float) -> void:
	if not body.is_in_group("player"):
		return
	if body.get("is_local") == false:
		return
	var direction: float = clampf(push_direction, -1.0, 1.0)
	if direction == 0.0:
		return
	sleeping = false
	_push_attempts[body.get_instance_id()] = Vector2(direction, PUSH_ATTEMPT_TTL)
```

- [ ] **Step 4: Broadcast push block transform from the peer currently moving it**

Replace the `GameplayRpc` broadcast in `_physics_process` with `NetworkManager`:

```gdscript
func _physics_process(delta: float) -> void:
	if _ground_detector == null:
		_is_grounded = get_contact_count() > 0
	else:
		_ground_detector.global_position = global_position + Vector2(0.0, GROUND_DETECTOR_OFFSET)
		_ground_detector.global_rotation = 0.0
		_ground_detector.force_raycast_update()
		_is_grounded = _ground_detector.is_colliding()

	_sync_timer += delta
	if _sync_timer >= SYNC_RATE and not sleeping:
		_sync_timer = 0.0
		var network_manager := get_node_or_null("/root/NetworkManager")
		if network_manager != null and bool(network_manager.call("is_connected_to_server")):
			var level := _find_level_root()
			var block_path := str(level.get_path_to(self)) if level != null else str(get_path())
			network_manager.call("send_push_block_state", block_path, global_position, rotation, linear_velocity, angular_velocity)
```

Add:

```gdscript
func _find_level_root() -> Node:
	var node: Node = self
	while node != null:
		if node is PrototypeLevel:
			return node
		node = node.get_parent()
	return null

func apply_remote_state(pos: Vector2, rot: float, remote_linear_velocity: Vector2, remote_angular_velocity: float) -> void:
	global_position = pos
	rotation = rot
	linear_velocity = remote_linear_velocity
	angular_velocity = remote_angular_velocity
```

- [ ] **Step 5: Apply remote push block state in GameManager**

In `client/scripts/core/game_manager/game_manager.gd`, connect the new signal in `_ready()`:

```gdscript
network_manager.push_block_state_received.connect(_on_push_block_state_received)
```

Add:

```gdscript
func _on_push_block_state_received(block_path: String, pos: Vector2, rot: float, linear_velocity: Vector2, angular_velocity: float) -> void:
	if not is_instance_valid(_current_level):
		return
	var block := _current_level.get_node_or_null(NodePath(block_path))
	if block == null or not block.has_method("apply_remote_state"):
		return
	block.call("apply_remote_state", pos, rot, linear_velocity, angular_velocity)
```

- [ ] **Step 6: Verify local push probe**

Run:

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/push_block_gameplay_probe.gd
```

Expected: pass. If it still fails because `real_level_blank` lacks `Objects/PushBlock`, fix the active level scene before changing script logic further.

- [ ] **Step 7: Manual two-client push check**

```text
1. Start two clients.
2. Move P1 against PushBlock and push for 2 seconds.
3. Confirm P1 sees the block move.
4. Confirm P2 sees the same block move within 0.1 seconds.
5. Move P2 against PushBlock and push for 2 seconds.
6. Confirm P1 receives the updated transform.
```

- [ ] **Step 8: Commit**

```powershell
git add shared\scripts\gameplay\objects\push_block.gd client\scripts\core\game_manager\game_manager.gd client\scenes\levels\real_level_blank.tscn client\tests
git commit -m "fix: sync push block movement"
```

---

## Task 6: Add End-To-End Manual Sync Diagnostics

**Skills during implementation:** `godot-prompter:godot-debugging`, `godot-prompter:multiplayer-sync`

**Files:**
- Modify: `client/scripts/network_manager.gd`
- Modify: `server/network_manager.gd`
- Modify: `client/scripts/core/game_manager/game_manager.gd`

- [ ] **Step 1: Add concise event logs**

Add logs for each gameplay event:

```gdscript
print("[Client] send_collect_gem path=%s" % gem_path)
print("[Client] sync_collect_gem path=%s" % gem_path)
print("[Client] send_pressure_button path=%s pressed=%s" % [button_path, str(is_pressed)])
print("[Client] sync_pressure_button path=%s pressed=%s" % [button_path, str(is_pressed)])
print("[Client] send_push_block path=%s pos=%s" % [block_path, str(pos)])
print("[Client] sync_push_block path=%s pos=%s" % [block_path, str(pos)])
```

On server:

```gdscript
print("[Server] relay collect gem from=%d path=%s" % [multiplayer.get_remote_sender_id(), gem_path])
print("[Server] relay pressure button from=%d path=%s pressed=%s" % [multiplayer.get_remote_sender_id(), button_path, str(is_pressed)])
print("[Server] relay push block from=%d path=%s pos=%s" % [multiplayer.get_remote_sender_id(), block_path, str(pos)])
```

- [ ] **Step 2: Manual two-client scenario**

Run:

```text
1. Close all Godot server processes using port 9999.
2. P1: main menu -> create room.
3. P2: join room.
4. P1: start game.
5. P1 steps on bridge button.
6. P2 crosses bridge.
7. P1 collects fire gem.
8. P2 collects water gem.
9. P1 pushes block.
10. P2 pushes block.
```

Expected:

```text
Both clients see bridge active/inactive changes.
Both clients see collected gems disappear.
Both clients see gem progress update.
Both clients see push block movement.
No client dies from lava while the remote bridge state is active.
```

- [ ] **Step 3: Commit diagnostics only if useful**

If logs are too noisy after the bug is fixed, gate them behind a debug flag before committing:

```gdscript
const DEBUG_GAMEPLAY_SYNC: bool = true
```

Use:

```gdscript
if DEBUG_GAMEPLAY_SYNC:
	print("[Client] ...")
```

Commit:

```powershell
git add client\scripts\network_manager.gd server\network_manager.gd client\scripts\core\game_manager\game_manager.gd
git commit -m "chore: add gameplay sync diagnostics"
```

---

## Task 7: Final Verification And Godot Review

**Skills during implementation:** `godot-prompter:godot-testing`, `godot-prompter:godot-code-review`

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run static verifier**

```powershell
python client\tests\verify_prototype_foundation.py
```

Expected: pass.

- [ ] **Step 2: Run client parse**

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --quit
```

Expected: exit 0, no GDScript parse errors.

- [ ] **Step 3: Run server parse on a free port**

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path server --quit --port=19099
```

Expected: exit 0. If port `19099` is busy, choose another free port and record it.

- [ ] **Step 4: Run focused probes**

```powershell
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/multiplayer_hazard_sync_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/multiplayer_puzzle_sync_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/push_block_gameplay_probe.gd
& 'C:\Users\habayakka\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe' --headless --path client --script res://tests/multiplayer_gameplay_sync_probe.gd
```

Expected: all probes print passed messages.

- [ ] **Step 5: Run GodotPrompter review checklist**

Review final diff for:

```text
- Area2D gems scan Player layer and do not double-connect body_entered.
- Remote visual players do not trigger local hazards/buttons.
- Remote state application does not re-emit network signals and create loops.
- PushBlock uses valid RigidBody2D force changes in physics callbacks.
- Gameplay sync uses one RPC owner: NetworkManager.
- client/shared and server/shared resolve to repo shared/.
- real_level_blank contains the gameplay objects expected by active tests.
```

- [ ] **Step 6: Final commit if verification changes were needed**

```powershell
git add <changed-files>
git commit -m "test: verify multiplayer gameplay sync"
```

---

## Follow-Up Plan: Real Server-Authoritative Gameplay

This bugfix intentionally keeps local collision as the short-term gameplay truth. After the current bugs are fixed, create a separate plan for true authoritative gameplay:

```text
- Dedicated server loads the same active level scene as clients.
- Server spawns lightweight authoritative player bodies with role/element data.
- Clients send input packets every physics tick.
- Server simulates movement with collision-aware map.
- Server validates hazards, gems, button presses, push block forces, and exits.
- Clients receive authoritative snapshots and reconcile.
```

Do not mix that refactor into this bugfix. It is larger and should be tested separately.

---

## Self-Review

- Spec coverage: Lỗi 1 bridge/button sync is covered by Tasks 2, 3, and 6. Lỗi 2 push block is covered by Task 5. Lỗi 3 gem collection is covered by Task 4. Shared/server desync root cause is covered first by Task 1.
- Placeholder scan: No `TBD`, `TODO`, or "similar to" steps. Scene positions for new gems/push block must be selected from the actual level geometry during implementation because the visual level layout is authored in `.tscn`; this is an explicit implementation choice, not a missing behavior.
- Type consistency: The plan uses existing `PressureButton`, `PrototypeLevel`, `CollectibleGem`, `GemManager`, `PushBlock`, and `NetworkManager` names. New push block RPC signatures match client and server.
