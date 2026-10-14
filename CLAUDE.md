# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Arena TPS** — a 3D third-person multiplayer deathmatch shooter (8 players, free-for-all) set in a Japanese district "NEO-EDO" mixing a traditional temple area with Tokyo neon. The project is the practical support for a **micro-services architecture** course assignment.

Built by two people on separate, independent tracks:
- **`front/`** — the Godot 4.7.2 project. It holds **both the game client and the dedicated game server** (one project, two exports). Julien's responsibility for the client; the server side (`scripts/server/`) is where it meets Elian's backend.
- **`services/`** — only a placeholder README. The real micro-services are Elian's separate repo `TPSArena_backend`, checked out next to this one at `../../backend/` (spec: `../../project-context.md`).
- **`tools/`** — Python/shell/GDScript utility scripts that *generate* assets (textures, sounds, fonts) or export the client. They are not part of the runtime game.

There is no build system, package manager, or test runner in this repo — it's a Godot project plus some offline asset-generation scripts.

## Commands

**Run the game**: open `front/project.godot` in the Godot 4.7.2 editor and press F5. `front/` must stay on exactly this Godot version — opening it with another version converts the project files and causes conflicts for the other dev.

**Run the dedicated server** locally (from `front/`): `godot --headless -- --server --bots 2 --duration 60`, then start clients with `godot` and REJOINDRE `127.0.0.1`. In the editor: Debug → Customize Run Instances, first instance with `--headless -- --server`.

**Export the client** (Windows/Linux standalone build, for giving to the other player):
```bash
tools/build_client.sh            # Windows build (default)
tools/build_client.sh linux
tools/build_client.sh all
```
Requires `godot` on PATH (or `GODOT=/path/to/godot`) and export templates installed once in the editor. Output goes to `build/` (gitignored).

**Export the dedicated server**: `tools/build_server.sh [windows|linux|all]`, using the presets "Serveur Windows" / "Serveur Linux" (Dedicated Server, resources kept). Output goes to `../server/` (`TPSArena_Jeu/server/`, outside this repo).

**Regenerate generated assets** (only needed after touching the generator scripts themselves — outputs are committed, not built on every run):
```bash
python tools/generate_textures.py      # tileable map textures (numpy, pillow)
python tools/generate_suit_masks.py    # character outfit masks from skinning weights
python tools/generate_sounds.py        # all SFX, pure synthesis, no external audio
python tools/subset_font.py            # strips the Japanese font to used glyphs
```
`tools/extract_animations.gd` is run from inside the Godot editor, not the shell.

There are no automated tests. Verifying a change means running the game in the editor and exercising the affected screen/flow (see the `run`/`verify` skills).

## Architecture

### Inputs vs. simulation (`PlayerCommands`)

The central design idea, used everywhere a character is controlled: a character never reads the keyboard/mouse directly. Every frame, something fills a `PlayerCommands` object (`front/scripts/player_commands.gd`) — move vector, look delta, jump/crouch/sprint/fire/aim/reload/ability — and the character (`front/scripts/player.gd`) simulates from that struct alone.

- The local human player fills it from `Inputs` (autoload, `front/scripts/inputs.gd`).
- A bot fills it from its AI (`front/scripts/bots/bot_brain.gd`).

This split exists so the dedicated server can later drive the simulation from commands sent over the network (full server authority) without touching the character code. Keep this separation when adding new controllable behavior — don't branch on "is this a bot" inside `player.gd`.

### Simulated back-end (`Backend` autoload)

`front/scripts/backend/backend.gd` fakes every BFF route the real micro-services architecture will eventually expose (`register`, `verify_email`, `login`, `get_profile`, `get_friends`, `get_servers`, `report_match`, etc.). Login accepts anything, social/leaderboard data is fabricated, local match stats are saved to `user://profil_simule.cfg`. All functions are `async` (called with `await`) specifically so that swapping their bodies for real `HTTPRequest` calls later won't require touching any screen. **When adding a new back-end-shaped feature, add a function here first following this same signature convention** rather than hardcoding data in a screen script.

### Client and dedicated server in one project

`front/scenes/boot.tscn` (`scripts/boot.gd`) is the main scene. It opens the dedicated server (`scenes/server/server.tscn`) when the `dedicated_server` feature is set (server export), `--server` is in the user args, or the display is headless; otherwise the login screen. Server-only code lives in `front/scripts/server/`, code shared with offline play in `front/scripts/shared/` (`MatchRules`: spawns, nav bake, shield rule, ranking; `Uuid`). Existing files were deliberately not moved (moving files outside the editor breaks `.tscn` references).

### Networking (`Net` autoload)

`front/scripts/net/net.gd` is the online layer for **both sides** (ENet, UDP 24567). Every `@rpc` is declared there, on `/root/Net`, so client and server always declare the same RPCs; `Net.is_server()` tells which side runs. The header comment lists the protocol.

- The **dedicated server** (`scripts/server/server_main.gd`) doesn't play. It runs forever: `idle` (lobby) → `in_progress` → `ending` → `idle`, the same states as the backend's Server List. `server_game.gd` is the match on the server: map, bots (`BotBrain` reads `game.players`, `roam_points`, `nav_map` by duck typing), damage, deaths, respawns, timer.
- **Authority (first step)**: each client simulates its own player and sends its state to the server at `STATE_HZ`; the server rebroadcasts everyone's state (bots included). The shooter reports hits (`Net.hit`); only the server applies damage and broadcasts results with the reliable `push_health` / `push_death` / `push_respawn` / `push_match_over` RPCs. Clients never talk to each other (`server_relay` off). Moving to full server simulation from `PlayerCommands` is the planned next stage.
- **Identity**: the handshake (`_hello`) carries the player's `user_id` (`Backend.user_id()`), a join ticket (empty in LAN) and `BUILD_VERSION`. The server refuses a different version, a 9th human player, or an account already connected. Players can join a match in progress (a bot gives up its slot if needed).
- **LAN lobby**: the first accepted player is the leader (`Net.leader_id`, reassigned when they leave). Only the leader can change bots/duration (`request_settings`) and start (`request_start`); the server checks it.
- Bots have negative ids, are simulated only on the server, and are puppets on clients.

### Server ↔ backend (`BackendLink`)

All of the server's backend calls go through `scripts/server/backend_link.gd`: register, heartbeat, ticket verification, `player.match` and `match.finished` events (sent over HTTP to the Server List, which publishes them; the game server has no Redis access). Today only `LanLink` exists: it accepts every ticket and logs the events, already shaped like the backend's Pydantic models (`backend/libs/common/tpsarena_common/events.py`). Keep that shape when changing results: `match.finished` has one row per `user_id`, bots excluded, placements computed bots included. `ServerListLink` (the real backend) is the next step; see `backend/TODO.md`.

### Data-driven classes and weapons

Classes and weapons are Godot `Resource` (`.tres`) files, editable in the Godot inspector, not code:
- `front/data/classes/*.tres` (schema: `front/scripts/data/class_data.gd`) — HP, speed, weapon, ability, appearance.
- `front/data/weapons/*.tres` (schema: `front/scripts/data/weapon_data.gd`) — damage, fire rate, magazine, spread, zoom, 3D model.

`GameState` (autoload, `front/scripts/game_state.gd`) is the single list of playable classes (`GameState.CLASSES`) and holds cross-screen state (selected class, match mode/duration/bot count). Add a new class/weapon by creating a `.tres` and, for classes, registering it in `GameState.CLASSES`.

### Character rig / animation

Two parallel character pipelines under `front/scripts/character/`:
- **Human players** (`human_rig.gd` + `human_designs.gd` + `aim_ik_modifier.gd` + `cyber_suit.gdshader`): imported humanoid rig, animation blending driven by speed, then a post-animation IK pass that twists the lower body toward movement and the torso/hands toward the aim direction.
- **Training dummies** (`character_rig.gd` + `character_designs.gd`): procedural robot mannequins, no IK pass.

Animation state is driven entirely by observable character state (velocity, grounded, crouched, aim angle) — in multiplayer this state is exactly what gets broadcast (`player.net_state()`) so remote players animate correctly without extra sync logic.

### The arena map

`front/scripts/maps/arena_map.gd` procedurally builds the 120×120m "NEO-EDO" arena (sanctuary, market, "IoT 研究所" lab, pagoda, zen garden, neon alleys — zone breakdown is in the README) as code-driven lists of props, loaded by the standalone scene `front/scenes/maps/arena.tscn`. It's deliberately a separate scene from `game.tscn` so the dedicated server loads just the map. After editing `arena_map.gd`, use the **"Reconstruire la map"** button in the `arena.tscn` scene inspector to regenerate it in the editor — it doesn't rebuild automatically on script save.

Animated/interactive IoT-themed props live under `front/scripts/maps/props/` (security cameras that track the nearest player, live-value sensors, patrol drones, dashboard, etc.) and are added to the map via the same prop-list mechanism in `arena_map.gd`.

### Autoloads (global singletons)

Defined in `front/project.godot` under `[autoload]`: `Inputs`, `GameState`, `Backend`, `Settings`, `Sfx`, `Net`. Any script can reference these by name directly (no explicit import). They also load on the dedicated server, so they must work headless (`Effects` and `Sfx` skip their work when `Effects.headless()`). When introducing new cross-screen state or services, check whether it belongs in an existing autoload before adding a new one.

## Working conventions (from README)

- Godot version is pinned at **4.7.2** for the whole team — never let the editor auto-upgrade the project.
- Never commit `.godot/` (regenerated cache); **do** commit `.uid` and `.import` files (Godot needs them to resolve assets and import settings).
- Avoid two people editing the same `.tscn` scene file simultaneously — they merge badly.
- Branch naming: `front/<topic>` for client work, `services/<topic>` for back-end work.
- Commit messages: short, present tense, prefixed by area, e.g. `front: ajoute le tir par raycast`, `services: crée le service d'authentification`.
- Secrets go in a gitignored `.env`; provide a `.env.example` with no real values.
