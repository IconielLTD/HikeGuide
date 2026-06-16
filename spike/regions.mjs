// HikeGuide — region definitions for region packs.
//
// Each region is one downloadable pack, tagged with the NATION whose access law
// applies inside it. The nation drives the app's per-nation access model (see
// AccessLandService.statusAt + models/access_guidance.dart):
//   - England / Wales — CRoW "right to roam" model: the marked polygons are
//     open-access land; outside them there is no mapped right.
//   - Scotland — open-access model: a right of responsible access by default;
//     the marked polygons are RESTRICTIONS (camping byelaw zones, military
//     land), and outside them the app shows the right-to-roam default.
//
// Bboxes are approximate (lng/lat) and intentionally OVERLAP at the edges:
// build_pack.mjs assigns a parcel to every SAME-NATION region whose bbox its
// geometry overlaps, so a GPS fix near a border always resolves to a pack that
// actually contains the parcels around it (no false "no access" at region
// seams). The trade-off is a little duplication of border parcels across
// neighbouring packs — cheap, since packs download singly.
//
// ORDER MATTERS for the region *label* only: PackResolver returns the first
// coverage rectangle a point falls in, so smaller/inner regions (London) come
// before the larger ones that enclose them (South East), and England comes
// before Scotland so the fuzzy land border resolves to England on the English
// side.

export const REGIONS = [
  // --- England (CRoW open-access model) -------------------------------------
  { id: 'london', nation: 'England', label: 'London',
    bbox: { xmin: -0.55, ymin: 51.25, xmax: 0.35, ymax: 51.72 } },
  { id: 'north-east-england', nation: 'England', label: 'North East England',
    bbox: { xmin: -2.70, ymin: 54.30, xmax: -0.65, ymax: 55.85 } },
  { id: 'north-west-england', nation: 'England', label: 'North West England',
    bbox: { xmin: -3.75, ymin: 52.95, xmax: -2.00, ymax: 55.20 } },
  { id: 'yorkshire-and-the-humber', nation: 'England', label: 'Yorkshire and the Humber',
    bbox: { xmin: -2.60, ymin: 53.25, xmax: 0.25, ymax: 54.65 } },
  { id: 'east-midlands', nation: 'England', label: 'East Midlands',
    bbox: { xmin: -1.85, ymin: 51.95, xmax: 0.40, ymax: 53.65 } },
  { id: 'west-midlands', nation: 'England', label: 'West Midlands',
    bbox: { xmin: -3.25, ymin: 51.90, xmax: -1.15, ymax: 53.25 } },
  { id: 'east-of-england', nation: 'England', label: 'East of England',
    bbox: { xmin: -0.75, ymin: 51.45, xmax: 1.80, ymax: 53.10 } },
  { id: 'south-east-england', nation: 'England', label: 'South East England',
    bbox: { xmin: -1.95, ymin: 50.70, xmax: 1.45, ymax: 52.20 } },
  { id: 'south-west-england', nation: 'England', label: 'South West England',
    bbox: { xmin: -6.50, ymin: 49.85, xmax: -1.45, ymax: 52.15 } },

  // --- Scotland (open-access model: the marked polygons are RESTRICTIONS) ----
  // One pack for now. Its bbox spans all of Scotland (mainland + isles) so the
  // bundled coverage index reports nation=Scotland everywhere here — the app
  // then shows the right-to-roam default outside any marked restriction parcel.
  // Tiling Scotland into smaller packs is a future refinement (see DATA.md).
  { id: 'scotland', nation: 'Scotland', label: 'Scotland',
    bbox: { xmin: -8.80, ymin: 54.55, xmax: -0.50, ymax: 61.10 } },
];

/// Bbox union of one nation's regions — the all-nation extent for fetch.
export function nationBbox(nation) {
  let xmin = Infinity, ymin = Infinity, xmax = -Infinity, ymax = -Infinity;
  for (const r of REGIONS) {
    if (r.nation !== nation) continue;
    if (r.bbox.xmin < xmin) xmin = r.bbox.xmin;
    if (r.bbox.ymin < ymin) ymin = r.bbox.ymin;
    if (r.bbox.xmax > xmax) xmax = r.bbox.xmax;
    if (r.bbox.ymax > ymax) ymax = r.bbox.ymax;
  }
  if (xmin === Infinity) throw new Error(`No regions defined for nation: ${nation}`);
  return { xmin, ymin, xmax, ymax };
}

/// The distinct nations that have regions, in declaration order.
export function nations() {
  return [...new Set(REGIONS.map((r) => r.nation))];
}

/// All-England extent — kept for back-compat with older callers.
export function englandBbox() {
  return nationBbox('England');
}
