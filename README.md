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
