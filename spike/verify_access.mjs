// Verify the bundled access GeoJSON against known ground truth using the SAME
// ray-cast PIP the app uses. Throwaway. Node 22+, zero deps.
import { readFile } from "node:fs/promises";

function pointInRing(lng, lat, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > lat) !== (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
// even-odd across all rings of one polygon (outer + holes)
const pointInPoly = (lng, lat, rings) => rings.reduce((acc, r) => acc !== pointInRing(lng, lat, r), false);

function* polys(fc) {
  for (const f of fc.features) {
    const g = f.geometry;
    if (!g) continue;
    if (g.type === "Polygon") yield g.coordinates;
    else if (g.type === "MultiPolygon") for (const p of g.coordinates) yield p;
  }
}

function contains(fc, lng, lat) {
  for (const rings of polys(fc)) {
    if (pointInPoly(lng, lat, rings)) return true;
  }
  return false;
}

const POINTS = [
  { name: "Stanage Edge (open moor)",  lat: 53.3450, lng: -1.6330, expect: "crow" },
  { name: "Sherwood Pines core",       lat: 53.1580, lng: -1.0820, expect: "forestry" },
  { name: "Sherwood Pines core 2",     lat: 53.1620, lng: -1.0900, expect: "forestry" },
  { name: "Clipstone Forest",          lat: 53.1700, lng: -1.0600, expect: "forestry?" },
  { name: "Major Oak, Sherwood",       lat: 53.2058, lng: -1.0721, expect: "?" },
  { name: "Nottingham city centre",    lat: 52.9548, lng: -1.1581, expect: "neither" },
];

const crow = JSON.parse(await readFile("assets/access/crow_open_access.geojson", "utf8"));
const forestry = JSON.parse(await readFile("assets/access/forestry_england.geojson", "utf8"));

let parcelCount = 0;
for (const _ of polys(crow)) parcelCount++;
for (const _ of polys(forestry)) parcelCount++;
console.log(`loaded: CROW features=${crow.features.length}, Forestry features=${forestry.features.length}, total parcels(after MultiPolygon split)=${parcelCount}\n`);

for (const p of POINTS) {
  const inCrow = contains(crow, p.lng, p.lat);
  const inForestry = contains(forestry, p.lng, p.lat);
  const got = inCrow ? "CRoW" : inForestry ? "Forestry England" : "neither";
  console.log(`${p.name.padEnd(28)} -> ${got}   (expected ${p.expect})`);
}

// Structural self-test: how many parcels contain their own bbox centre? For a
// large set of (mostly convex) parcels this must be well above zero, proving
// ring winding + PIP work on the real data (independent of any test coord).
function selfTest(fc, label) {
  let hits = 0, n = 0;
  for (const rings of polys(fc)) {
    n++;
    const outer = rings[0];
    let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity;
    for (const [lng, lat] of outer) {
      minLng = Math.min(minLng, lng); maxLng = Math.max(maxLng, lng);
      minLat = Math.min(minLat, lat); maxLat = Math.max(maxLat, lat);
    }
    if (pointInPoly((minLng + maxLng) / 2, (minLat + maxLat) / 2, rings)) hits++;
  }
  console.log(`${label}: ${hits}/${n} parcels contain their bbox centre`);
}
console.log("");
selfTest(crow, "CRoW");
selfTest(forestry, "Forestry England");
