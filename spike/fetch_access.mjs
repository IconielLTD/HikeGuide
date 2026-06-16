// HikeGuide — fetch + simplify access-land GeoJSON from public ArcGIS servers.
// Throwaway tooling (Node 22+, zero deps). For each layer it pulls every feature
// intersecting that layer's NATION bbox, asks the server to simplify
// (maxAllowableOffset ~11 m) and round (geometryPrecision 5 dp ~1 m), strips
// properties, and writes assets/access/*.geojson — the SOURCE the per-region
// packs are sliced from by spike/build_pack.mjs.
//
//   node spike/fetch_access.mjs                 # all enabled layers
//   node spike/fetch_access.mjs --nation Scotland   # only that nation's layers
//
// England is a large download (all-England CRoW is the bulk of it); run on wifi.
//
//   CRoW Open Access land  © Natural England (Open Government Licence)
//   Forestry England legal boundary © Forestry Commission / Crown copyright
//   LLTNP camping management zones © Loch Lomond & The Trossachs National Park

import { writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { nationBbox } from "./regions.mjs";

// Resolve output paths from the project root (this script lives in spike/), so
// it writes to the right place no matter which folder you run it from.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");

const PAGE = 2000;            // = server maxRecordCount
const REQ_TIMEOUT_MS = 45000;
const MAX_OFFSET_DEG = "0.0001";   // ~11 m server-side simplify (outSR is 4326)
const PRECISION = "5";             // 5 dp ~1.1 m

// Each layer is fetched over its NATION's bbox (regions.mjs). Native server SR
// is irrelevant — we request outSR=4326, so even the BNG (EPSG:27700) Scottish
// layers come back in lng/lat, no reprojection needed here.
const LAYERS = [
  // --- England: marked polygons are OPEN-ACCESS land ------------------------
  {
    name: "crow_open_access",
    label: "CRoW Open Access",
    nation: "England",
    base: "https://services.arcgis.com/JJzESW51TqeY9uat/arcgis/rest/services/CRoW_Act_2000_Access_Layer/FeatureServer/0/query",
  },
  {
    name: "forestry_england",
    label: "Forestry England",
    nation: "England",
    base: "https://services2.arcgis.com/mHXjwgl3OARRqqD4/arcgis/rest/services/Forestry_England_Legal_Boundary_2024/FeatureServer/0/query",
  },
  // --- Scotland: marked polygons are RESTRICTIONS (open-access model) -------
  {
    name: "scotland_camping_byelaws",
    label: "Camping management zone (byelaws)",
    nation: "Scotland",
    // Loch Lomond & The Trossachs camping management byelaw zones (BNG-native;
    // returned in 4326 via outSR). Verified live ArcGIS FeatureServer.
    base: "https://services5.arcgis.com/bB6hy3TK2FRc3AB0/arcgis/rest/services/LLTNP_Camping_byelaws_management_zones_2017/FeatureServer/0/query",
  },
  {
    name: "scotland_mod",
    label: "Military (MOD) — no public access",
    nation: "Scotland",
    // INTENTIONALLY NOT MAPPED. MOD land splits into two opposite types —
    // secured estate (no access) and training/ranges (right to roam when red
    // flags are down) — and no authoritative public Scotland-wide FeatureServer
    // exists (DIO holds it; public ArcGIS hits are planning "consultation
    // zones", not access bans). Rather than ship unreliable polygons, the live-
    // firing / red-flag safety advice is delivered as part of the general
    // in-app Scotland notice (models/access_guidance.dart -> scotlandOpenAccess,
    // auto-shown once on entering Scotland). Left here, disabled, only so a
    // verified secured-estate source could be slotted in later with no rework.
    base: null,
    enabled: false,
  },
];

function buildUrl(layer, offset) {
  const b = nationBbox(layer.nation);
  const p = new URLSearchParams({
    where: "1=1",
    geometry: `${b.xmin},${b.ymin},${b.xmax},${b.ymax}`,
    geometryType: "esriGeometryEnvelope",
    inSR: "4326",
    spatialRel: "esriSpatialRelIntersects",
    outFields: "",
    returnGeometry: "true",
    outSR: "4326",
    f: "geojson",
    maxAllowableOffset: MAX_OFFSET_DEG,
    geometryPrecision: PRECISION,
    resultRecordCount: String(PAGE),
    resultOffset: String(offset),
  });
  return `${layer.base}?${p.toString()}`;
}

async function fetchAll(layer) {
  const features = [];
  let offset = 0;
  for (;;) {
    const res = await fetch(buildUrl(layer, offset), {
      signal: AbortSignal.timeout(REQ_TIMEOUT_MS),
      headers: { "User-Agent": "HikeGuide-data-fetch/1.0 (hobby app)" },
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`${layer.name} HTTP ${res.status} @offset ${offset}: ${text.slice(0, 200)}`);
    const json = JSON.parse(text);
    if (json.error) throw new Error(`${layer.name} ArcGIS error: ${JSON.stringify(json.error)}`);
    const batch = json.features ?? [];
    features.push(...batch);
    console.log(`  ${layer.name}: +${batch.length} (total ${features.length})`);
    const exceeded = json.exceededTransferLimit === true || json.properties?.exceededTransferLimit === true;
    if (batch.length === 0 || (batch.length < PAGE && !exceeded)) break;
    offset += PAGE;
  }
  return features;
}

function slim(features) {
  const out = [];
  for (const f of features) {
    const g = f?.geometry;
    if (!g) continue;
    if (g.type === "Polygon" || g.type === "MultiPolygon") {
      out.push({ type: "Feature", properties: {}, geometry: g });
    }
  }
  return out;
}

const fmtKB = (n) => `${(n / 1024).toFixed(0)} KB`;

// --nation <name> → fetch only that nation's layers (avoids re-downloading the
// large England layers when iterating on Scotland).
function selectLayers() {
  const idx = process.argv.indexOf("--nation");
  const nation = idx >= 0 ? process.argv[idx + 1] : null;
  let layers = LAYERS.filter((l) => l.enabled !== false && l.base);
  if (nation) {
    layers = layers.filter((l) => l.nation.toLowerCase() === nation.toLowerCase());
    if (layers.length === 0) {
      throw new Error(`No enabled layers for nation: ${nation}`);
    }
  }
  return layers;
}

async function main() {
  await mkdir(join(root, "assets/access"), { recursive: true });
  const layers = selectLayers();
  for (const layer of layers) {
    const b = nationBbox(layer.nation);
    console.log(`=== ${layer.label} [${layer.nation}]  bbox ${JSON.stringify(b)}`);
    const feats = slim(await fetchAll(layer));
    const fc = { type: "FeatureCollection", _source: layer.label, features: feats };
    const body = JSON.stringify(fc);
    const path = join(root, "assets/access", `${layer.name}.geojson`);
    await writeFile(path, body);
    console.log(`  -> ${path}: ${feats.length} polygons, ${fmtKB(Buffer.byteLength(body))}\n`);
  }
  console.log("done.");
}
main().catch((e) => { console.error("FAILED:", e.message); process.exit(1); });
