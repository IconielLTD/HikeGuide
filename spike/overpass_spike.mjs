// HikeGuide — Phase 0 SPIKE (throwaway). Node 22+ (global fetch).
// Goal: sanity-check the Overpass SERVICE (shared, rate-limited) for the two
// queries the app needs, and validate point-in-polygon + bbox prefilter against
// a sample region-clipped CRoW GeoJSON. Reports REAL timings over a few runs.
//
// Run:  node spike/overpass_spike.mjs
// This is NOT app code. No deps. Do not build UI on top of it.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Public Overpass endpoints. We hammer #1; the rest are fallbacks worth knowing
// about if #1 is slow/429s (this is the whole point of the spike).
const OVERPASS_ENDPOINTS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.private.coffee/api/interpreter",
];
const ENDPOINT = OVERPASS_ENDPOINTS[0];

const RUNS = 3;            // repeats per query to show variance
const POLITE_DELAY_MS = 1200; // be a good citizen between calls

// Test points in the East Midlands (the MVP region).
const POINTS = [
  { name: "Sherwood Forest (Major Oak)", lat: 53.2058, lng: -1.0721, expect: "woodland" },
  { name: "Sherwood Pines",              lat: 53.1745, lng: -1.0640, expect: "woodland" },
  { name: "Nottingham city centre",      lat: 52.9548, lng: -1.1581, expect: "no woodland" },
  { name: "Stanage Edge (Peak/Derbys)",  lat: 53.3450, lng: -1.6330, expect: "moor + CRoW" },
];

// ---------------------------------------------------------------------------
// Overpass queries
// ---------------------------------------------------------------------------
const woodlandQuery = (lat, lng) => `
[out:json][timeout:25];
(
  way(around:60,${lat},${lng})[natural=wood];
  way(around:60,${lat},${lng})[landuse=forest];
  relation(around:60,${lat},${lng})[natural=wood];
  relation(around:60,${lat},${lng})[landuse=forest];
);
out tags;`;

const waterQuery = (lat, lng) => `
[out:json][timeout:25];
(
  way(around:1200,${lat},${lng})[waterway];
  way(around:1200,${lat},${lng})[natural=water];
);
out geom;`;

async function overpass(query) {
  const t0 = performance.now();
  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": "HikeGuide-Phase0-Spike/0.1 (hobby project)",
    },
    body: "data=" + encodeURIComponent(query),
  });
  const text = await res.text();
  const ms = performance.now() - t0;
  let json = null;
  try { json = JSON.parse(text); } catch { /* non-JSON (often an HTML 429/error page) */ }
  return { ms, status: res.status, ok: res.ok, json, raw: text };
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------
function haversine(aLat, aLng, bLat, bLng) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

function bearing(aLat, aLng, bLat, bLng) {
  const toRad = (d) => (d * Math.PI) / 180;
  const y = Math.sin(toRad(bLng - aLng)) * Math.cos(toRad(bLat));
  const x =
    Math.cos(toRad(aLat)) * Math.sin(toRad(bLat)) -
    Math.sin(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.cos(toRad(bLng - aLng));
  const deg = (Math.atan2(y, x) * 180) / Math.PI;
  const dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
  return dirs[Math.round(((deg + 360) % 360) / 45) % 8];
}

function nearestWater(lat, lng, elements) {
  let best = null;
  for (const el of elements ?? []) {
    if (!el.geometry) continue;
    for (const node of el.geometry) {
      const d = haversine(lat, lng, node.lat, node.lon);
      if (!best || d < best.d) {
        best = { d, lat: node.lat, lng: node.lon, tags: el.tags ?? {} };
      }
    }
  }
  if (!best) return null;
  return {
    distance_m: Math.round(best.d),
    direction: bearing(lat, lng, best.lat, best.lng),
    kind:
      best.tags.waterway ? `waterway=${best.tags.waterway}` :
      best.tags.natural ? `natural=${best.tags.natural}` : "water",
    name: best.tags.name ?? null,
  };
}

function summariseWoodland(elements) {
  if (!elements || elements.length === 0) return { found: false };
  // Collapse the tag signals the app cares about for woodland_type.
  const sigs = elements.map((e) => {
    const t = e.tags ?? {};
    return {
      type: t.natural === "wood" ? "natural=wood" : t.landuse === "forest" ? "landuse=forest" : "?",
      leaf_type: t.leaf_type ?? null,
      leaf_cycle: t.leaf_cycle ?? null,
      species: t.species ?? null,
      name: t.name ?? null,
    };
  });
  const leaf = sigs.find((s) => s.leaf_type)?.leaf_type ?? "unspecified";
  const mapped =
    leaf === "broadleaved" ? "broadleaf / deciduous" :
    leaf === "needleleaved" ? "coniferous" :
    leaf === "mixed" ? "mixed" : "unspecified (leaf_type missing)";
  return { found: true, count: elements.length, woodland_type: mapped, signals: sigs };
}

// ---------------------------------------------------------------------------
// Point-in-polygon (ray casting) with bbox prefilter — coords are [lng,lat]
// ---------------------------------------------------------------------------
function ringBbox(ring) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const [x, y] of ring) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return { minX, minY, maxX, maxY };
}

function pointInRing(lng, lat, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    const intersect =
      yi > lat !== yj > lat &&
      lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

// Precompute bbox-per-polygon so the prefilter is O(1) per feature.
function indexFeatures(geojson) {
  const out = [];
  for (const f of geojson.features) {
    const g = f.geometry;
    const polys = g.type === "Polygon" ? [g.coordinates]
              : g.type === "MultiPolygon" ? g.coordinates : [];
    for (const poly of polys) {
      out.push({ name: f.properties?.name ?? "(unnamed)", rings: poly, bbox: ringBbox(poly[0]) });
    }
  }
  return out;
}

function pip(lat, lng, indexed) {
  let bboxTested = 0, polyTested = 0;
  for (const p of indexed) {
    bboxTested++;
    const b = p.bbox;
    if (lng < b.minX || lng > b.maxX || lat < b.minY || lat > b.maxY) continue; // prefilter
    polyTested++;
    // ring[0] outer, ring[1..] holes
    if (pointInRing(lng, lat, p.rings[0])) {
      let inHole = false;
      for (let i = 1; i < p.rings.length; i++) {
        if (pointInRing(lng, lat, p.rings[i])) { inHole = true; break; }
      }
      if (!inHole) return { inside: true, name: p.name, bboxTested, polyTested };
    }
  }
  return { inside: false, name: null, bboxTested, polyTested };
}

// ---------------------------------------------------------------------------
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const stats = (arr) => {
  const s = [...arr].sort((a, b) => a - b);
  const med = s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
  return { min: Math.round(s[0]), median: Math.round(med), max: Math.round(s[s.length - 1]) };
};

async function timedQuery(label, queryFn, lat, lng) {
  const times = [];
  let last = null;
  for (let i = 0; i < RUNS; i++) {
    const r = await overpass(queryFn(lat, lng));
    times.push(r.ms);
    last = r;
    const n = r.json?.elements?.length ?? "—";
    const flag = r.ok ? "" : `  <-- HTTP ${r.status}`;
    console.log(`    ${label} run ${i + 1}: ${Math.round(r.ms)}ms  status=${r.status}  elements=${n}${flag}`);
    if (!r.ok && r.raw) console.log(`      body: ${r.raw.slice(0, 160).replace(/\s+/g, " ")}`);
    await sleep(POLITE_DELAY_MS);
  }
  return { times, last };
}

async function main() {
  console.log(`HikeGuide Phase 0 spike`);
  console.log(`Endpoint: ${ENDPOINT}`);
  console.log(`Runs per query: ${RUNS}, polite delay: ${POLITE_DELAY_MS}ms\n`);

  const geojson = JSON.parse(readFileSync(join(__dirname, "sample_crow.geojson"), "utf8"));
  const indexed = indexFeatures(geojson);
  console.log(`Loaded sample CRoW GeoJSON: ${geojson.features.length} features -> ${indexed.length} polygons indexed\n`);

  const allWood = [], allWater = [];

  for (const p of POINTS) {
    console.log(`\n=== ${p.name}  (${p.lat}, ${p.lng})  [expect: ${p.expect}] ===`);

    // (a) woodland
    console.log(`  (a) woodland:`);
    const wood = await timedQuery("woodland", woodlandQuery, p.lat, p.lng);
    allWood.push(...wood.times.filter((t, i) => wood.last && true));
    console.log(`      -> ${JSON.stringify(summariseWoodland(wood.last?.json?.elements))}`);

    // (b) nearest water
    console.log(`  (b) nearest water:`);
    const water = await timedQuery("water", waterQuery, p.lat, p.lng);
    allWater.push(...water.times);
    console.log(`      -> ${JSON.stringify(nearestWater(p.lat, p.lng, water.last?.json?.elements))}`);

    // (c) point-in-polygon against sample CRoW
    const t0 = performance.now();
    const r = pip(p.lat, p.lng, indexed);
    const pipMs = performance.now() - t0;
    console.log(`  (c) CRoW PIP: inside=${r.inside}${r.name ? ` ("${r.name}")` : ""}  ` +
                `bboxTested=${r.bboxTested} polyTested=${r.polyTested}  ${pipMs.toFixed(3)}ms`);
  }

  console.log(`\n--- TIMING SUMMARY (ms across all points/runs) ---`);
  console.log(`  woodland query:  ${JSON.stringify(stats(allWood))}`);
  console.log(`  water query:     ${JSON.stringify(stats(allWater))}`);
  console.log(`  (PIP is local & sub-ms; not a network concern)`);
}

main().catch((e) => { console.error("SPIKE FAILED:", e); process.exit(1); });
