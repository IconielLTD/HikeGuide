import { readFile } from "node:fs/promises";

function* polys(fc) {
  for (const f of fc.features) {
    const g = f.geometry;
    if (!g) continue;
    if (g.type === "Polygon") yield g.coordinates;
    else if (g.type === "MultiPolygon") for (const p of g.coordinates) yield p;
  }
}
const R = 6371000, d2r = (d) => (d * Math.PI) / 180;
function hav(aLat, aLng, bLat, bLng) {
  const dLat = d2r(bLat - aLat), dLng = d2r(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(d2r(aLat)) * Math.cos(d2r(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

const forestry = JSON.parse(await readFile("assets/access/forestry_england.geojson", "utf8"));

const TARGET = { name: "Sherwood Pines", lat: 53.1745, lng: -1.0640 };

let nearest = Infinity, nearestRingBbox = null, total = 0, overlapping = 0;
for (const rings of polys(forestry)) {
  total++;
  const outer = rings[0];
  let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity;
  let near = Infinity;
  for (const [lng, lat] of outer) {
    minLng = Math.min(minLng, lng); maxLng = Math.max(maxLng, lng);
    minLat = Math.min(minLat, lat); maxLat = Math.max(maxLat, lat);
    near = Math.min(near, hav(TARGET.lat, TARGET.lng, lat, lng));
  }
  // does this parcel's bbox come within ~3km of the target?
  if (minLng - 0.05 <= TARGET.lng && TARGET.lng <= maxLng + 0.05 &&
      minLat - 0.05 <= TARGET.lat && TARGET.lat <= maxLat + 0.05) overlapping++;
  if (near < nearest) { nearest = near; nearestRingBbox = { minLng, minLat, maxLng, maxLat }; }
}

console.log(`Forestry sub-polygons: ${total}`);
console.log(`parcels with bbox within ~5km of ${TARGET.name}: ${overlapping}`);
console.log(`nearest Forestry vertex to ${TARGET.name}: ${(nearest / 1000).toFixed(2)} km`);
console.log(`nearest parcel bbox:`, nearestRingBbox);

// overall data extent
let gMinLng = Infinity, gMinLat = Infinity, gMaxLng = -Infinity, gMaxLat = -Infinity, verts = 0;
for (const rings of polys(forestry)) for (const r of rings) for (const [lng, lat] of r) {
  verts++; gMinLng = Math.min(gMinLng, lng); gMaxLng = Math.max(gMaxLng, lng);
  gMinLat = Math.min(gMinLat, lat); gMaxLat = Math.max(gMaxLat, lat);
}
console.log(`\nForestry data extent: lng [${gMinLng.toFixed(3)}, ${gMaxLng.toFixed(3)}], lat [${gMinLat.toFixed(3)}, ${gMaxLat.toFixed(3)}], vertices=${verts}`);
