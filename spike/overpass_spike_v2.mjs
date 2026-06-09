// HikeGuide — Phase 0 SPIKE v2 (throwaway). Node 22+.
// v1 found: (1) overpass-api.de is slow/flaky right now (504/429, ~7-9s median),
// (2) `way(around:60)` is the WRONG woodland test — it measures distance to the
// polygon boundary, so a point deep inside a large wood returns 0 elements.
// v2 fixes the query with is_in() containment, folds woodland + nearest water
// into ONE round-trip (real production shape), and compares endpoints.

const ENDPOINTS = {
  "overpass-api.de":   "https://overpass-api.de/api/interpreter",
  "kumi.systems":      "https://overpass.kumi.systems/api/interpreter",
};

const RUNS = 2;
const DELAY_MS = 2500; // gentler, to dodge 429

const POINTS = [
  { name: "Sherwood Forest (Major Oak)", lat: 53.2058, lng: -1.0721 },
  { name: "Stanage Edge (open moor)",    lat: 53.3450, lng: -1.6330 },
];

// ONE query: is_in() woodland containment + nearest water within 1.2km.
const combinedQuery = (lat, lng) => `
[out:json][timeout:25];
is_in(${lat},${lng})->.a;
( area.a[natural=wood]; area.a[landuse=forest]; );
out tags;
(
  way(around:1200,${lat},${lng})[waterway];
  way(around:1200,${lat},${lng})[natural=water];
);
out geom;`;

async function overpass(url, query) {
  const t0 = performance.now();
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": "HikeGuide-Phase0-Spike/0.2 (hobby project)",
      },
      body: "data=" + encodeURIComponent(query),
    });
    const text = await res.text();
    const ms = performance.now() - t0;
    let json = null;
    try { json = JSON.parse(text); } catch {}
    return { ms, status: res.status, ok: res.ok, json };
  } catch (e) {
    return { ms: performance.now() - t0, status: 0, ok: false, json: null, err: String(e) };
  }
}

function haversine(aLat, aLng, bLat, bLng) {
  const R = 6371000, toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat), dLng = toRad(bLng - aLng);
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}
function bearing(aLat, aLng, bLat, bLng) {
  const toRad = (d) => (d * Math.PI) / 180;
  const y = Math.sin(toRad(bLng - aLng)) * Math.cos(toRad(bLat));
  const x = Math.cos(toRad(aLat)) * Math.sin(toRad(bLat)) - Math.sin(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.cos(toRad(bLng - aLng));
  return ["N","NE","E","SE","S","SW","W","NW"][Math.round(((Math.atan2(y, x) * 180 / Math.PI + 360) % 360) / 45) % 8];
}

function interpret(lat, lng, json) {
  const els = json?.elements ?? [];
  const areas = els.filter((e) => e.type === "area");
  const ways = els.filter((e) => e.type === "way" && e.geometry);

  let woodland_type = "not in mapped woodland";
  if (areas.length) {
    const t = areas[0].tags ?? {};
    const leaf = areas.map((a) => a.tags?.leaf_type).find(Boolean);
    woodland_type =
      leaf === "broadleaved" ? "broadleaf / deciduous" :
      leaf === "needleleaved" ? "coniferous" :
      leaf === "mixed" ? "mixed" :
      (t.natural === "wood" ? "wood (leaf_type unspecified)" : "forest (leaf_type unspecified)");
  }

  let best = null;
  for (const w of ways) for (const n of w.geometry) {
    const d = haversine(lat, lng, n.lat, n.lon);
    if (!best || d < best.d) best = { d, lat: n.lat, lng: n.lon, tags: w.tags ?? {} };
  }
  const water = best ? {
    distance_m: Math.round(best.d),
    direction: bearing(lat, lng, best.lat, best.lng),
    kind: best.tags.waterway ? `waterway=${best.tags.waterway}` : `natural=${best.tags.natural ?? "water"}`,
  } : null;

  return { areas: areas.length, ways: ways.length, woodland_type, water };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  for (const [label, url] of Object.entries(ENDPOINTS)) {
    console.log(`\n############ ENDPOINT: ${label}  (${url}) ############`);
    for (const p of POINTS) {
      console.log(`\n=== ${p.name} (${p.lat}, ${p.lng}) ===`);
      for (let i = 0; i < RUNS; i++) {
        const r = await overpass(url, combinedQuery(p.lat, p.lng));
        if (!r.ok) {
          console.log(`  run ${i + 1}: ${Math.round(r.ms)}ms  status=${r.status}  FAIL${r.err ? " " + r.err : ""}`);
        } else {
          const info = interpret(p.lat, p.lng, r.json);
          console.log(`  run ${i + 1}: ${Math.round(r.ms)}ms  status=200  ` +
            `woodland="${info.woodland_type}" (${info.areas} area) | water=${JSON.stringify(info.water)} (${info.ways} ways)`);
        }
        await sleep(DELAY_MS);
      }
    }
  }
}
main().catch((e) => { console.error("FAILED:", e); process.exit(1); });
