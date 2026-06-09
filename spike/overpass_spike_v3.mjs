// HikeGuide — Phase 0 SPIKE v3 (throwaway). Node 22+.
// Settles the woodland-detection question. is_in() returned 0 areas at the
// Major Oak (heart of Sherwood Forest), which is wrong/unreliable. v3 uses the
// robust approach instead: fetch wood/forest POLYGONS (out geom) in a bbox
// around the point, then run OUR OWN point-in-polygon (the same algorithm we
// already validated for CRoW). Endpoint-agnostic; no reliance on Overpass areas.

// v2 finding: kumi.systems hangs (no response) from here; overpass-api.de
// responds but is flaky (504/429). So: responsive endpoint first, hard 12s
// abort per request so nothing can hang the run, fall through on failure.
const ENDPOINTS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.private.coffee/api/interpreter",
];
const REQ_TIMEOUT_MS = 12000;

const POINTS = [
  { name: "Sherwood Forest (Major Oak)", lat: 53.2058, lng: -1.0721 },
  { name: "Sherwood Pines",              lat: 53.1745, lng: -1.0640 },
  { name: "Nottingham city centre",      lat: 52.9548, lng: -1.1581 },
  { name: "Stanage Edge (open moor)",    lat: 53.3450, lng: -1.6330 },
];

// Fetch candidate wood/forest polygons whose geometry is within ~600m of the
// point (covers the case where we're deep inside a big polygon: any part of its
// boundary within 600m pulls the whole polygon via out geom).
const woodPolyQuery = (lat, lng) => `
[out:json][timeout:25];
(
  way(around:600,${lat},${lng})[natural=wood];
  way(around:600,${lat},${lng})[landuse=forest];
  relation(around:600,${lat},${lng})[natural=wood];
  relation(around:600,${lat},${lng})[landuse=forest];
);
out geom tags;`;

async function overpass(query) {
  for (const url of ENDPOINTS) {
    try {
      const t0 = performance.now();
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "HikeGuide-Phase0-Spike/0.3" },
        body: "data=" + encodeURIComponent(query),
        signal: AbortSignal.timeout(REQ_TIMEOUT_MS),
      });
      const text = await res.text();
      const ms = performance.now() - t0;
      if (!res.ok) { console.log(`    [${url} -> ${res.status}, ${Math.round(ms)}ms, trying next]`); continue; }
      return { ms, json: JSON.parse(text), url };
    } catch (e) { console.log(`    [${url} threw ${e.name === "TimeoutError" ? "timeout" : e}, trying next]`); }
  }
  return null;
}

// ray-cast PIP, coords as [lng,lat]
function pointInRing(lng, lat, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > lat) !== (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

// Build polygons from Overpass elements:
//  - way with geometry -> single outer ring
//  - relation (multipolygon) -> members with role outer/inner; we approximate by
//    treating each outer member ring independently (good enough for detection).
function elementsToPolys(elements) {
  const polys = [];
  for (const el of elements) {
    if (el.type === "way" && el.geometry) {
      polys.push({ ring: el.geometry.map((n) => [n.lon, n.lat]), tags: el.tags ?? {} });
    } else if (el.type === "relation" && el.members) {
      for (const m of el.members) {
        if (m.type === "way" && m.geometry && (m.role === "outer" || !m.role)) {
          polys.push({ ring: m.geometry.map((n) => [n.lon, n.lat]), tags: el.tags ?? {} });
        }
      }
    }
  }
  return polys;
}

function woodlandTypeFromTags(tags) {
  const leaf = tags.leaf_type;
  if (leaf === "broadleaved") return "broadleaf / deciduous";
  if (leaf === "needleleaved") return "coniferous";
  if (leaf === "mixed") return "mixed";
  return tags.natural === "wood" ? "wood (leaf_type unspecified)" : "forest (leaf_type unspecified)";
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  console.log("v3: fetch wood/forest polygons + OUR point-in-polygon\n");
  for (const p of POINTS) {
    const r = await overpass(woodPolyQuery(p.lat, p.lng));
    if (!r) { console.log(`=== ${p.name}: all endpoints failed`); continue; }
    const polys = elementsToPolys(r.json.elements ?? []);
    let hit = null;
    for (const poly of polys) {
      if (pointInRing(p.lng, p.lat, poly.ring)) { hit = poly; break; }
    }
    const verdict = hit
      ? `IN woodland -> ${woodlandTypeFromTags(hit.tags)}${hit.tags.name ? ` ("${hit.tags.name}")` : ""}`
      : `not inside any of ${polys.length} nearby wood polygons`;
    const host = new URL(r.url).host;
    console.log(`=== ${p.name} (${Math.round(r.ms)}ms via ${host}) ` +
                `candidates=${polys.length} -> ${verdict}`);
    await sleep(2500);
  }
}
main().catch((e) => { console.error("FAILED:", e); process.exit(1); });
