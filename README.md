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

`shared/` is the single source of truth for code and resources used by both the client and the server. The Godot projects access it through directory symbolic links:

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

Do not recreate physical copies of `client/shared` or `server/shared`; they should be symlinks.

### Creating the symlinks on Windows

Windows may require Developer Mode or an Administrator PowerShell to create directory symlinks.

From the repository root:

```powershell
New-Item -ItemType SymbolicLink -Path "client\shared" -Target "..\shared"
New-Item -ItemType SymbolicLink -Path "server\shared" -Target "..\shared"
```

If the paths already exist but are not symlinks, remove them first after confirming there is no unmerged work inside:

```powershell
Remove-Item "client\shared" -Recurse -Force
Remove-Item "server\shared" -Recurse -Force
New-Item -ItemType SymbolicLink -Path "client\shared" -Target "..\shared"
New-Item -ItemType SymbolicLink -Path "server\shared" -Target "..\shared"
```

Verify the links:

```powershell
Get-Item "client\shared" -Force | Format-List FullName,LinkType,Target
Get-Item "server\shared" -Force | Format-List FullName,LinkType,Target
```

Expected result:

```text
LinkType : SymbolicLink
```

### GitHub / clone notes

Git should track the links as symlinks, not as copied folders. Before committing, verify:

```powershell
git ls-files -s client/shared server/shared
```

The mode should be `120000` for both entries.

On Windows, enable symlink support before cloning/checking out if needed:

```powershell
git config --global core.symlinks true
```

If a fresh clone creates plain files/folders instead of symlinks, recreate the links with the commands above.
