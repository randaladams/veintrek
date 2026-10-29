# VeinTrek

A first-person shooter for Android, flown from the cockpit of a micro-ship
travelling through the human bloodstream. Tilt the phone to steer through
branching blood vessels, blast red blood cells (the infected ones shoot back),
and scrape white blood cells off your window before they break it.

Built with **Godot 4.7** (GL Compatibility renderer). Every mesh, texture and
sound is generated in code, so the repo has no binary assets.

## Install on your phone

Every push to `main` builds a debug APK with GitHub Actions and publishes it to
the **Latest build** release:

**https://github.com/randaladams/veintrek/releases/latest/download/veintrek.apk**

Open that link on the phone, then open the downloaded file. Android will ask you
to allow installs from your browser the first time.

The APK is also attached as an artifact to each workflow run under
**Actions → Build Android APK**.

### Keeping updates installable

Android only lets an APK update an existing install when both are signed with
the same key. Store a keystore in the repository secret `DEBUG_KEYSTORE_BASE64`
(base64 of a keystore with alias `androiddebugkey`, passwords `android`) and
every build will be signed with it. Without that secret each build gets a fresh
key, and you'll need to uninstall the old version before installing a new one.

```sh
keytool -genkeypair -keystore debug.keystore -storepass android -alias androiddebugkey \
  -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
gh secret set DEBUG_KEYSTORE_BASE64 --repo randaladams/veintrek < <(base64 -w0 debug.keystore)
```

For a Play Store release you'll want a proper private release key instead.

## How to play

- **Tilt** to steer and aim. Whatever angle you hold the phone at when a run
  starts (during the 3‑2‑1 countdown) becomes centre. Recalibrate from the
  pause menu. The gold dot by the crosshair shows where your tilt is pushing.
- **Hold the right side** of the screen to fire. Lasers go straight to the
  crosshair; there's no aim assist. Auto-fire is available in Settings.
- **Touch the left side** to shock the windshield. It fries every white cell
  stuck to the glass, plus any hunting you nearby. You start each run with
  **3 charges** (max 5). A charge isn't spent if there's nothing to shock.
- **Sharp turns** are announced with flashing chevrons and a countdown in
  metres. Bends throw the ship toward the outside wall, so lean the way the
  arrows point.
- **Red cells** crack your glass if you ram them. **Dark infected cells** with a
  green core shoot plasma at you. Dodge it or shoot them first.
- **White cells** chase you and latch onto the window, draining its strength
  until you shock them off (or they lose their grip after several seconds).
- Pickups: **cyan rings** repair the window, **blue lightning bolts** add a
  shock charge (semi-rare), **gold crystals** upgrade the lasers (rare; Mk‑1 to
  Mk‑5: twin cannons, faster fire, a third cannon, then spread with piercing
  shots).

### Modes

- **Campaign**: six missions from the femoral artery to the heart. Each one
  unlocks the next.
- **Endless**: the vessel never ends and keeps getting faster, narrower and more
  hostile. Chase a high score.

If the tilt directions feel backwards on your phone, flip **Invert left/right**
or **Invert up/down** in Settings.

On a computer: arrow keys / WASD steer, Space fires, E shocks, Esc pauses.

## Project layout

| Path | What it does |
| --- | --- |
| `scripts/main.gd` | Wires the game and menus together; developer command-line flags |
| `scripts/game.gd` | Flight, tilt steering, weapons, collisions, spawning, scoring |
| `scripts/vessel_segment.gd` | One stretch of vessel: curved centreline, sharp turns, radius profile, tube mesh |
| `scripts/vessel_world.gd` | Grows the vessel ahead of the ship and frees it behind |
| `scripts/cockpit.gd` | Cockpit canopy, dashboard gauges, turn warnings, glass cracks, shock effect |
| `scripts/ui.gd` | Title, level select, settings, how to play, pause and results screens |
| `scripts/sfx.gd` | Synthesised sound effects and the heartbeat ambience |
| `scripts/globals.gd` | Settings, save data, campaign level definitions, difficulty curves |
| `scripts/meshes.gd` | Procedural meshes (biconcave red cell, power-ups) and shared materials |
| `scripts/entities/` | Red cells, white cells, power-ups, projectiles |
| `shaders/` | Vessel wall and white cell shaders |

Tuning lives in `scripts/globals.gd`: `LEVELS` for the campaign and
`endless_diff()` for endless mode.

## Running on a computer

Open the folder in Godot 4.7 and press Play. Clicking the window counts as a
touch (left half shocks, right half fires).

Developer flags go after `--`:

```sh
godot -- --start=endless --bot           # jump into endless with autopilot + auto-fire
godot -- --start=campaign:2 --god        # level 3, unbreakable window
godot -- --shots=/tmp/shots --shot-every=2 --shot-count=5   # save screenshots, then quit
godot -- --selftest                      # inject touches and check fire / shock / pause
```
