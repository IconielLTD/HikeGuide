// HikeGuide — fetch + simplify access-land GeoJSON for ALL of England (Phase 2).
// Throwaway tooling (Node 22+, zero deps). Pulls every feature intersecting the
// all-England bbox from the public ArcGIS FeatureServers, asks the server to
// simplify (maxAllowableOffset ~11 m) and round (geometryPrecision 5 dp ~1 m),
// strips properties, and writes assets/access/*.geojson — the SOURCE the
// per-region packs are sliced from by spike/build_pack.mjs.
//
// This is a large download (all-England CRoW is the bulk of it). Run on wifi.
//
//   CRoW Open Access land  © Natural England (Open Government Licence)
//   Forestry England legal boundary © Forestry Commission / Crown copyright

import { writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { englandBbox } from "./regions.mjs";

// Resolve output paths from the project root (this script lives in spike/), so
// it writes to the right place no matter which folder you run it from.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");

// All-England extent (union of the region bboxes in regions.mjs).
const BBOX = englandBbox();

const PAGE = 2000;            // = server maxRecordCount
const REQ_TIMEOUT_MS = 45000;
const MAX_OFFSET_DEG = "0.0001";   // ~11 m server-side simplify
const PRECISION = "5";             // 5 dp ~1.1 m

const LAYERS = [
  {
    name: "crow_open_access",
    label: "CRoW Open Access",
    base: "https://services.arcgis.com/JJzESW51TqeY9uat/arcgis/rest/services/CRoW_Act_2000_Access_Layer/FeatureServer/0/query",
  },
  {
    name: "forestry_england",
    label: "Forestry England",
    base: "https://services2.arcgis.com/mHXjwgl3OARRqqD4/arcgis/rest/services/Forestry_England_Legal_Boundary_2024/FeatureServer/0/query",
  },
];

function buildUrl(base, offset) {
  const p = new URLSearchParams({
    where: "1=1",
    geometry: `${BBOX.xmin},${BBOX.ymin},${BBOX.xmax},${BBOX.ymax}`,
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
  return `${base}?${p.toString()}`;
}

async function fetchAll(layer) {
  const features = [];
  let offset = 0;
  for (;;) {
    const res = await fetch(buildUrl(layer.base, offset), {
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

async function main() {
  await mkdir(join(root, "assets/access"), { recursive: true });
  console.log(`All-England bbox ${JSON.stringify(BBOX)}\n`);
  for (const layer of LAYERS) {
    console.log(`=== ${layer.label}`);
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
