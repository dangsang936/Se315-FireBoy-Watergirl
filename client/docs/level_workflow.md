# Level Workflow

## Scenes

- `res://scenes/bootstrap/game.tscn` runs the prototype sandbox.
- `res://scenes/bootstrap/game_real.tscn` runs the real-map blank scene.
- `res://scenes/levels/prototype_level.tscn` is for quick mechanics tests.
- `res://scenes/levels/real_level_blank.tscn` is the clean starting point for production maps.

## Level Contract

Every playable level should keep these node names:

```text
LevelRoot (PrototypeLevel script)
├── Players
│   └── PlayerSpawn
├── Terrain
├── Objects
├── Hazards
│   └── HazardZone
└── Goals
    └── ExitDoor
```

`PrototypeLevel` wires `HazardZone.player_entered` to lose, `ExitDoor.player_entered` to win, and spawns the player at `Players/PlayerSpawn`.

## Creating A New Level

1. Duplicate `res://scenes/levels/real_level_blank.tscn`.
2. Rename it, for example `res://scenes/levels/level_01.tscn`.
3. Keep the contract node names unchanged.
4. Build terrain under `Terrain`.
5. Add push blocks, doors, plates, and puzzle objects under `Objects`.
6. Add lava, water, or poison hazard areas under `Hazards`.
7. Move `Goals/ExitDoor` to the finish.
8. Move `Players/PlayerSpawn` to the start.

## Hazard Pool Types

`HazardZone.pool_type` supports:

- `LAVA`: Fireboy survives, Watergirl fails.
- `WATER`: Watergirl survives, Fireboy fails.
- `POISON`: Fireboy and Watergirl both fail.

Any `HazardZone` child under `Hazards` is wired automatically by the level script.

## Switching Test Scenes

Fast editor method:

1. Open `res://scenes/bootstrap/game.tscn` for prototype.
2. Open `res://scenes/bootstrap/game_real.tscn` for real map.
3. Press `F6` to run the currently open scene.

Project main scene method:

1. Open `Project > Project Settings > Application > Run`.
2. Set `Main Scene` to `res://scenes/bootstrap/game.tscn` for prototype testing.
3. Set `Main Scene` to `res://scenes/bootstrap/game_real.tscn` for real-map testing.
4. Press `F5`.

Code method:

1. Open the desired bootstrap scene.
2. In the Inspector, set `Game.level_scene` to any level scene.
3. Keep `player_scene` as `res://scenes/players/fireboy.tscn` until multi-character flow is added.
