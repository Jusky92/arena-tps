# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Arena TPS** — a 3D third-person multiplayer deathmatch shooter (up to 16 players, free-for-all) set in a Japanese district "NEO-EDO" mixing a traditional temple area with Tokyo neon. The project is the practical support for a **micro-services architecture** course assignment.

Built by two people on separate, independent tracks:
- **`front/`** — the Godot 4.7.2 project. It holds **both the game client and the dedicated game server** (one project, two exports). Julien's responsibility for the client; the server side (`scripts/server/`) is where it meets Elian's backend.
- **`services/`** — only a placeholder README. The real micro-services are Elian's separate repo `TPSArena_backend`, checked out next to this one at `../../backend/` (spec: `../../project-context.md`).
- **`tools/`** — Python/shell/GDScript utility scripts that *generate* assets (textures, sounds, fonts), export the client and the server (`build_client.sh`, `build_server.sh`) or launch the exported server (`lancer_serveur.sh`). They are not part of the runtime game.

There is no build system, package manager, or test runner in this repo — it's a Godot project plus some offline asset-generation scripts.

## Commands

**Run the game**: open `front/project.godot` in the Godot 4.7.2 editor and press F5. `front/` must stay on exactly this Godot version — opening it with another version converts the project files and causes conflicts for the other dev.

**Run the dedicated server** locally (from `front/`): `godot --headless -- --server --bots 2 --duration 60` (also `--map neo-edo|hikari-mall`, `--max-players 1..16`, 16 by default), then start clients with `godot`, log in with "Jouer hors ligne" and REJOINDRE `127.0.0.1` (the join-by-address box only shows in offline mode). In the editor: Debug → Customize Run Instances, first instance with `--headless -- --server`. With the real backend (stack from `backend/`: `docker compose up -d`), add `--serverlist-url http://localhost:8002 --public-address <IP>` and set `GAME_SERVER_SECRET` (same value as `backend/.env`). Test accounts: register in the game, and read the code in Mailpit (http://localhost:8025).

**Export the client** (Windows/Linux/macOS standalone builds, to hand out to players):
```bash
tools/build_client.sh            # Windows build (default)
tools/build_client.sh linux
tools/build_client.sh macos      # build/macos/ArenaTPS.zip, universal, ad-hoc signed (not notarized)
tools/build_client.sh all        # all three
```
Requires `godot` on PATH (or `GODOT=/path/to/godot`) and export templates installed once in the editor. Output goes to `build/` (gitignored).

**Launch the exported Linux server against the real backend**: `tools/lancer_serveur.sh [extra server args]`. It reads `GAME_SERVER_SECRET` from `../../backend/.env`, detects this PC's IP for `--public-address` (lists every address when there are several; override with `ADRESSE_PUBLIQUE=`), and refuses to start a second server on the same port.

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

### Back-end access (`Backend` autoload)

`front/scripts/backend/backend.gd` is a facade, the only thing screens talk to. It keeps the shared state (`user`, `party` with each member's `class_id`, sent with `sync_party_class()` so the play page shows every member's character, `friends`, `incoming`/`outgoing` friend requests, `invites`) and its signals (`party_changed`, `friends_changed`, `invites_changed`, `match_ready`, `session_lost`, `services_changed`, `toast`). It delegates to one of two implementations with the same functions and the same data shapes:
- `bff_backend.gd` is the real backend: HTTP to the BFF (`http://<host>:8000`) through `scripts/shared/api_client.gd`, and a WebSocket to Real-time (`ws://<host>:8005/ws`) through `realtime_client.gd` for presence and notifications (`party.invite_sent`, `party.updated`, `party.match_ready`, `friend.*`, `progress.*`). Tokens are kept in memory only. The access token is refreshed 60 s before expiry, or once on a 401, then re-sent to Real-time.
- `simulated_backend.gd` is "Jouer hors ligne" on the login screen: no network, fake data. Online launch and public servers return an error there; you play LAN by IP (the main menu shows the join-by-address box only in this mode).

The mode and the backend host (typed on the login screen) are saved in `user://reseau.cfg`. Players log in with their email **or** their username (`identifier`); an unverified account that logged in by username is asked for its email on the code screen. Functions are `await`ed and return `{ok, error, message, …}`. `error` is the backend's error code (API contract), and `ApiClient.ERROR_MESSAGES` maps it to French. When adding a backend feature, add it to both implementations and the facade.

Online flow: the party leader clicks LANCER EN LIGNE, which calls `Backend.launch_party(GameState.online_settings)` right away (bots and duration from the last launch, sent as `match_settings`) and returns its ticket. There is no separate settings page: the leader adjusts bots, duration and map in the game server's lobby, then starts there (see "Server ↔ backend"). The other members get theirs through `match_ready` (Real-time `party.match_ready`). Everyone calls `Net.join(address, name, port, ticket)`. Public servers: `get_servers()`, then `get_join_ticket()`. Offline matches (bots, training) are never reported: stats only come from the dedicated server's `match.finished`.

`Backend.BUILD_VERSION` must match between client and server, and it filters the public server list. Bump it when the network protocol changes.

### Client and dedicated server in one project

`front/scenes/boot.tscn` (`scripts/boot.gd`) is the main scene. It opens the dedicated server (`scenes/server/server.tscn`) when the `dedicated_server` feature is set (server export), `--server` is in the user args, or the display is headless; otherwise the login screen. Server-only code lives in `front/scripts/server/`, code shared with offline play in `front/scripts/shared/` (`MatchRules`: spawns, nav bake, shield rule, ranking; `Uuid`). Existing files were deliberately not moved (moving files outside the editor breaks `.tscn` references).

### Networking (`Net` autoload)

`front/scripts/net/net.gd` is the online layer for **both sides** (ENet, UDP 24567). Every `@rpc` is declared there, on `/root/Net`, so client and server always declare the same RPCs; `Net.is_server()` tells which side runs. The header comment lists the protocol.

- The **dedicated server** (`scripts/server/server_main.gd`) doesn't play. It runs forever: `idle` (lobby) → `in_progress` → `ending` → `idle`, the same states as the backend's Server List. `server_game.gd` is the match on the server: map, bots (`BotBrain` reads `game.players`, `roam_points`, `nav_map` by duck typing), damage, deaths, respawns, timer.
- **Authority (first step)**: each client simulates its own player and sends its state to the server at `STATE_HZ`; the server rebroadcasts everyone's state (bots included). The shooter reports hits (`Net.hit`); only the server applies damage and broadcasts results with the reliable `push_health` / `push_death` / `push_respawn` / `push_match_over` RPCs. Clients never talk to each other (`server_relay` off). Moving to full server simulation from `PlayerCommands` is the planned next stage.
- **Identity**: the handshake (`_hello`) carries the player's `user_id` (`Backend.user_id()`), a join ticket (empty in LAN) and `BUILD_VERSION`. The server refuses a different version, a human player beyond `Net.max_players` (`--max-players`, 16 by default), or an account already connected. Players can join a match in progress (a bot gives up its slot if needed).
- **LAN lobby**: the first accepted player is the leader (`Net.leader_id`, reassigned when they leave). Only the leader can change bots/duration (`request_settings`) and start (`request_start`); the server checks it.
- Bots have negative ids, are simulated only on the server, and are puppets on clients.

### Server ↔ backend (`BackendLink`)

All of the server's backend calls go through `scripts/server/backend_link.gd`: register, heartbeat, ticket verification, `player.match` and `match.finished` events (sent over HTTP to the Server List, which publishes them; the game server has no Redis access). There are two implementations:
- `LanLink` (default) accepts every ticket and logs the events.
- `ServerListLink` (`--serverlist-url http://host:8002` plus the env var `GAME_SERVER_SECRET`) does the real calls.
  - It registers and re-registers on `404 server_not_found`, and heartbeats every 5 s.
  - The heartbeat reply tells it about a reservation (`reserved` signal). The reply also carries the party's `match_settings`, which `server_main.gd` applies for that match only (back to the `--bots`/`--duration` defaults afterwards). The reply also names the party leader (`leader_id`), who becomes the lobby leader (`Net.leader_user_id`, `Net.set_party_leader()`) and changes the settings (`request_settings`) and starts the match (`request_start`) once the server is `reserved` (`Net.can_edit_settings()`, `Net.lobby_status()`). If the leader's ticket expires unused, the first connected member gets the lead. The Server List keeps the reservation as long as players are connected.
  - At match end it sends `match.finished`, then disconnects everyone (`Net.close_all`) and goes back to `idle`.
  - `Net.lan_lobby = false` in that mode: the leader comes from the party, not from the connection order.

Keep the event payloads shaped like the backend's Pydantic models (`backend/libs/common/tpsarena_common/events.py`): `match.finished` has one row per `user_id`, bots excluded, placements computed bots included.

**GDScript pitfall:** `start()`, `report()` and `verify()` are coroutines in the base class too (they contain an `await`). GDScript decides from the *static* type whether a call awaits a coroutine. Calling, through a `BackendLink`-typed variable, a method that is a coroutine only in the subclass crashes the engine after the await (corrupted stack, signal 11). Keep any method a subclass makes async async in the base class too.

### Specialists, classes (loadouts) and weapons

Two separate choices, both data-driven:
- **Specialist** = the character: appearance, HP, speed and ability. `ClassData` resources in `front/data/classes/*.tres` (schema `front/scripts/data/class_data.gd`), listed in `GameState.CLASSES` (tank, assassin, tireur, oni). Chosen on the SPÉCIALISTES screen (`class_select.tscn`), kept in `GameState.selected_class`. Its id for the backend is the `.tres` basename (`GameState.class_id()`), sent to the party with `Backend.sync_party_class()`.
- **Class** = the equipment (loadout): `{name, primary, secondary}` weapon ids plus 2 grenades, any specialist can use any class. Up to 10 per player, edited in the CLASSES tab (`LoadoutEditor`, `front/scripts/ui/loadout_editor.gd`), chosen on the JOUER page. `GameState.loadouts` / `selected_loadout`, saved locally in `user://loadouts.cfg` and on the account through `Backend.get_loadouts()` / `save_loadouts()` (Social `GET/PUT /loadouts/me`, which checks the weapon ids).
- **Weapons**: `WeaponData` resources in `front/data/weapons/*.tres` (schema `front/scripts/data/weapon_data.gd`: damage, fire rate, magazine, spread, zoom, 3D model). `WeaponCatalog` (`front/scripts/data/weapon_catalog.gd`) lists the class weapons (`WEAPONS`), the grenade and the pickup-only specials, and sanitizes loadouts. Add a weapon by creating its `.tres` and adding it to `WEAPONS` (and to Social's allowed weapon list).

The server judges hits by zone (head or body, `MatchRules.is_headshot`), with the shooter's weapon and specialist.

`GameState` (autoload) also holds the other cross-screen state: match mode/duration/bot count, offline map (`map_id`), online launch settings (`online_settings`).

### Character rig / animation

Two parallel character pipelines under `front/scripts/character/`:
- **Human players** (`human_rig.gd` + `human_designs.gd` + `aim_ik_modifier.gd` + `cyber_suit.gdshader`): imported humanoid rig, animation blending driven by speed, then a post-animation IK pass that twists the lower body toward movement and the torso/hands toward the aim direction.
- **Training dummies** (`character_rig.gd` + `character_designs.gd`): procedural robot mannequins, no IK pass.

Animation state is driven entirely by observable character state (velocity, grounded, crouched, aim angle) — in multiplayer this state is exactly what gets broadcast (`player.net_state()`) so remote players animate correctly without extra sync logic.

### Maps

`MapCatalog` (`front/scripts/maps/map_catalog.gd`) lists the playable maps: `neo-edo` (default) and `hikari-mall` (abandoned mall, 100×100 m, 2 levels, `mall_map.gd` + `scenes/maps/mall.tscn`). Each map scene's script extends `ArenaMap` and answers the same questions (spawn points, pickups, training targets, bot navigation). The map id travels in the lobby settings and goes to the backend (Server List, `match.finished`). Who picks it: the dedicated server's `--map` (default for its matches), the LAN lobby leader, the JOUER page's offline map list for solo and training, and the party's `match_settings.map` when it sends one. Add a map by creating its scene and adding it to `MapCatalog.MAPS`.

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
