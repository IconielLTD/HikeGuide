// HikeGuide — English region definitions for region packs (Phase 2).
//
// Each region is one downloadable pack. Bboxes are approximate (lng/lat) and
// intentionally OVERLAP at the edges: build_pack.mjs assigns a parcel to every
// region whose bbox its geometry overlaps, so a GPS fix near a border always
// resolves to a pack that actually contains the parcels around it (no false
// "no access" at region seams). The trade-off is a little duplication of
// border parcels across neighbouring packs — cheap, since packs download singly.
//
// ORDER MATTERS for the region *label* only: PackResolver returns the first
// coverage rectangle a point falls in, so smaller/inner regions (London) come
// before the larger ones that enclose them (South East).

export const NATION = 'England';

export const REGIONS = [
  { id: 'london', label: 'London',
    bbox: { xmin: -0.55, ymin: 51.25, xmax: 0.35, ymax: 51.72 } },
  { id: 'north-east-england', label: 'North East England',
    bbox: { xmin: -2.70, ymin: 54.30, xmax: -0.65, ymax: 55.85 } },
  { id: 'north-west-england', label: 'North West England',
    bbox: { xmin: -3.75, ymin: 52.95, xmax: -2.00, ymax: 55.20 } },
  { id: 'yorkshire-and-the-humber', label: 'Yorkshire and the Humber',
    bbox: { xmin: -2.60, ymin: 53.25, xmax: 0.25, ymax: 54.65 } },
  { id: 'east-midlands', label: 'East Midlands',
    bbox: { xmin: -1.85, ymin: 51.95, xmax: 0.40, ymax: 53.65 } },
  { id: 'west-midlands', label: 'West Midlands',
    bbox: { xmin: -3.25, ymin: 51.90, xmax: -1.15, ymax: 53.25 } },
  { id: 'east-of-england', label: 'East of England',
    bbox: { xmin: -0.75, ymin: 51.45, xmax: 1.80, ymax: 53.10 } },
  { id: 'south-east-england', label: 'South East England',
    bbox: { xmin: -1.95, ymin: 50.70, xmax: 1.45, ymax: 52.20 } },
  { id: 'south-west-england', label: 'South West England',
    bbox: { xmin: -6.50, ymin: 49.85, xmax: -1.45, ymax: 52.15 } },
];

/// Bbox covering every region — the all-England extent for fetch_access.mjs.
export function englandBbox() {
  let xmin = Infinity, ymin = Infinity, xmax = -Infinity, ymax = -Infinity;
  for (const r of REGIONS) {
    if (r.bbox.xmin < xmin) xmin = r.bbox.xmin;
    if (r.bbox.ymin < ymin) ymin = r.bbox.ymin;
    if (r.bbox.xmax > xmax) xmax = r.bbox.xmax;
    if (r.bbox.ymax > ymax) ymax = r.bbox.ymax;
  }
  return { xmin, ymin, xmax, ymax };
}
