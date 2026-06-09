# HikeGuide

A bushcraft field companion for England. HikeGuide helps people connect with
nature by enabling them to feel more like they *could survive out there* — comfortable, oriented, and
unafraid. The aim is to make you feel like the you have your own personal bushcraft guide on your device.

It reads where you are, tells you what's around you (woodland, water, the rules
of the land you're standing on), and offers short, plain-English lessons and
realistic things to try — aimed at adults with **no** prior bushcraft or
Ordnance Survey experience.

> **Status:** Android-only, in active field testing. Built with Flutter 3.44.x / Dart 3.5+.

## Features

Five tabs:

- **Now** — your live position as a grid reference, magnetic declination, the
  environment around you (nearest water + its kind, woodland type), and the
  land-access classification where you're standing. All of it updates live as
  you move and cross boundaries.
- **Map** — an OpenStreetMap basemap with bundled access-land overlays, a live
  pulsing GPS marker, and trip recording. While recording, your route draws in
  amber and renders **lighter where you double back** so you can see where
  you've already been. The "Access" banner opens a plain-language guide to what
  you legally can and can't do here (roaming on CRoW land, going off-path in
  Forestry, fenced areas, fire, etc.).
- **Guides** — short, beginner-friendly how-tos (3–6 steps), generated and
  cached on device.
- **Journal** — your saved trips: distance, duration, step count, and route.
- **Info** — setup (API keys), attribution, and app information.

Trip recording runs as a location **foreground service**, so tracking survives
screen-off and backgrounding. Step count comes from the device pedometer.

## How it works

- **Location** — a single shared `LiveLocation` service is the one source of
  truth for position + access status, consumed by both the Now and Map tabs
  (geolocator allows only one position stream at a time). While recording,
  `TripRecorder` owns the stream and `LiveLocation` mirrors its fixes. The
  stream is released when no location tab is visible, and offscreen tabs pause
  their animations — both to save battery.
- **Access land** — delivered as per-region **packs** (GeoJSON of CRoW Open
  Access + Forestry England, classified offline with point-in-polygon tests).
  The app detects your region offline from a tiny bundled coverage index, then
  loads the matching pack — bundled today, downloadable from GitHub Releases as
  coverage expands, so the install stays small and works offline in the field.
- **Environment** — nearest water and woodland come from the Overpass (OSM) API,
  **cache-first** with bounded retries. Results are stored locally; the app does
  not re-query aggressively.
- **Content** — guides and "opportunities" are generated via the Anthropic
  Messages API (Claude Haiku) and cached in SQLite. Caches are versioned and
  regenerate automatically when the prompts change.
- **Storage** — trips, route points, and content caches live in a local SQLite
  database (sqflite) with versioned migrations. API keys live only in the
  platform secure store (Android Keystore), never in SQLite.

## Getting started

Prerequisites: the Flutter SDK (3.44.x), the Android SDK, and a device or
emulator.

```powershell
flutter pub get
flutter run            # debug build on a connected device/emulator
```

### API keys

Keys are entered in-app on the **Info** tab and stored in secure storage:

- **Anthropic API key** — *required* for generated guides and opportunities.
  Get one at <https://console.anthropic.com/>. Bring-your-own-key: usage is
  billed to your own account. You will have to add credits to your account to use it.
- **OS Maps (OS Data Hub) key** — *optional*, only for the OS "Outdoor"
  basemap. Without it the app uses the default OpenStreetMap tiles.

The app runs without either key but, you won't get generated guides or the
OS basemap until they're set. Which are some of the best parts of the app.

## Distributing a build

HikeGuide ships as a signed APK attached to a **GitHub Release** — people
download and sideload it directly. Quick personal builds need no setup: with
`android/key.properties` absent, the release build falls back to debug signing,
so `flutter run --release` and the command below just work.

```powershell
flutter build apk --release   # → build/app/outputs/flutter-apk/app-release.apk
```

To publish an APK that others can install and **update in place**, sign it with
a stable key you keep — see [`android/SIGNING.md`](android/SIGNING.md). Android
only accepts an update signed with the same key as the existing install, so a
throwaway debug key would force people to uninstall (losing their trips) to take
an update.

## Privacy

Your location history stays on the device. `allowBackup` is disabled and Android
12+ data-extraction rules exclude the database and preferences, so trips and
caches are kept out of cloud backup and device-to-device transfer. There's no
analytics, no background-location permission, and all network calls are HTTPS.

## Testing

```powershell
flutter analyze
flutter test
```

The suite covers the geo math (grid reference, geomagnetic declination,
point-in-polygon, point-to-segment distance), Overpass parsing, access-guidance
content, trip math (distance, duration, steps, retrace flagging), and the
journal repository's save/list plus schema migrations (run on desktop SQLite via
`sqflite_common_ffi`).

## Project layout

```
lib/
  main.dart            App entry; startup cache reconcile + orphan-trip cleanup
  screens/             The five tabs + trip/guide detail screens
  services/            Location, trip recording, Overpass, Anthropic, access,
                       SQLite cache, secure key stores, geo helpers
  models/              Trip, Guide, Opportunity, EnvironmentContext, etc.
  widgets/             GPS marker, position info, access sheet, status views
  theme/               Dark olive Material theme
assets/packs/          Bundled region pack + coverage index + manifest
assets/access/         Source GeoJSON for the packs (not bundled; build inputs)
spike/                 Node scripts to fetch access data + build_pack.mjs
DATA.md                How to (re)build the access-land data + host region packs
android/SIGNING.md     Signing key + GitHub Release builds
LICENSE                PolyForm Noncommercial 1.0.0 (no commercial use)
```

## Data sources & attribution

- **CRoW Open Access** © Natural England, under the Open Government Licence.
- **Forestry England** legal boundary © Crown copyright.
- **Map tiles & environment data** © OpenStreetMap contributors (via Overpass).

Regenerate the bundled access overlays with `spike/fetch_access.mjs`.

## License

Source-available under the **[PolyForm Noncommercial License 1.0.0](LICENSE)**.
You're welcome to use, study, modify, and share HikeGuide for noncommercial
purposes — personal use, learning, hobby projects. **Commercial use, including
selling this app or selling cloned/derivative versions of it, is not permitted.**
