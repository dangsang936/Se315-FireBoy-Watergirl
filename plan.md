# Main Menu + Create Room Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Goal:** Add a Maaack-based main menu with Create Room / Join Room / Settings / Exit, plus a UI-only async hook for future listen-server hosting.
>
> **Architecture:** The main menu instances Maaack's base `MainMenu` scene and overrides only local behavior. Create Room uses an async `NetworkManager.host_room(port)` signal contract; this plan intentionally leaves real server startup to the server team.
>
> **Tech Stack:** Godot 4.6, typed GDScript, Maaack's Game Template, ENet multiplayer contract stubs.
 
> **Mục đích session tiếp theo:** Implement or finish the plan below. Đây là task **UI-only scope** — KHÔNG đụng server logic thật.
>
> **Bối cảnh:** Branch `clientside`. Game FireWater Online (Godot 4.6, GDScript, ENet multiplayer co-op 2 người). Original request: add menu chính (Create Room / Join Room / Settings / Exit) + khi bấm Create Room thì tự chạy server rồi vào game. Repo hiện tại có thể đã apply một phần; xem `Current-state guard`.
 
---
 
## Quyết định đã chốt (KHÔNG hỏi lại)
 
1. **Create Room = Listen Server (Cách B).** Host = vừa chơi vừa làm server. Nhưng scope task NÀY chỉ làm **UI + hook**, server logic thật do server team làm.
2. **`host_room()` = async signal contract (Option B).** UI gọi `host_room(port)` → nghe `room_created` → navigate. Không sync return.
3. **Dùng template Maaack = instance base + override** (KHÔNG copy file addon ra `scenes/`).
4. **Create Room → navigate thẳng `game.tscn`** (không có host_lobby scene trung gian).
5. **Scope LAN.**
6. **Plugin Maaack đã cài** tại `client/addons/maaacks_game_template/`; nếu project chưa enable thì thêm `[editor_plugins]` + autoloads.
 
## Scope (đọc kỹ trước khi code)
 
### ĐƯỢC đụng
- `client/project.godot` — enable plugin + 4 autoloads + đổi main_scene
- `client/scenes/menus/main_menu.tscn` — tạo mới (instance base)
- `client/scenes/menus/main_menu.gd` — tạo mới (extends MainMenu)
- `client/scripts/network_manager.gd` — **chỉ THÊM** `host_room()` stub + 2 signals ở CUỐI file
- `client/tests/verify_prototype_foundation.py` — update main_scene assertion to the new menu scene
 
### KHÔNG đụng (server team owns)
- ❌ `server/network_manager.gd`
- ❌ GameManager (`game_manager.gd`) spawn/level flow
- ❌ Listen server logic thật (`create_server`, relay, role assign)
- ❌ `client/scenes/ui/lobby.tscn` + `lobby_ui.gd` (dùng sẵn cho Join Room)

## Current-state guard (đọc trước khi implement)

Plan này có thể chạy trên repo sạch hoặc repo đã apply một phần. Trước mỗi task:

- Nếu config / file / signal / function đã tồn tại đúng contract thì **giữ nguyên**, không duplicate.
- Nếu implementation hiện tại giữ `NewGameButton` nhưng đổi text thành "Create Room", đó là đúng. **Không rename inherited Maaack nodes.**
- Nếu `verify_prototype_foundation.py` vẫn expect `game.tscn` as `run/main_scene`, update test cùng task đổi main scene.
 
---
 
## Flow
 
```
Launch → main_menu.tscn (main_scene mới)
  ├─[Create Room]→ NetworkManager.host_room(9999)   [STUB]
  │               → room_created      → SceneLoader.load_scene(game.tscn)
  │               → room_creation_failed → StatusLabel "Failed: ..."
  ├─[Join Room]──→ SceneLoader.load_scene(lobby.tscn)  [lobby_ui.gd đã có]
  ├─[Settings]───→ _open_sub_menu(options_window)      [template Maaack]
  └─[Exit]───────→ exit confirmation → quit
```
 
---
 
## Context đã verify (đừng verify lại)
 
- **`GlobalState`, `AppSettings`, `PlayerConfig`** = `class_name` static classes (KHÔNG phải autoload). AppConfig._ready() gọi `GlobalState.open()` + `AppSettings.set_from_config_and_window()` an toàn.
- **`NetworkManager`** = autoload hiện có, dùng `const DEFAULT_PORT: int = 9999` (dùng cho `host_room(port:=DEFAULT_PORT)`).
- **AppConfig autoload path** = addon path gốc (`res://addons/.../app_config.tscn`). KHÔNG chạy setup wizard copy ra `res://scenes/`.
- **`.tscn` viết tay**: theo pattern example `addons/maaacks_game_template/examples/scenes/menus/main_menu/main_menu.tscn`. Godot tự regenerate `.uid` khi import — OK.
- **MainMenu base script** dùng `%` unique_name_in_owner cho nút (`%NewGameButton`, `%OptionsButton`, `%CreditsButton`, `%ExitButton`, `%MenuContainer`, `%MenuButtonsBoxContainer`, `%ExitConfirmation`). Vì `super._ready()` đọc các node này, **KHÔNG rename** `NewGameButton` hoặc `OptionsButton`; chỉ đổi text/behavior.
 
## UID tham chiếu (copy chính xác)
 
| Resource | UID | Path |
|---|---|---|
| base main_menu.tscn | `uid://c6k5nnpbypshi` | `res://addons/maaacks_game_template/base/nodes/menus/main_menu/main_menu.tscn` |
| options window | `uid://dum2pujhh1w4g` | `res://addons/maaacks_game_template/examples/scenes/windows/main_menu_options_window.tscn` |
| AppConfig.tscn | `uid://cjke6crjg14a0` | `res://addons/maaacks_game_template/base/nodes/autoloads/app_config/app_config.tscn` |
| SceneLoader.tscn | `uid://cbwmrnp0af35y` | `res://addons/maaacks_game_template/base/nodes/autoloads/scene_loader/scene_loader.tscn` |
| MusicController | `uid://r5t485lr3p7t` | `res://addons/maaacks_game_template/base/nodes/autoloads/music_controller/project_music_controller.tscn` |
| UISoundController | `uid://cc37235kj4384` | `res://addons/maaacks_game_template/base/nodes/autoloads/ui_sound_controller/project_ui_sound_controller.tscn` |
 
---
 
## Tasks
 
### Task 1 — Enable plugin + autoloads (`client/project.godot`)
**Skill:** `godot-prompter:godot-project-setup`

- [ ] Check existing values first. If these exact settings already exist, leave them unchanged.
- [ ] Add missing Maaack plugin/autoload settings to `client/project.godot`.
- [ ] Change `run/main_scene` to `res://scenes/menus/main_menu.tscn`.
- [ ] Update `client/tests/verify_prototype_foundation.py` to expect the menu scene.
 
Thêm section mới:
```ini
[editor_plugins]
enabled=PackedStringArray("maaacks_game_template")
```
 
Bổ sung vào section `[autoload]` hiện có (giữ nguyên NetworkManager):
```ini
AppConfig="*res://addons/maaacks_game_template/base/nodes/autoloads/app_config/app_config.tscn"
SceneLoader="*res://addons/maaacks_game_template/base/nodes/autoloads/scene_loader/scene_loader.tscn"
ProjectMusicController="*res://addons/maaacks_game_template/base/nodes/autoloads/music_controller/project_music_controller.tscn"
ProjectUISoundController="*res://addons/maaacks_game_template/base/nodes/autoloads/ui_sound_controller/project_ui_sound_controller.tscn"
```
 
Đổi main_scene (dòng 14 hiện tại):
```ini
run/main_scene="res://scenes/menus/main_menu.tscn"
```

Update prototype verification so repo tests agree with the new boot flow:
```python
require('run/main_scene="res://scenes/menus/main_menu.tscn"' in project_text, "Wrong main scene", failures)
```
 
### Task 2 — Tạo `client/scenes/menus/main_menu.gd`
**Skills:** `godot-prompter:godot-ui`, `godot-prompter:multiplayer-basics`

- [ ] Create or update `client/scenes/menus/main_menu.gd`.
- [ ] Keep inherited Maaack node references: `%NewGameButton`, `%OptionsButton`, `%CreditsButton`, `%ExitButton`.
- [ ] Implement idempotent room-created / room-failed signal connection cleanup.
 
Extend `MainMenu` (kế thừa template logic sub-menu/exit/focus):
```gdscript
extends MainMenu

func _ready() -> void:
	super._ready()
	%NewGameButton.grab_focus()

func _on_new_game_button_pressed() -> void:
	_disable_buttons()
	_set_status("Starting server...")
	# Option B async: nghe signal, KHÔNG sync return
	_connect_host_signals()
	NetworkManager.host_room(9999)

func _on_room_created() -> void:
	_disconnect_room_failed_signal()
	SceneLoader.load_scene("res://scenes/bootstrap/game.tscn")

func _on_room_failed(reason: String) -> void:
	_disconnect_room_created_signal()
	_set_status("Failed: %s" % reason)
	_enable_buttons()

func _on_join_room_button_pressed() -> void:
	SceneLoader.load_scene("res://scenes/ui/lobby.tscn")

# _on_options_button_pressed / _on_exit_button_pressed → kế thừa base MainMenu

# --- helpers ---
func _connect_host_signals() -> void:
	var created_callable := Callable(self, "_on_room_created")
	var failed_callable := Callable(self, "_on_room_failed")
	if not NetworkManager.room_created.is_connected(created_callable):
		NetworkManager.room_created.connect(created_callable, CONNECT_ONE_SHOT)
	if not NetworkManager.room_creation_failed.is_connected(failed_callable):
		NetworkManager.room_creation_failed.connect(failed_callable, CONNECT_ONE_SHOT)

func _disconnect_room_created_signal() -> void:
	var created_callable := Callable(self, "_on_room_created")
	if NetworkManager.room_created.is_connected(created_callable):
		NetworkManager.room_created.disconnect(created_callable)

func _disconnect_room_failed_signal() -> void:
	var failed_callable := Callable(self, "_on_room_failed")
	if NetworkManager.room_creation_failed.is_connected(failed_callable):
		NetworkManager.room_creation_failed.disconnect(failed_callable)

func _disable_buttons() -> void:
	for btn in [%NewGameButton, %JoinRoomButton, %OptionsButton, %ExitButton]:
		btn.disabled = true

func _enable_buttons() -> void:
	for btn in [%NewGameButton, %JoinRoomButton, %OptionsButton, %ExitButton]:
		btn.disabled = false

func _set_status(text: String) -> void:
	%StatusLabel.text = text
```
 
### Task 3 — Tạo `client/scenes/menus/main_menu.tscn`
**Skill:** `godot-prompter:godot-ui`

- [ ] Create or update `client/scenes/menus/main_menu.tscn` as an instance of Maaack base `MainMenu`.
- [ ] Keep `NewGameButton` and `OptionsButton` node names; change only visible text and local behavior.
- [ ] Add `JoinRoomButton`, `StatusLabel`, and explicit focus neighbors.
 
Instance base + override (theo pattern `addons/maaacks_game_template/examples/scenes/menus/main_menu/main_menu.tscn`):
 
- Root `MainMenu` node:
  - `script = ExtResource("local main_menu.gd")`
  - `game_scene_path = "res://scenes/bootstrap/game.tscn"`
  - `options_packed_scene = ExtResource(main_menu_options_window.tscn)`
  - `confirm_exit = true`
- Override nút trong `MenuButtonsBoxContainer` (dùng `parent_id_path` như example):
  - `NewGameButton` → giữ nguyên node name, text "Create Room", dùng inherited connection tới overridden `_on_new_game_button_pressed`
  - **THÊM** `JoinRoomButton` (Button "Join Room") giữa NewGame + Options, `unique_name_in_owner = true`, connect `_on_join_room_button_pressed`
  - `OptionsButton` → giữ nguyên node name, text "Settings" (kế thừa connect base)
  - `CreditsButton` → `visible = false`
  - `ExitButton` → text "Exit" (kế thừa connect base)
- **THÊM** node `StatusLabel` (Label, `unique_name_in_owner = true`) dưới MenuButtonsBoxContainer
- Title "FireWater Online", Subtitle "Co-op Puzzle Platformer"
- Tất cả nút `focus_mode = FOCUS_ALL`, wire `focus_neighbor_*` cho gamepad nav:
  - `NewGameButton.focus_neighbor_bottom = NodePath("../JoinRoomButton")`
  - `JoinRoomButton.focus_neighbor_top = NodePath("../NewGameButton")`
  - `JoinRoomButton.focus_neighbor_bottom = NodePath("../OptionsButton")`
  - `OptionsButton.focus_neighbor_top = NodePath("../JoinRoomButton")`
  - `OptionsButton.focus_neighbor_bottom = NodePath("../ExitButton")`
  - `ExitButton.focus_neighbor_top = NodePath("../OptionsButton")`
 
### Task 4 — NetworkManager stub (`client/scripts/network_manager.gd`)
**Skill:** `godot-prompter:multiplayer-basics`

- [ ] Inspect `client/scripts/network_manager.gd` for existing `room_created`, `room_creation_failed`, and `host_room()`.
- [ ] Append the stub only if it is missing.
- [ ] Leave all existing client/server RPC behavior untouched.
 
Nếu `room_created`, `room_creation_failed`, and `host_room()` đã tồn tại đúng contract, **không append duplicate**. Nếu chưa có, **chỉ THÊM** ở cuối file, KHÔNG sửa code cũ:
```gdscript
# ============================================================
# HOST ROOM (Create Room) — UI hook contract (Option B async)
# SERVER-TEAM CONTRACT: implement listen-server start in a separate server-owned task.
#   peer = ENetMultiplayerPeer.new()
#   var err := peer.create_server(port, 2)
#   if err != OK:
#       room_creation_failed.emit("Port %d busy" % port)
#       return
#   multiplayer.multiplayer_peer = peer
#   ... assign peer 1 = authority + role 0 (Fireboy) ...
#   room_created.emit()
# ============================================================
signal room_created
signal room_creation_failed(reason: String)
 
func host_room(port: int = DEFAULT_PORT) -> void:
	push_warning("[NetworkManager] host_room() not implemented — server team owns hosting")
	room_creation_failed.emit("Server hosting not yet implemented")
```
 
### Task 5 — Verification
**Skill:** `godot-prompter:godot-testing`

- [ ] Run static repo verification.
- [ ] Run Godot headless parse check.
- [ ] Complete manual menu smoke checks.
- [ ] Run `godot-prompter:godot-code-review` after implementation.

Static repo verification after updating `verify_prototype_foundation.py`:
```bash
python client/tests/verify_prototype_foundation.py
```
Kỳ vọng: pass. Nếu fail `Wrong main scene`, test vẫn chưa được update từ `game.tscn` sang `main_menu.tscn`.
 
Parse check (headless):
```bash
"C:/Users/habayakka/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe" \
  --path "D:/FireBoyandWaterGirl/Se315-FireBoy-Watergirl/client" --headless --quit
```
Kỳ vọng: không parse error, không autoload error.
 
Manual (editor):
1. Boot → MainMenu, 4 nút dọc, focus Create Room
2. Settings → OptionsMenu tabs (Audio/Video/Input)
3. Exit → confirm dialog → quit
4. Create Room → StatusLabel "Failed: Server hosting not yet implemented" (stub OK, không crash)
5. Join Room → lobby.tscn (IP/port input hiện)
 
**Sau khi xong:** chạy `godot-prompter:godot-code-review` validate.
 
---
 
## Suggested Skills (invoke khi implement)
 
| Task | Skill | Lý do |
|---|---|---|
| 1 | `godot-prompter:godot-project-setup` | Autoload registration, plugin enable |
| 2, 3 | `godot-prompter:godot-ui` | VBoxContainer layout, focus wiring, anchors, `%` unique names |
| 2, 4 | `godot-prompter:multiplayer-basics` | `create_server` pattern, signal contract, error check trước assign peer |
| 5 | `godot-prompter:godot-testing` | Headless parse verification |
| Final | `godot-prompter:godot-code-review` | Validate against Godot best practices |
| (process) | `godot-prompter:using-godot-prompter` | Bootstrap — RULE: phải check matching skill trước khi code |
 
---
 
## Files hiện có quan trọng (đọc nếu cần)
 
- `client/project.godot` — config hiện tại, cần modify
- `client/scripts/network_manager.gd` — autoload hiện tại, cần append stub
- `client/scenes/ui/lobby.tscn` + `client/scripts/ui/lobby_ui.gd` — Join Room target (đã có IP/port input, dùng sẵn)
- `client/scenes/bootstrap/game.tscn` — Create Room navigate target
- `client/scripts/core/game_manager/game_manager.gd` — spawn flow (KHÔNG đụng, chỉ tham khảo)
- `client/addons/maaacks_game_template/base/nodes/menus/main_menu/main_menu.gd` — base MainMenu class (đọc để hiểu signals/exports kế thừa)
- `client/addons/maaacks_game_template/examples/scenes/menus/main_menu/main_menu.tscn` — pattern reference cho instance + override
- `CLAUDE.md` (root) — project rules, coding conventions
- `client/AGENTS.md` — Godot rules (typed GDScript, tabs, composition)
 
## Lưu ý caveats
- **Typed GDScript + tabs** (per CLAUDE.md). Code samples trên đã dùng tabs + typed.
- **Không rename nodes/scenes/signals hiện có** trừ khi task yêu cầu.
- **Không edit `.tscn` thủ công** trừ khi cần — task 3 bắt buộc viết tay (sandbox không mở editor được). Nếu implement trong editor → dùng UI Inspector thay cho tay viết `.tscn`.
