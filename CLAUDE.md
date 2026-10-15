# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Arena TPS** — a 3D third-person multiplayer deathmatch shooter (up to 16 players, free-for-all, filled with bots) with two maps: "NEO-EDO", a Japanese district mixing a traditional temple area with Tokyo neon, and "Hikari Mall", an abandoned two-level shopping mall at dusk. The project is the practical support for a **micro-services architecture** course assignment.

Built by two people on separate, independent tracks:
- **`front/`** — the Godot 4.7.2 project. It holds **both the game client and the dedicated game server** (one project, two exports). Julien's responsibility for the client; the server side (`scripts/server/`) is where it meets Elian's backend.
- **`services/`** — only a placeholder README. The real micro-services are Elian's separate repo `TPSArena_backend`, checked out next to this one at `../../backend/` (spec: `../../project-context.md`).
- **`tools/`** — Python/shell/GDScript utility scripts that *generate* assets (textures, sounds, fonts), export the client and the server (`build_client.sh`, `build_server.sh`) or launch the exported server (`lancer_serveur.sh`). They are not part of the runtime game.

There is no build system, package manager, or test runner in this repo — it's a Godot project plus some offline asset-generation scripts.

## Commands

**Run the game**: open `front/project.godot` in the Godot 4.7.2 editor and press F5. `front/` must stay on exactly this Godot version — opening it with another version converts the project files and causes conflicts for the other dev.

**Run the dedicated server** locally (from `front/`): `godot --headless -- --server --bots 2 --duration 60` (also `--map neo-edo|hikari-mall`, `--max-players 1-16`, `--port`, `--name`, `--bot-level faible|moyen|eleve`), then start clients with `godot`, log in with "Jouer hors ligne" and REJOINDRE `127.0.0.1` (the join-by-address box only shows in offline mode). In the editor: Debug → Customize Run Instances, first instance with `--headless -- --server`. With the real backend (stack from `backend/`: `docker compose up -d`), add `--serverlist-url http://localhost:8002 --public-address <IP>` and set `GAME_SERVER_SECRET` (same value as `backend/.env`). Test accounts: register in the game, and read the code in Mailpit (http://localhost:8025).

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
python tools/subset_font.py <full NotoSansJP-Bold.otf>   # strips the Japanese font to the glyphs used in .gd files
```
`tools/extract_animations.gd` is run from inside the Godot editor, not the shell. New sounds must be appended at the end of `SOUNDS` in `generate_sounds.py` (the RNG is seeded, so existing files stay byte-identical) and registered in `Sfx.VARIANTS`. A file with the same name in `front/assets/sounds/custom/` overrides a generated sound (see `LISEZMOI.md` there).

There are no automated tests. Verifying a change means running the game in the editor and exercising the affected screen/flow (see the `run`/`verify` skills).

## Architecture

### Inputs vs. simulation (`PlayerCommands`)

The central design idea, used everywhere a character is controlled: a character never reads the keyboard/mouse directly. Every frame, something fills a `PlayerCommands` object (`front/scripts/player_commands.gd`) — move vector, look delta, jump/crouch/sprint/fire/aim/reload/ability — and the character (`front/scripts/player.gd`) simulates from that struct alone.

- The local human player fills it from `Inputs` (autoload, `front/scripts/inputs.gd`). `Inputs` declares the default keys and applies the player's own (`user://touches.cfg`, edited in the COMMANDES tab of `SettingsPanel`, `front/scripts/ui/settings_panel.gd`: tabs VIDÉO / SON / COMMANDES, shown on the main menu's PARAMÈTRES page and in the pause menu; video choices wait for APPLIQUER, then a window mode or resolution change reverts after 15 s unless confirmed). Show a key in the UI with `Inputs.hint(action)`, never a hard-coded letter.
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
- **Authority ("referee" server)**: each client simulates its own player and sends its state to the server at `STATE_HZ`; the server rebroadcasts everyone's state (bots included). Clients send *actions*, never results: `Net.fire` / `Net.reload` announce each shot (the server holds every magazine in `server_game.gd` `_arsenal` and enforces fire rate), then `Net.hit` reports "I hit target X at offset Y with weapon Z". `server_game.resolve_hit` checks weapon-in-loadout, an announced shot (hit tokens), range, arc for melee/flame, hitbox and line of sight, then picks head/body (`MatchRules.is_headshot`) and computes damage itself. Projectiles and grenades (`Net.fire_projectile`) are simulated only on the server; clients just display them. Pickups and super powers are server-side too. Abilities are announced with `Net.use_ability` (server checks the cooldown and starts the ability on its own copy of the player: shield damage reduction, Archer bullets through up to `MatchRules.PIERCE_WALLS` walls, counted by `_walls_between`).
- **Legendary weapon** (`scripts/shared/legendary_event.gd`, `scripts/ui/legendary_cinematic.gd`): once per deathmatch, at 50-80 % of the duration, the server picks a spot among `map.target_points()`, sets `Engine.time_scale = 0` and `Net.frozen` (actions ignored), sends `push_legendary(0, …)`; after `CINEMATIC_TIME` real seconds (`create_timer(…, ignore_time_scale = true)`) it resumes and adds a `Pickups.Kind.LEGENDARY` pad (`PickupDirector.add_pad`, same id on every side) and sends `push_legendary(1, …)`. Offline, `game.gd` does the same itself. Anything that must run during the freeze uses real time (`Time.get_ticks_msec`). `game.gd` and `server_game.gd` reset `Engine.time_scale` in `_exit_tree`. Results go out with reliable RPCs (`push_health`, `push_death`, `push_respawn`, `push_explosion`, `push_pickup`, `push_special`, `push_aura`, `push_match_over`…). Clients never talk to each other (`server_relay` off). Moving to full server simulation from `PlayerCommands` is the planned next stage.
- **Identity**: the handshake (`_hello`) carries the player's `user_id` (`Backend.user_id()`), a join ticket (empty in LAN) and `BUILD_VERSION`. The server refuses a different version, a human player beyond `Net.max_players` (16 by default, `--max-players`), or an account already connected. Players can join a match in progress (a bot gives up its slot if needed).
- **LAN lobby**: the first accepted player is the leader (`Net.leader_id`, reassigned when they leave). Only the leader can change bots/duration/map/bot level (`request_settings`, stored in `Net.settings`) and start (`request_start`); the server checks it. On a server reserved by a party, the party leader has the same role (see "Server ↔ backend").
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

### Data-driven specialists, loadouts and weapons

Black Ops 2 style: a **specialist** (character, HP, ability) plus a **loadout** ("classe" in the UI: primary + secondary weapon, 2 grenades always included). Specialists and weapons are Godot `Resource` (`.tres`) files, editable in the inspector:
- `front/data/classes/*.tres` (schema: `front/scripts/data/class_data.gd`) — specialists: HP, speed, ability (SHIELD, DASH, PIERCE, CHARGE), appearance. Registered in `GameState.CLASSES`. Chosen on the SPÉCIALISTES screen (`class_select.tscn`), kept in `GameState.selected_class`; its id for the backend is the `.tres` basename (`GameState.class_id()`), sent to the party with `Backend.sync_party_class()`.
- `front/data/weapons/*.tres` (schema: `front/scripts/data/weapon_data.gd`) — damage, pellets, fire rate, magazine, range, spread, zoom, headshot multiplier, projectile/explosion, slow/splat/burn effects, wall piercing (`pierce_walls`), aim assist (`aim_assist_deg`), `legendary`, 3D model. New `WeaponData.Model` / `Pickups.Kind` values are always appended at the end (`.tres` files store the number). A new primary/secondary weapon id must also be allowed by the backend's Social service (`primary_weapons` / `secondary_weapons` in its `config.py`). Registered in `WeaponCatalog` (`front/scripts/data/weapon_catalog.gd`): `WEAPONS` (loadout weapons), `GRENADE`, `SPECIALS` (pickup weapons and effect "weapons" like the shockwave).
- Loadouts (up to `WeaponCatalog.MAX_LOADOUTS` = 10) live in `GameState.loadouts`, saved in `user://loadouts.cfg` and, with the real backend, on the account (`Backend.get_loadouts` / `save_loadouts` → Social `GET`/`PUT /loadouts/me`). Edited and equipped in the CLASSES tab (`LoadoutEditor`, ÉQUIPER POUR JOUER), changed during a match from the pause menu; the JOUER page has no class picker.

`GameState` (autoload, `front/scripts/game_state.gd`) holds cross-screen state: selected specialist and loadout, offline map (`map_id`), match mode/duration/bot count/bot level (solo settings saved in `user://partie_solo.cfg`), online launch settings (`online_settings`).

### Map pickups

`front/scripts/data/pickups.gd` (`Pickups`) defines pickup kinds (heal, armor, double jump, speed, three special weapons, super power) and super powers (overload, shockwave, invisibility, key F). `front/scripts/shared/pickup_director.gd` (`PickupDirector`) runs the pads: authoritative on the server or offline, display-only on online clients (`Net.pickup_states`, `push_pickup(s)`). Pad positions come from the map (`pickup_points()`); pads are drawn by `scripts/maps/props/pickup_pad.gd`.

### Character rig / animation

Two parallel character pipelines under `front/scripts/character/`:
- **Human players** (`human_rig.gd` + `human_designs.gd` + `aim_ik_modifier.gd` + `cyber_suit.gdshader`): imported humanoid rig, animation blending driven by speed, then a post-animation IK pass that twists the lower body toward movement and the torso/hands toward the aim direction.
- **Training dummies** (`character_rig.gd` + `character_designs.gd`): procedural robot mannequins, no IK pass.

Animation state is driven entirely by observable character state (velocity, grounded, crouched, aim angle) — in multiplayer this state is exactly what gets broadcast (`player.net_state()`) so remote players animate correctly without extra sync logic.

### Maps

Maps are standalone scenes under `front/scenes/maps/`, deliberately separate from `game.tscn` so the dedicated server loads just the map. They are listed in `front/scripts/maps/map_catalog.gd` (`MapCatalog`: id, display name, scene). The map id travels in `Net.settings.map` (chosen by the LAN leader, or `--map` on the server), is sent to the Server List and in `match.finished`; on a server reserved by a party, the party leader picks it in the lobby; offline games use `GameState.map_id`, picked in the PARTIE SOLO window that SOLO (BOTS) opens (`_open_solo_panel`: map, 1 to 15 bots, bot level, duration; bot levels are `BotBrain.LEVELS`, each bot draws its skill in the level's range, servers take `--bot-level`) or in the map chooser that ENTRAÎNEMENT opens (`_pick_offline_map`).

- `front/scripts/maps/arena_map.gd` (`ArenaMap`) procedurally builds the 120×120 m "NEO-EDO" arena (sanctuary, market, "IoT 研究所" lab, pagoda, zen garden, neon alleys — zone breakdown in the README), scene `arena.tscn`. `arena_dressing.gd` adds lawns, MultiMesh grass, bushes and cover.
- `front/scripts/maps/mall_map.gd` (`MallMap extends ArenaMap`, reusing its builder helpers) builds the 100×100 m two-level "Hikari Mall" (floor at y = 5), scene `mall.tscn`.
- Game code never reads map constants directly: it asks the map instance `map_id()`, `spawn_points()`, `get_spawn_transforms()`, `pickup_points()`, `target_points()` (training dummies, bot roaming) and `nav_aabb()` (navmesh bake area, `MatchRules.bake_navigation`). A new map overrides these and `build()`.
- Animated props live under `front/scripts/maps/props/` (security cameras on the lamp posts that track the nearest player, lab dashboard, robot arms, conveyor, cherry trees, lanterns, banners, vending machines, koi pond, pickup pads).

After editing a map script, use the **"Reconstruire la map"** button in the scene inspector to regenerate it in the editor — it doesn't rebuild automatically on script save. Japanese text added to a map needs `tools/subset_font.py` to be re-run, or its glyphs won't render.

### Autoloads (global singletons)

Defined in `front/project.godot` under `[autoload]`: `Inputs`, `GameState`, `Backend`, `Settings`, `Sfx`, `Net`. Any script can reference these by name directly (no explicit import). `Settings` also holds the video options (quality preset, window mode, resolution): it applies the quality to every `DirectionalLight3D` (shadows) and `WorldEnvironment` (glow) as they enter the tree, keeping the map's own values in metadata, so maps don't need to know about it. They also load on the dedicated server, so they must work headless (`Effects` and `Sfx` skip their work when `Effects.headless()`). When introducing new cross-screen state or services, check whether it belongs in an existing autoload before adding a new one.

## Working conventions (from README)

- Godot version is pinned at **4.7.2** for the whole team — never let the editor auto-upgrade the project.
- Never commit `.godot/` (regenerated cache); **do** commit `.uid` and `.import` files (Godot needs them to resolve assets and import settings).
- Avoid two people editing the same `.tscn` scene file simultaneously — they merge badly. Don't move files outside the editor (it breaks `.tscn` references).
- Bump `Backend.BUILD_VERSION` (`front/scripts/backend/backend.gd`) whenever the network protocol changes.
- Branch naming: `front/<topic>` for client work, `services/<topic>` for back-end work.
- Commit messages: short, present tense, prefixed by area, e.g. `front: ajoute le tir par raycast`, `services: crée le service d'authentification`.
- Secrets go in a gitignored `.env`; provide a `.env.example` with no real values.
