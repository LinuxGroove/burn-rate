# Burn Rate

A 3D jetpack runner seen side on, through a downtown tower with three depth lanes, for one player and party races of 2–8 (up to four on one screen, plus LAN and online), in Godot 4.7 with GDScript, built from Quaternius' sci-fi and city kits. The concept is idea 22 in [game-ideas](https://github.com/LinuxGroove/game-ideas/blob/main/ideas/22-burn-rate.md). Online play goes through the shared [game server](https://github.com/LinuxGroove/game-server); **read game-ideas' [online-addon.md](https://github.com/LinuxGroove/game-ideas/blob/main/online-addon.md) before touching networking, online or the shared add-on.**

## Commands

```sh
godot --headless --path . --import
godot --headless --path . tools/check_scripts.tscn                  # every script compiles
godot --headless --path . tests/run_tests.tscn -- --games=2         # unit tests and whole bot runs
godot --headless --path . tests/run_tests.tscn -- --only=test_gadgets   # one test
godot --path . -- --solo                                            # straight into a run
godot --path . -- --solo --mode=party --bots=3                      # a party race against bots
godot --path . -- --solo --zone=servers --pack=k4                   # start in a zone with a jetpack
godot --headless --path . tools/sim_check.tscn -- --skill=average --runs=8   # how far bots fly, and what kills them
godot --headless --path . tools/gauntlet.tscn -- --skill=average --d=1.0     # every pattern at a difficulty, and which ones are unfair
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 tools/shot.tscn -- --out=/tmp/shot.png --at=900
python3 tools/make_icon.py                                          # the icon: icon.svg, the snap's copy and icon.png
```

Run the script check and the tests before every commit, and `sim_check` with the novice and average bots after changing patterns, zones, speeds or the autopilot. A new `class_name` needs an `--import` before the script check finds it. Headless runs reimport assets and rewrite many `*.import` files and `icon.png.import`; revert those (`git checkout -- '*.import'`, `rm icon.png.import`) unless you meant to change them.

## Layout

| Path | What |
|---|---|
| `game/game_config.gd` | `GAME_ID`, `PROTOCOL`, player limits, `QUICK_MATCH_SIZE`, setting defaults (pace, lanes, comfort, detail), input map |
| `game/run/` | The run with no nodes: `Run`, `Pilot`, `RunInput`, `RoomGen`, `Patterns` (what goes in a room), `Zones`, hazards, pick-ups, `Packs` (the six jetpacks), `Course`/`Courses`, `Autopilot` |
| `game/view/` | `RunView` (draws a `Run`), `RoomView`, `HazardView`, `PilotView`, `RunCamera`, `Look` (sky, light, the city), `Kit` (models by name), `fx/` shaders |
| `game/people/` | `Person`: Universal Base Characters with hair, outfits drawn by a shader, and the animation libraries |
| `game/play/` | `RunScene`: steps the run with this device's controls and bots, and hands events to the view, HUD and sound |
| `game/ui/` | Title, HUD, pause menu, results, Hangar, lobby, how to play |
| `game/audio/` | `RunAudio`: the run's sounds and music |
| `game/net/session.gd` | `Session` autoload: lobby, couch seats and transport for solo, LAN, online rooms and quick match |
| `game/net/run_net.gd` | `RunNet`: party races between devices |
| `game/net/online_server.gd` | Default game server; `SERVER_KEY` stays `defaultkey` in git |
| `game/progress.gd` | `Progress` autoload: credits, packs and upgrades, missions, bests, the Daily Flight and Courses (user://progress.cfg) |
| `addons/quaternius/` | Quaternius' Modular Sci-Fi MegaKit, Sci-Fi Essentials Kit and Downtown City MegaKit (CC0), from LinuxGroove/quaternius-assets |
| `addons/linuxgroove/` | Shared LinuxGroove add-on (settings, input and seats, theme, LAN, online, names, play tests) |
| `addons/com.heroiclabs.nakama/` | Vendored Nakama client with a local patch (see its `VENDORED.md`) |
| `assets/people/` | The base characters, their hair and the animation libraries |
| `assets/models/` | Models made for the game (the jetpack, from `tools/jetpack.py`) |
| `tests/` | `run_tests.gd` runs every `*_tests.gd` here; each `test_*` method gets the runner as `t` and calls `t.check(ok, "what")` |
| `tools/` | Script checker, `sim_check` and `gauntlet` (bot balance), `shot` (a screenshot of a run), `probe_models.gd`, the icon, `version.sh`, `release.sh` |

## How the game is built

- **The run has no nodes.** `Run` steps at 60 Hz (`Run.DT`) from a seed and the pilots' `RunInput`s, so the same seed and inputs always play the same way and tests fly whole runs headless. `RunScene` steps it in `_physics_process`; `RunView`, the HUD and the sounds only read it and its events (`take_events()`).
- **Space.** x runs along the run (the screen's right), y up from the floor (the room is `Run.CEILING`, 8 m), and three lanes, 0 nearest the camera; `RunView.lane_z()` turns a lane into z. Rooms are `Kit.TILE` (4 m) wide. The camera only follows in x, never shakes, zooms or rolls.
- **Rooms and patterns.** `RoomGen` fills the rooms ahead from the seed: each zone (`Zones`) lists the patterns it uses and the difficulty each starts at, and `Patterns` places hazards, credits and crates with numbers that scale by difficulty (`by_d(easy, hard)`). Classic mode is one lane: patterns that need lanes are skipped.
- **Fairness.** Every hazard warns before it can hit (`warning()`), and `test_patterns_fair` flies the average bot through every pattern at its zone's difficulty. `tools/gauntlet.tscn` shows which patterns crash which bots. Judge difficulty with the novice and average bots, not the expert.
- **Burn.** Near misses and credits raise Burn up to x5 (`Pilot.BURN_STEPS`), which adds speed and multiplies credits; a hit, or running along the floor for longer than `Pilot.FLOOR_GRACE`, drops it. A hit with a shield or on a vehicle costs that instead of the run.
- **Pilots and jetpacks.** `PilotView` puts a `Person` in a flight suit with the jetpack on the `spine_03` bone. The pack is placed in the skeleton's rest space; keep the skeleton's own transform in that maths when changing it. Each prototype in `Packs` paints the pack's trim and flame.
- **Comfort.** Reduce flashing sets the `steady` shader global, so zappers and lasers glow steadily; Calm background dims the city and the far wall. Never add camera shake, zoom or roll.
- **Detail.** Handhelds run the Mobile renderer at low detail (`RunScene.detail()` is 0): fewer lights, no far city, simpler effects. Check both after changing how something looks.
- **Host-authoritative races.** In party races over LAN and online, peer 1 runs the `Run` and its bots; clients send their inputs (`_c_*` RPCs) and the host sends state (`_h_*`), always with `rpc_id`. Couch pilots are seats of their device's peer.
- **One Session for every mode.** Solo, couch, LAN, online rooms and quick match all run the same code. Follow the rules in online-addon.md: never attach the bridge's peer yourself, never send a second hello, no `await` between joining and setting `mode`.
- **Bump `PROTOCOL`** whenever any RPC's arguments or meaning change.
- **Online results** go to the game server's `burn-rate` module (`modules/src/games/burn-rate.ts` in game-server): party race results from the host, and endless, Daily Flight and Course scores to their boards. Changing what's reported means changing that module too, and deploying the server first.
- **Play tests.** The shared add-on's `LGPlaytest` records a play test when the Play test recording setting is on (or with `-- --playtest`): a picture every few seconds, game events, frame times and controls, the player's notes (F8, or Note this moment in the pause menu) and a survey when they quit, all in one zip in `user://playtest/`. Game events go through `LGPlaytest.event()` and `moment()`; the round's own survey questions (and standard ones to skip) are `GameConfig.PLAYTEST`. Quit through `LGScenes.quit()` so the survey comes first.
- **Everything works offline.** No server, no network and online turned off must all still play.
- **Launch ping.** `game/main.gd` calls `LGLaunchPing.send(GameConfig.GAME_ID)` at startup: one anonymous request to the game server's `/launch` (game, random install id, version, OS, CPU) so the server counts every player, online or not. It's skipped headless, from source and with `DO_NOT_TRACK` set, and never blocks or retries.

## The shared add-on

`addons/linuxgroove/` and `addons/com.heroiclabs.nakama/` are copies shared with [Foam Frenzy](https://github.com/LinuxGroove/foam-frenzy), [Graveyard Hollow](https://github.com/LinuxGroove/LampLighters), [Tiptoe](https://github.com/LinuxGroove/tiptoe), [Joyride Junction](https://github.com/LinuxGroove/joyride-junction), [Block Party: Skyway](https://github.com/LinuxGroove/block-party-skyway), [Race Day](https://github.com/LinuxGroove/race-day) and [Verdigris Protocol](https://github.com/LinuxGroove/hull-bloom). Fix shared behaviour in the add-on, not with a workaround here, keep it game-agnostic, and port the change to the other games in the same piece of work. When the change affects how games should use the add-on, update online-addon.md in game-ideas too. Keep the `_disconnect_peer` and `_close` patch in `NakamaMultiplayerPeer.gd` when updating nakama-godot.

## Style

- Match the surrounding code: `##` doc comments on classes and non-obvious functions, short comments only where the reason isn't obvious.
- Connect signals with methods (or `bind`), not lambdas; a lambda on an autoload signal stays connected after its screen is freed.
- Build pieces so tests can drive them without a network or a scene change: `Run` needs no nodes, and UI panels build without a run.
- Controller first: everything works with a pad, and the mouse and keyboard always work too. One button flies; lanes are up and down.
- Player-facing text is plain and short, in the game's words (runs, lanes, Burn, credits, prototypes, the Hangar).

## Testing online

Prefer a local game server to `play.linuxgroove.com`, since test runs create real accounts and rooms. online-addon.md describes running one in LXD or Docker and the two-instance tests for joining by code and quick match. Device logs live in `~/snap/burn-rate/common/.local/share/burn-rate/logs/godot.log`.

## Releases

Pushing to `main` builds the snap and publishes it to the `edge` channel; a GitHub release publishes to `candidate`. The **Windows and macOS** workflow (`desktop.yml`) exports both from Linux with the `Windows Desktop` and `macOS` presets: pushes to `main` keep the zips as artifacts for 5 days, and releases get them attached. They aren't signed by Microsoft or Apple, and the release notes tell players how to open them. CI injects the server key from the `GAME_SERVER_KEY` secret, so never commit the real key.

Versions are `vYYYY.WW.MINOR`, derived from git by `tools/version.sh` (`2026.41.0` on a tag, `2026.41.0+3.g1a2b3c4d` after it); CI stamps it into `project.godot` before building and nobody edits it by hand. Make releases with the **Release** workflow (Actions, Release, Run workflow), which refuses commits whose CI hasn't passed. Commit subjects become the release notes, so write them for players.
