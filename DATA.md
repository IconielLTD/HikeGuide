# Updating the access-land data

HikeGuide's "can I walk here?" data (CRoW Open Access + Forestry England) is
delivered as **region packs**. This guide covers how to (re)build that data and,
when you're ready, how to host it on GitHub Releases so the app install stays
small.

You don't need GitHub for Part 1. Take it one part at a time.

**The pipeline, in one line:**
`fetch_access.mjs` (download source) → `build_pack.mjs` (slice into regions) →
the app loads the pack for wherever you are.

## Before you start

- Install **Node.js 22+** (`node --version` to check).
- Run every command **from the project root** (`E:\HikeGuideApp`) — i.e. the
  folder this file is in. The commands below already include the `spike/` path.
- The data files are **git-ignored** (they're large and regeneratable). That's
  why, on a fresh clone, you re-run Part 1 to recreate them.

---

## Part 1 — Build the data locally (no GitHub needed)

This pulls the real data and bundles it straight into the app. Good for
development and for covering more of England.

### 1. Fetch the source data (all of England)

```powershell
node spike/fetch_access.mjs
```

This downloads every CRoW + Forestry polygon for England from the public
Ordnance-Survey/ArcGIS servers and writes two files into `assets/access/`. It's
a **large download** — run it on wifi, and give it a few minutes. If it stops
with a network/timeout error, just run it again (it starts over cleanly).

### 2. Slice it into region packs

```powershell
node spike/build_pack.mjs
```

This splits the source into one pack per English region and writes them, plus
`coverage.geojson` (which region covers a point) and `manifest.json` (the list
of packs), into `assets/packs/`. It prints how many parcels landed in each
region.

### 3. See it in the app

```powershell
flutter run
```

Open the **Info** tab → **Offline regions** to see the packs, and the **Now** /
**Map** tabs will show access data wherever you are in a covered region.

That's it — you now have wider England coverage, all bundled in the app.

> **Heads-up:** bundling *all* of England makes the app's download big. When
> that bothers you, move to Part 2.

---

## Part 2 — Host packs on GitHub Releases (smaller install)

Instead of baking every region into the app, you publish the packs once and the
app downloads only the region a user actually visits. This is the same place
your app's APK lives (see `android/SIGNING.md`).

You only need this when the bundled install gets too big — there's no rush.

### 1. Put your code on GitHub

Create a repository on github.com and push this project to it. (If you've never
done this, GitHub's own "Create a repo" guide walks you through it.)

### 2. Pick a tag and build in "remote" mode

A **tag** is just a version label for a release, e.g. `access-2026-06-09`.
Decide one, then build the packs with the download address they *will* have:

```powershell
node spike/build_pack.mjs --base-url https://github.com/<you>/<repo>/releases/download/<tag>
```

Replace `<you>`, `<repo>`, and `<tag>`. This bakes those download links (and a
checksum for each file) into `manifest.json`, instead of bundling the packs.

### 3. Create the Release and upload the packs

On your repo page → **Releases** → **Draft a new release**:

1. In **Choose a tag**, type the exact tag from step 2 and confirm it.
2. Give it a title (the tag name is fine).
3. Drag every `assets/packs/*.geojson` file into the **attach files** box.
   *(Upload `manifest.json` and `coverage.geojson` too if you like — they're
   harmless, but the app uses the bundled copies of those.)*
4. Click **Publish release**.

Each file now has a permanent link like
`https://github.com/<you>/<repo>/releases/download/<tag>/east-midlands.geojson`
— matching what step 2 baked in.

### 4. Stop bundling the big packs

Open `pubspec.yaml` and change the packs asset entry from the whole folder to
just the two small index files:

```yaml
  assets:
    - assets/packs/manifest.json
    - assets/packs/coverage.geojson
```

Then:

```powershell
flutter pub get
flutter build apk --release
```

The app now ships tiny and downloads each region on demand. In the **Info** tab,
regions show a **Download** button; tapping it (or visiting that region) fetches
the pack and caches it for offline use.

> **Tip — offline out of the box:** if you want one "home" region available with
> no download, keep its line in `pubspec.yaml`
> (e.g. `- assets/packs/east-midlands.geojson`) and leave that file in place.

### Advanced: updating packs without a new app version

The steps above bake the pack links into the *bundled* manifest, so adding a
region later needs an app update. If you'd rather update the catalogue
remotely, also upload `manifest.json` to the Release and set
`RegionPackService.remoteManifestUrl` to its URL — the app will fetch the live
manifest on launch and fall back to the bundled one offline.

---

## Notes

- **Attribution (keep it):** CRoW Open Access © Natural England (Open Government
  Licence); Forestry England legal boundary © Crown copyright; map/environment
  data © OpenStreetMap. These are credited in the app's Info tab — leave them in.
- **Region boundaries** are currently approximate rectangles (`spike/regions.mjs`).
  They classify the *data* correctly but the region *labels* can be loose near
  edges. Swapping in real region boundary polygons is a future improvement.
- **Re-running** `build_pack.mjs` is always safe — it overwrites the packs,
  coverage, and manifest from whatever source data is in `assets/access/`.
