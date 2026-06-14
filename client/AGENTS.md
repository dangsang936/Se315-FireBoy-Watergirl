# AGENTS.md

## Project
Godot 4.x game project.

## Coding rules
- Use typed GDScript.
- Use tabs for indentation in `.gd` files.
- Prefer composition over inheritance.
- Keep scripts small and focused.
- Do not rename nodes, scenes, resources, or signals unless explicitly asked.
- Do not edit `.tscn` manually unless necessary.
- Prefer editor-safe changes through scripts/resources.

## Godot rules
- Use Godot 4 APIs only.
- Avoid outdated Godot 3 syntax.
- Use exported node references where practical.
- Avoid fragile string-based `get_node()` paths.
- Keep collision layers/masks documented.

## Safety
- Before large changes, explain intended files.
- After changes, run a parse/check step when available.
- Never delete assets or scenes without explicit instruction.

<!-- SPECKIT START -->
Current Speckit plan: `specs/003-precision-player-movement/plan.md`
<!-- SPECKIT END -->
