# HikeGuide — Phase 0 Spike Findings

**Date:** 2026-06-04
**Goal (from the brief):** Sanity-check the Overpass *service* (shared, rate-limited — independent of the user's own signal) for the two queries the app needs, and validate point-in-polygon against a region-clipped CRoW GeoJSON. Report real timings. *If fast & reliable, move on. If sluggish or flaky, flag it before Phase 3.*

**Verdict: FLAKY. Flagging before Phase 3, as instructed.** The data approach is sound and proven, but the public Overpass service is too slow/unreliable to hard-depend on at request time. The app must lean on caching + multi-endpoint fallback + graceful degradation.

Throwaway artifacts (not app code): `overpass_spike.mjs` (v1), `overpass_spike_v2.mjs`, `overpass_spike_v3.mjs`, `sample_crow.geojson`. Node 22, zero deps.

---

## What works (proven)

### 1. CRoW point-in-polygon + bbox prefilter — SOLID
Ray-casting PIP over a `FeatureCollection` of `Polygon`/`MultiPolygon`, with a per-polygon bbox prefilter. Sub-millisecond, correct.
- Stanage Edge → `inside=true` (bboxTested=1, polyTested=1) — prefilter narrowed 3 polys to 1 before ray-casting.
- Sherwood / Nottingham → `inside=false` (polyTested=0) — bbox rejected all without ray-casting.
- **Conclusion:** the bundled region-clipped + simplified GeoJSON + bbox-prefilter plan in the brief is correct as written.

### 2. Nearest water — WORKS
`way(around:N)[waterway]; way(around:N)[natural=water]; out geom;` → haversine to nearest geometry node + 8-point compass bearing.
- Nottingham → `140m SE, natural=water`
- Stanage → `215m W, waterway=stream`
- Returns distance + direction + feature kind, exactly what the `water_distance`/`water_direction` context needs.

### 3. Woodland detection — WORKS, but ONLY the right way
This was the key gotcha. **Two wrong approaches and one right one:**
- ❌ `way(around:60)[natural=wood]` — measures distance to the polygon **boundary**, so a point deep inside a large wood returns **0 elements**. Major Oak (dead centre of Sherwood Forest) returned nothing.
- ❌ Overpass `is_in(lat,lng)` area containment — *also* returned 0 areas at Major Oak (area DB quirk / unreliable). Don't trust it.
- ✅ **Fetch wood/forest polygons (`out geom`) near the point, then run OUR OWN ray-cast PIP** (the same algorithm as CRoW). Major Oak → `candidates=12 → IN woodland → wood`. Correct.
  - **Recommended refinement:** fetch by a small **bbox** around the point (e.g. ±0.01°) rather than `around:600`. `around` only pulls polygons with a node/segment within the radius; for a point deep inside a very large forest the boundary can be outside the radius and you'd miss the containing polygon. A bbox fetch guarantees the enclosing polygon is in the candidate set. (Sherwood Pines returned "not inside any of 3 nearby polygons" with `around:600` — likely a clearing/track GPS point, but a bbox fetch is the safer general fix.)
  - `leaf_type` tag → `woodland_type` (broadleaved→deciduous, needleleaved→coniferous, mixed→mixed; often unspecified, so have a fallback).

### 4. One round-trip instead of two
Woodland (areas) + nearest water (ways) can be returned by a **single** Overpass query; distinguish results by `element.type`. Halves the request count — important given the rate limits below.

---

## What's flaky (the actual risk)

Real timings against `https://overpass-api.de/api/interpreter`:

| Query (v1, naive)        | min     | median  | max      |
|--------------------------|---------|---------|----------|
| woodland                 | 1207ms  | 8296ms  | 11098ms  |
| nearest water            | 746ms   | 7050ms  | 15462ms  |

- Best case ~0.7–2s; **typical 7–9s under load**; frequent **HTTP 504** (gateway timeout) and **HTTP 429** (rate limited).
- `overpass.kumi.systems` — **hung with no response** (had to abort). Not a usable fallback right now.
- `overpass.private.coffee` — **timed out** (>12s) on every attempt.
- Caveat: some 429s are partly self-inflicted (the spike fired ~30 calls in a few minutes). But the baseline latency (7–9s) and 504s appeared even on early, un-throttled calls — the service is genuinely loaded, not just rate-limiting us. The real app's heavy `context_hash` caching means far fewer calls, which helps the 429s but not the per-call latency.

---

## Recommendation for Phase 3 (decide now, per the brief)

Treat Overpass as **best-effort, never a hard dependency**:
1. **Cache aggressively** by `context_hash` (already in the design) — a successful detection is reused; we should query Overpass rarely (on cache miss / >500m move / manual refresh only).
2. **Multi-endpoint fallback list** with a **hard ~12s per-request timeout** and **one retry**; rotate endpoints on 429/504/timeout. Keep the list in one constant.
3. **Graceful degradation** when all endpoints fail: fall back to last-known context or sensible defaults (e.g. `woodland_type: "unknown"`) so the LLM-driven screens still function. Mirror the API utility's failure-state pattern.
4. **Be a good citizen:** descriptive `User-Agent`, low request rate, honour 429 backoff.
5. **If this ever grows beyond single-user hobby use:** self-host Overpass or use a commercial endpoint. For one user + heavy caching, fallback + cache is likely enough — but the *option* is flagged now, not at Phase 3.

Net: **no architectural blocker.** Overpass is viable *with* the caching + fallback + degradation the brief already anticipates. The naive "just query on demand" path would have produced 7–9s stalls and dead screens — that's the trap Phase 0 caught.

---

## Separate prerequisite surfaced (blocks Phase 1, not Phase 0)
**Flutter/Dart are not installed** in this environment (`flutter`/`dart` not found; only Python 3.13 + Node 22). Phase 1 (scaffold the Flutter project) can't start until the Flutter SDK + Android toolchain are installed.
