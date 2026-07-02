# FireWater Online

Online co-op puzzle platformer inspired by Fireboy and Watergirl.

## Goals
- Learn multiplayer architecture
- Build authoritative server
- Experiment with synchronization
- Modular gameplay systems

## Tech Stack
- Godot 4
- GDScript
- ENet multiplayer

## Structure
- docs/: GDD, structure docs, network/API notes, diagrams, meeting notes
- shared/: constants, enums, packets, events, models, config, reusable utilities
- client/: Godot client project
- server/: dedicated authoritative server project
- tools/: internal level, validation, replay, and automation tools
- deployment/: build, CI, Docker, and server deployment assets
- prototypes/: isolated movement, networking, physics, and puzzle experiments

## Shared Folder Setup

`shared/` is the single source of truth for code and resources used by both the client and the server. The Godot projects access it through local directory links:

```text
client/shared -> ../shared
server/shared -> ../shared
```

From inside either Godot project, always reference shared files with `res://shared/...`.

Examples:

```gdscript
preload("res://shared/packets/input_packet.gd")
preload("res://shared/scripts/gameplay/objects/push_block.gd")
```

Do not create physical copies of `client/shared` or `server/shared`. They are ignored by Git and should be generated locally.

### One-time setup after clone

After cloning the repository, run this once from the repository root:

```powershell
.\scripts\setup_git_hooks.ps1
```

This installs local Git hooks into `.git/hooks/`:

- `post-merge` recreates shared links after a normal `git pull` / merge.
- `post-rewrite` recreates shared links after `git pull --rebase`.

Then create the links immediately:

```powershell
.\scripts\setup_shared_links.ps1
```

After this setup, future pulls will automatically refresh `client/shared` and `server/shared`.

### Manual refresh

If the links are missing or Godot cannot load `res://shared/...`, run:

```powershell
.\scripts\setup_shared_links.ps1
```

The script creates:

```text
client/shared -> shared
server/shared -> shared
```

On Windows, it first tries to create directory symbolic links. If symlink creation is not allowed, it falls back to directory junctions, which usually do not require Administrator privileges or Developer Mode.

The script is safe around real folders: if `client/shared` or `server/shared` exists but is not a link/junction, it stops instead of deleting the folder.

### Verify the links

```powershell
Get-Item "client\shared" -Force | Format-List FullName,LinkType,Target
Get-Item "server\shared" -Force | Format-List FullName,LinkType,Target
```

Expected result is `LinkType : SymbolicLink` or `LinkType : Junction`.

### Notes

Git hooks are local files and are not committed to the repository, so each teammate needs to run this once on their own machine:

```powershell
.\scripts\setup_git_hooks.ps1
```
