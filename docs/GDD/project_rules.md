# Project Rules

Source documents:

- `docs/GDD/GDD_FireBoy_WaterGirl_Online.docx`
- `docs/GDD/Project_structure.docx`
- `client/AGENTS.md`
- `client/docs/level_workflow.md`

## Scope

- Focus gameplay only for the current client milestone.
- Build and validate playable mechanics before adding menus, cosmetics, ranking, monetization, or nonessential platform work.
- Keep the current playable scope centered on Fireboy prototype gameplay, hazards, collectibles, doors, push objects, level flow, HUD, pause/restart, and verification.
- Online multiplayer remains a project goal, but local co-op is not part of the current client scope.
- Do not add a no local co-op mode workaround.
- Do not add no co-op-adjacent work such as second-player input maps, split-screen controls, local dual-character switching, or same-keyboard two-player flow unless explicitly requested.

## Gameplay Rules

- The game is a 2D online co-op puzzle platformer inspired by FireBoy and WaterGirl.
- Fireboy survives lava and fails in water.
- Watergirl survives water and fails in lava.
- Both characters fail in poison.
- Players solve levels through movement, jumping, collision, respawn, animation, puzzle triggers, doors, platforms, checkpoints, spawn points, hazard zones, and win conditions.
- A level is complete only when the configured exit condition is satisfied.
- Current client levels may use a single active player until multi-character online flow is explicitly added.

## Level Rules

- Playable levels must preserve the documented node contract:

```text
LevelRoot (PrototypeLevel script)
|-- Players
|   `-- PlayerSpawn
|-- Terrain
|-- Objects
|-- Collectibles (optional)
|-- Hazards
|   `-- HazardZone
`-- Goals
    `-- ExitDoor
```

- `PrototypeLevel` wires hazards to failure, exit doors to completion, and spawn position to `Players/PlayerSpawn`.
- `Collectibles` is optional. Without it, the exit works immediately.
- When `Collectibles` has `GemManager`, the exit stays locked until the active player collects every matching-element gem.
- Any `HazardZone` child under `Hazards` should be wired automatically by the level script.
- New production levels should start from `res://scenes/levels/real_level_blank.tscn`.
- Prototype mechanics should be tested in `res://scenes/levels/prototype_level.tscn`.

## Client Architecture Rules

- The client is a Godot 4.x project.
- Use typed GDScript for `.gd` files.
- Use tabs for indentation in `.gd` files.
- Use Godot 4 APIs only; do not introduce Godot 3 syntax.
- Prefer composition over inheritance.
- Keep scripts small and focused.
- Use component-based design and explicit state machines for growing gameplay behavior.
- Do not rename nodes, scenes, resources, or signals unless explicitly requested.
- Do not edit `.tscn` files manually unless necessary.
- Prefer editor-safe changes through scripts and resources.
- Use exported node references where practical.
- Avoid fragile string-based deep `get_node()` paths.
- Document collision layers and masks when gameplay depends on them.

## Suggested Folder Ownership

- `client/scenes/bootstrap/`: startup scenes.
- `client/scenes/levels/`: playable level scenes.
- `client/scenes/players/`: Fireboy and Watergirl scenes.
- `client/scenes/ui/`: HUD and UI scenes.
- `client/scripts/core/`: game state, loading, flow, and managers.
- `client/scripts/player/`: movement, abilities, animation, collision, interaction, and states.
- `client/scripts/gameplay/`: puzzles, doors, checkpoints, hazards, platforms, triggers, and interactables.
- `client/scripts/multiplayer/`: ENet, synchronization, authority, RPC, lobby, prediction, and debug code.
- `client/scripts/ui/`: HUD, menus, lobby UI, popups, and widgets.
- `client/assets/`: imported sprites, animations, sounds, music, shaders, fonts, and tilesets.
- `client/tests/`: client and gameplay verification probes.
- `shared/`: constants, enums, packets, events, models, config, and utilities shared by future client/server work.

## Multiplayer Direction

- Networking direction is online multiplayer with ENet and a client/server authority model.
- Server-authoritative state is preferred for anti-cheat, synchronization stability, and game-state ownership.
- Clients send inputs or actions; authoritative systems validate and synchronize state.
- Future multiplayer systems may include spawning, transform/state sync, animation sync, puzzle sync, room/lobby flow, RPC events, prediction, reconciliation, interpolation, matchmaking, packet logging, latency monitoring, and desync checks.
- Do not implement local co-op input or local two-player flow as a substitute for online multiplayer.

## Development Safety

- Before large changes, explain intended files and scope.
- After changes, run a parse/check step when available.
- Run `py -3 tests/verify_prototype_foundation.py` for client foundation validation when relevant.
- If Godot CLI is unavailable, report that parse/check could not be run.
- Never delete assets or scenes without explicit instruction.
- Avoid unrelated scene/resource churn.

