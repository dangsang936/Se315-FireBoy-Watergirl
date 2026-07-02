# Project Instructions

## Godot

Use this Godot executable when running or validating the projects:

```powershell
& "C:\Godot\v4.6.2\godot.exe" --headless --path "C:\Project\WaterFire\client" --quit
& "C:\Godot\v4.6.2\godot.exe" --headless --path "C:\Project\WaterFire\server" --quit
```

Project paths:

```text
C:\Project\WaterFire\client
C:\Project\WaterFire\server
```

## Shared code

`C:\Project\WaterFire\shared` is the canonical shared source folder. The Godot projects access it through directory symbolic links:

```text
C:\Project\WaterFire\client\shared -> C:\Project\WaterFire\shared
C:\Project\WaterFire\server\shared -> C:\Project\WaterFire\shared
```

Use `res://shared/...` for shared scripts, scenes, packets, models, and RPC resources from both client and server. Do not recreate physical `client/shared` or `server/shared` copies.
