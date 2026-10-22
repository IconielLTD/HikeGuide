# HikeGuide

A bushcraft field companion for England. HikeGuide helps people connect with nature by enabling them to feel more like they could survive out there — comfortable, oriented, and unafraid. The aim is to give them their own personal beginner's bushcraft guide on their device.

It reads where you are, tells you what's around you (woodland, water, the rules
of the land you're standing on), and offers short, plain-English lessons and
realistic things to try — aimed at adults with **no** prior bushcraft or
Ordnance Survey experience.

> **Status:** Android-only. **v1.1.0 released** — see [Install](#install) below. Built with Flutter 3.44.x / Dart 3.5+.

## Install

HikeGuide is Android-only and distributed as a sideloaded APK (it's not on any
app store).

1. On your Android phone, open the **[latest release](https://github.com/IconielLTD/HikeGuide/releases/latest)** and download `app-release.apk` (~53 MB).
2. Tap the downloaded file. The first time, Android will ask to **allow installs
   from this source** — enable it, then install.
3. **Turn that permission back off** once it's installed (Settings → Apps →
   Special app access → Install unknown apps → the browser or file manager you
   used), so nothing else can install apps that way.
4. Open HikeGuide and grant **location** (and optionally **physical activity**,
   which is used for step counting).

**Only install HikeGuide from this repo's
[Releases](https://github.com/IconielLTD/HikeGuide/releases) page** — not from
copies posted anywhere else. Every genuine release is signed with the same key,
whose SHA-256 certificate fingerprint is:

```
75:3A:27:D4:32:49:9A:96:B3:7A:11:E3:FF:26:78:8D:BE:34:B1:33:D7:0D:92:40:BE:07:1C:EE:F9:A9:74:7F
```

To check it, an app such as AppVerifier shows the fingerprint of an installed
app, or on a computer `apksigner verify --print-certs app-release.apk` prints it
as "Signer #1 certificate SHA-256 digest" (the same digits, lower case, without
colons). Android enforces it for updates too: an APK signed with a different key
won't install over HikeGuide.

To get the most out of it, open the **Info** tab and add your API keys. Each key
box has a link underneath it that opens the right sign-up page in your browser:
sign up, copy the key, come back to HikeGuide, paste it in and tap **Save key**.
Keys are kept only in your phone's secure storage.

1. **Anthropic API key** — *for guides and practice opportunities.* Tap
   **Get a key: Claude Console**, sign in, create a key and add a little credit
   to your account. It's bring-your-own-key, so usage is billed to you; each
   guide or set of opportunities costs a fraction of a penny. Paste the key
   (it starts `sk-ant-`) and tap **Save key**.
2. **CARTO basemap key** — *for the dark map.* Tap **Get a key: CARTO** and
   request a free key with your email (no account or card needed), then paste
   and save it. Without it, switch the Map to the OS map instead.
3. **OS Maps API key** — *optional, for the OS "Outdoor" map.* Tap
   **Get a key: OS Data Hub**, create a free account and a project, and add the
   **OS Maps API** to it on the OpenData plan (no card). Paste the project's
   **Project API Key** (not the Project API Secret) and save it.
4. **Overpass server** — *optional, makes woodland and water detection
   reliable.* Without it the app uses free public servers, which are often
   overloaded. Tap **Overpass.ch (free tier)** (or **Other providers**), sign
   up, then paste the full server address your provider gives you, key included
   — e.g. `https://api.overpass.ch/v1/YOUR_KEY/interpreter` — and tap
   **Save server**.

Then **download your region's access pack** in **Info → Offline regions** once,
ideally on Wi-Fi; after that the access map works fully offline in the field.

The app runs without any keys, but guides, opportunities and the map are some
of the best parts. Your trips and location history stay on your device; see
[Privacy](#privacy) for what is shared to make the app work.

## Features

Five tabs:

- **Now** — your live position as a grid reference, magnetic declination, the
  environment around you (nearest water + its kind, woodland type), and the
  land-access classification where you're standing. All of it updates live as
  you move and cross boundaries.
- **Map** — a dark CARTO basemap (or the OS "Outdoor" map, one tap away) with
  per-region access-land overlays
  (downloaded on demand — see below), a live pulsing GPS marker, and trip
  recording. While recording, your route draws in
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
- **Access land** — delivered as per-region **packs** (CRoW Open Access +
  Forestry England, classified offline with point-in-polygon tests). The app
  detects your region offline from a tiny bundled coverage index, then loads
  that region's pack. **Packs download on demand — never automatically.** The
  first time you're in a region, open the **Info** tab and download its pack
  (ideally on Wi-Fi before a trip); after that it works fully offline. The Map
  shows a prompt when you're in a region whose pack you haven't downloaded yet,
  with a shortcut to the Info tab. This keeps the install small and avoids
  surprise mobile-data use.
- **Environment** — nearest water and woodland come from the Overpass (OSM) API,
  **cache-first** with bounded retries. Results are stored locally; the app does
  not re-query aggressively.
- **Content** — guides and "opportunities" are generated via the Anthropic
  Messages API (Claude Haiku 5.5) and cached in SQLite. Caches are versioned and
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
  Get one at <https://platform.claude.com/settings/keys>. Bring-your-own-key: usage is
  billed to your own account. You will have to add credits to your account to use it.
- **OS Maps (OS Data Hub) key** — *optional*, only for the OS "Outdoor"
  basemap.
- **CARTO basemaps key** — needed for the default dark basemap (CARTO has
  required a key since late 2026). Free from <https://carto.com/basemaps/apikey>,
  no account or card needed. Without it, use the OS basemap instead.
- **Overpass server** — *optional*. Woodland and nearest-water detection uses the
  free public Overpass servers, which need no key but are often overloaded. For a
  reliable one, sign up with a keyed provider (e.g. <https://overpass.ch/>, which
  has a free tier; others are listed on the
  [OSM wiki](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances))
  and paste its full server address, key included. It's tried first, with the
  public servers as the fallback.

The app runs without any of these keys but, you won't get generated guides or a
basemap until they're set. Which are some of the best parts of the app.

## Distributing a build

HikeGuide ships as a signed APK attached to a **GitHub Release** — people
download and sideload it directly. Release builds are signed with a stable key
you keep — see [`android/SIGNING.md`](android/SIGNING.md) — so people can
**update in place**:

```powershell
flutter build apk --release   # → build/app/outputs/flutter-apk/app-release.apk
```

Android only accepts an update signed with the same key as the existing
install, so a throwaway debug key would force people to uninstall (losing their
trips) to take an update. That's why a release build **fails** if
`android/key.properties` is missing. For a quick personal release build without
the key, opt in to debug signing — and don't distribute the result:

```powershell
$env:HIKEGUIDE_ALLOW_DEBUG_SIGNING = "1"; flutter build apk --release
```

Debug builds (`flutter run`) need no setup.

## Privacy

Your trips and location history stay on the device. `allowBackup` is disabled
and Android 12+ data-extraction rules exclude the database and preferences, so
trips and caches are kept out of cloud backup and device-to-device transfer.
There's no analytics, no background-location permission, and all network calls
are HTTPS. API keys are kept in the phone's secure storage and are never written
to the device log.

To work, the app does share some information. This is what leaves the phone,
and who receives it:

- **Overpass** (woodland and water detection): your position, **rounded to about
  100 m**, goes to the public Overpass servers (overpass-api.de, run by FOSSGIS,
  and overpass.private.coffee), or to your own Overpass server if you've set one.
  It's sent when you open the Now tab in a new ~500 m area; results are reused
  for 7 days.
- **Map tiles**: CARTO or Ordnance Survey see which map areas you view, as with
  any online map.
- **Anthropic**: the requests for guides and opportunities describe your
  surroundings (region, season, woodland type, distance and direction to the
  nearest water, land-access type) but contain **no coordinates**.
- **GitHub**: region packs are downloaded from this repo's Releases when you
  choose to download them.

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
- **Camping management byelaw zones (Scotland)** © Loch Lomond & The Trossachs
  National Park Authority.
- **Map tiles & environment data** © OpenStreetMap contributors (via Overpass).

Regenerate the bundled access overlays with `spike/fetch_access.mjs`.

## Credits

Created and maintained by **Nathan Osborn** ([IconielLTD](https://github.com/IconielLTD)).

HikeGuide was built with significant AI assistance, disclosed here for
transparency: **[Claude Code](https://claude.com/claude-code)** (Anthropic's
Claude) was used throughout as a pair‑programming assistant for design,
implementation, and review. Commits that were co‑written carry a
`Co-Authored-By: Claude` trailer, so the AI's contribution is visible in the git
history. All direction, decisions, and final review remain the author's.

## License

Source-available under the **[PolyForm Noncommercial License 1.0.0](LICENSE)**.
You're welcome to use, study, modify, and share HikeGuide for noncommercial
purposes — personal use, learning, hobby projects. **Commercial use, including
selling this app or selling cloned/derivative versions of it, is not permitted.**
