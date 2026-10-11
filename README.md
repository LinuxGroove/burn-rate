# Burn Rate

*Hold to fly. Change lanes to live. Fly close to burn hotter.*

A 3D jetpack runner through a downtown tower, seen from the side, with three
lanes deep into the building to dodge between. For one player, and party
races for two to eight on one screen, on the local network and online. For
Linux PCs and handhelds, made with Godot 4. Part of
[LinuxGroove Games](https://linuxgroove.com); the concept is idea 22 in
[game-ideas](https://github.com/LinuxGroove/game-ideas/blob/main/ideas/22-burn-rate.md).

## How it plays

You're a test pilot for Kestrel Lift, a jetpack startup, and you've just
taken one of the prototypes out of the lab. Flying down through the tower
and out over the city, you meet Halberd Security's zappers, lasers,
seekers, drones and shutters.

- **One button flies**, up and down change lanes. Every hazard warns you
  before it can hit, and its lane is lit on the floor.
- **Burn.** Skimming past a hazard and taking credits raise your Burn up to
  x5, which speeds you up and multiplies your credits. A hit, or running
  along the floor, puts it out.
- **Six zones**: the Test Lab, the Server Hall, the Robot Bay, the Atrium,
  Downtown over the rooftops, and Halberd's own floor.
- **Hijacked robots.** Crates hold Halberd's robots to ride for a while:
  the Raptor stomps the smaller robots, the Shell runs on the floor and the
  ceiling, the eye drone hovers, and the gun drone shoots.
- **Modes**
  - **Fly**: an endless run at Calm, Normal or Fast, with lanes or in
    Classic (one lane).
  - **Daily Flight**: the same run for everyone today, with the day's
    prototype, your best ghost and an online board.
  - **Courses**: thirty set courses, five per zone, with medal times and
    ghosts.
  - **Last One Flying**: a party race where the screen won't wait. Fall off
    its left edge and you're out; last pilot flying takes the round. Up to
    four on one screen, up to eight over the local network or online, in a
    room with a code or by quick match (bots fill in if nobody turns up).
- **The Hangar.** Missions raise your rank, and ranks open the six
  prototypes (K-1 Steady, K-2 Kick, K-3 Glide, K-4 Pulse, K-5 Switch and
  K-6 Mule) and suits. Credits buy more suits and gadgets: a magnet, lane
  hints, a shield, a head start, a seeker jammer and a reboot.
- **Comfortable to watch.** The camera only slides along with you: no
  shake, zoom or roll. Reduce flashing makes zappers and lasers glow
  steadily, and Calm background dims the city behind.

When the game starts with the internet on, it tells the LinuxGroove game
server once, so we can count how many people play and on what: a random id
made on the first run, the game's version, the OS and the CPU, and nothing
else. It never signs in, and with no network nothing is sent. Set
`DO_NOT_TRACK=1` to turn it off. Everything except online play works with no
network at all.

## Controls

Controller first; the keyboard and mouse always work.

| Action | Controller | Keyboard and mouse |
|---|---|---|
| Fly (hold) | A or RT | Space, Shift or left click |
| Lane back (farther) | Up, LB or left stick up | Up or W |
| Lane forward (nearer) | Down, RB or left stick down | Down or S |
| Fly again | Y | R |
| Pause | Start | Esc or P |

## Building and testing

You need Godot 4.7.

```sh
godot --headless --path . --import
godot --headless --path . tools/check_scripts.tscn             # every script compiles
godot --headless --path . tests/run_tests.tscn -- --games=2    # unit tests, bot runs and party races
godot --path . -- --solo                                       # straight into a run
godot --path . -- --solo --mode=party --bots=3                 # a party race on one screen against bots
```

`CLAUDE.md` lists the rest of the tools: bot balance checks, screenshots,
a two-copy network race and the sound synthesizer.

## Snap

`snapcraft pack` builds a strictly confined snap, `burn-rate`, with the
exported game. Pushing to `main` builds the snap and publishes it to the
`edge` channel; a GitHub release publishes to `candidate`. The **Windows and
macOS** workflow exports both from Linux and attaches the zips to releases.

Code is MIT (see `LICENSE`); assets and other credits are in
[CREDITS.md](CREDITS.md).
