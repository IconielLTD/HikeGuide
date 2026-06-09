// Builds per-region access-land packs from the all-England source GeoJSON.
//
// A "region pack" is the on-demand unit HikeGuide downloads/caches per area.
// One pack = one GeoJSON FeatureCollection where every feature carries
// properties.source (the access regime label). This script slices the source
// (assets/access/*.geojson, fetched by fetch_access.mjs) into the regions
// defined in regions.mjs, then writes the coverage index + manifest the app
// resolves against.
//
// A parcel goes into EVERY region whose bbox its geometry overlaps, so the
// resolver can never send a border GPS fix to a pack that lacks its parcels.
//
//   node spike/build_pack.mjs                  # bundled packs (asset: paths)
//   node spike/build_pack.mjs --base-url URL   # remote packs (url:+sha256)
//
// In remote mode each <id>.geojson is meant to be uploaded to a GitHub Release
// at <URL>/<id>.geojson; only coverage.geojson + manifest.json stay bundled.

import { readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { REGIONS, NATION } from './regions.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'assets', 'packs');
mkdirSync(outDir, { recursive: true });

const VERSION = '2026-06-09';

// --base-url <url> → emit remote (downloadable) manifest entries.
const baseUrlIdx = process.argv.indexOf('--base-url');
let BASE_URL = baseUrlIdx >= 0 ? process.argv[baseUrlIdx + 1] : null;
if (BASE_URL) {
  // Guard against the two common mistakes: the clone URL (repo.git) and a
  // trailing slash. Warn if it isn't a release *download* URL (e.g. the /tag/
  // release page, which won't serve the asset files).
  BASE_URL = BASE_URL.replace(/\.git(?=\/|$)/, '').replace(/\/+$/, '');
  if (!/\/releases\/download\//.test(BASE_URL)) {
    console.warn('  (warning) --base-url should be a release DOWNLOAD url:');
    console.warn('    https://github.com/<you>/<repo>/releases/download/<tag>');
    console.warn(`    got: ${BASE_URL}`);
  }
}

// source file → human access label (kept identical to the old labels so
// guidance classification is unchanged).
const inputs = [
  { file: 'assets/access/crow_open_access.geojson', source: 'Open Access (CRoW)' },
  { file: 'assets/access/forestry_england.geojson', source: 'Forestry England' },
];

// Compute a feature's bbox so we can test region overlap without re-walking
// the whole geometry per region.
function featureBbox(geometry) {
  let xmin = Infinity, ymin = Infinity, xmax = -Infinity, ymax = -Infinity;
  const visit = (c) => {
    if (typeof c[0] === 'number') {
      const [lng, lat] = c;
      if (lng < xmin) xmin = lng;
      if (lng > xmax) xmax = lng;
      if (lat < ymin) ymin = lat;
      if (lat > ymax) ymax = lat;
      return;
    }
    for (const x of c) visit(x);
  };
  visit(geometry.coordinates);
  return { xmin, ymin, xmax, ymax };
}

const bboxOverlap = (a, b) =>
  a.xmin <= b.xmax && a.xmax >= b.xmin && a.ymin <= b.ymax && a.ymax >= b.ymin;

// Load + tag every source feature once.
const all = [];
for (const { file, source } of inputs) {
  let raw;
  try {
    raw = JSON.parse(readFileSync(join(root, file), 'utf8'));
  } catch {
    console.warn(`  (skip) ${file} not found — run fetch_access.mjs first`);
    continue;
  }
  let n = 0;
  for (const f of raw.features ?? []) {
    if (!f || !f.geometry) continue;
    all.push({ source, geometry: f.geometry, bbox: featureBbox(f.geometry) });
    n++;
  }
  console.log(`  ${source}: ${n} features`);
}
if (all.length === 0) {
  console.error('No source features — nothing to build.');
  process.exit(1);
}

const coverageFeatures = [];
const manifestPacks = [];

for (const region of REGIONS) {
  const feats = all
    .filter((f) => bboxOverlap(f.bbox, region.bbox))
    .map((f) => ({ type: 'Feature', properties: { source: f.source }, geometry: f.geometry }));
  if (feats.length === 0) {
    console.log(`  ${region.id}: 0 parcels — skipped`);
    continue;
  }

  const pack = {
    type: 'FeatureCollection',
    packId: region.id,
    nation: NATION,
    version: VERSION,
    features: feats,
  };
  const packPath = join(outDir, `${region.id}.geojson`);
  const body = JSON.stringify(pack);
  writeFileSync(packPath, body);
  const { size } = statSync(packPath);
  const sha256 = createHash('sha256').update(body).digest('hex');
  console.log(`  ${region.id}: ${feats.length} parcels, ${(size / 1e6).toFixed(2)} MB`);

  // Coverage rectangle (lng/lat) for this region.
  const { xmin, ymin, xmax, ymax } = region.bbox;
  coverageFeatures.push({
    type: 'Feature',
    properties: { packId: region.id, nation: NATION, label: region.label },
    geometry: {
      type: 'Polygon',
      coordinates: [[
        [xmin, ymin], [xmax, ymin], [xmax, ymax], [xmin, ymax], [xmin, ymin],
      ]],
    },
  });

  const entry = {
    id: region.id,
    nation: NATION,
    label: region.label,
    version: VERSION,
    sizeBytes: size,
  };
  if (BASE_URL) {
    entry.url = `${BASE_URL.replace(/\/$/, '')}/${region.id}.geojson`;
    entry.sha256 = sha256;
  } else {
    entry.asset = `assets/packs/${region.id}.geojson`;
  }
  manifestPacks.push(entry);
}

writeFileSync(
  join(outDir, 'coverage.geojson'),
  JSON.stringify({ type: 'FeatureCollection', features: coverageFeatures }, null, 2),
);
writeFileSync(
  join(outDir, 'manifest.json'),
  JSON.stringify({ schema: 1, packs: manifestPacks }, null, 2),
);

console.log(`\n${manifestPacks.length} packs → assets/packs/  (${BASE_URL ? 'remote' : 'bundled'} manifest)`);
if (!BASE_URL) {
  console.log('Bundled mode: ensure pubspec bundles assets/packs/ (whole dir).');
} else {
  console.log(`Remote mode: upload the packs + manifest.json + coverage.geojson to ${BASE_URL}`);
  console.log('Optionally set RegionPackService.remoteBaseUrl to that base to update without app rebuilds.');
}
