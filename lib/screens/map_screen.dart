import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/access_guidance.dart';
import '../services/access_land_service.dart';
import '../services/geo/geometry.dart';
import '../services/live_location.dart';
import '../services/os_maps_key_store.dart';
import '../services/trip_recorder.dart';
import '../theme/app_theme.dart';
import '../widgets/access_info_sheet.dart';
import '../widgets/position_info.dart';
import '../widgets/pulsing_gps_marker.dart';

/// Map tab: switchable basemap (CartoDB Dark Matter / OS Outdoor) with required
/// attribution, a pulsing amber GPS marker, and a grid-ref/declination panel.
/// Access overlays + historical routes come in later phases.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Default view: Sherwood Forest, East Midlands (the MVP region) until GPS resolves.
  static const LatLng _defaultCentre = LatLng(53.2058, -1.0721);
  static const double _defaultZoom = 13.0;

  // Pale amber for stretches you've doubled back over, so an out-and-back leg
  // reads as two passes rather than one solid line.
  static final Color _retraceColor =
      Color.lerp(AppColors.accent, Colors.white, 0.55)!;

  final MapController _mapController = MapController();
  final LiveLocation _live = LiveLocation.instance;

  // Local mirrors of [LiveLocation], refreshed via its listener.
  LatLng? _gps;
  String? _gpsReason;
  bool _locating = true;
  String? _accessStatus;

  // Keep the camera centred on the live position until the user pans away;
  // the recenter button re-engages it.
  bool _followMe = true;
  bool _mapReady = false;
  bool _hasCentred = false; // centred on the first fix yet?

  bool _useOsMap = false;
  String? _osKey;

  // Access-land overlay (bundled CRoW / Forestry England GeoJSON). Empty until
  // data is bundled; refreshed for the visible viewport as the map moves.
  bool _hasAccessData = false;
  List<AccessParcel> _accessParcels = const [];
  String? _accessViewSig; // last viewport we refreshed for (skip duplicates)

  @override
  void initState() {
    super.initState();
    // Seed from the shared location source, then follow its updates. Camera
    // moves wait for onMapReady (the controller isn't attached yet here).
    _gps = _live.current;
    _accessStatus = _live.accessStatus;
    _gpsReason = _live.reason;
    _locating = _live.locating;
    _live.start(); // idempotent
    _live.addListener(_onLiveLocation);
    _loadOsKey();
    _loadAccessFlag();
    // Redraw the live trip polyline as new points arrive.
    TripRecorder.instance.addListener(_onTripChange);
  }

  @override
  void dispose() {
    _live.removeListener(_onLiveLocation);
    TripRecorder.instance.removeListener(_onTripChange);
    super.dispose();
  }

  // Track what the polyline actually depends on, so step-counter events (which
  // also notify TripRecorder) don't trigger a needless full map rebuild.
  bool _wasRecording = false;
  int _lastPointCount = 0;

  void _onTripChange() {
    if (!mounted) return;
    // Position/marker come from LiveLocation; here we only redraw the live
    // trip polyline, which changes only when recording toggles or a point is
    // added — not on step-count updates.
    final rec = TripRecorder.instance;
    if (rec.isRecording == _wasRecording && rec.pointCount == _lastPointCount) {
      return;
    }
    _wasRecording = rec.isRecording;
    _lastPointCount = rec.pointCount;
    setState(() {});
  }

  /// Mirror [LiveLocation] into local state and steer the camera: centre on the
  /// first fix, then follow until the user pans away.
  void _onLiveLocation() {
    if (!mounted) return;
    final fix = _live.current;
    setState(() {
      _gps = fix;
      _accessStatus = _live.accessStatus;
      _gpsReason = _live.reason;
      _locating = _live.locating;
    });
    if (fix == null || !_mapReady) return;
    if (!_hasCentred) {
      _hasCentred = true;
      _mapController.move(fix, 15.0);
    } else if (_followMe) {
      _mapController.move(fix, _mapController.camera.zoom);
    }
  }

  void _recenter() {
    final fix = _gps;
    if (fix == null) return;
    setState(() => _followMe = true);
    _mapController.move(fix, _mapController.camera.zoom);
  }

  Future<void> _loadAccessFlag() async {
    final has = await AccessLandService.instance.hasData;
    if (!mounted) return;
    setState(() => _hasAccessData = has);
  }

  /// Refresh the access overlay for the current viewport. Cheap (in-memory bbox
  /// filter), guarded so we only rebuild when the rounded viewport changes and
  /// only when zoomed in enough that the overlay is legible (>= z11).
  Future<void> _refreshAccess(MapCamera camera) async {
    if (!_hasAccessData) return;
    if (camera.zoom < 11) {
      if (_accessParcels.isNotEmpty) {
        setState(() => _accessParcels = const []);
      }
      return;
    }
    final b = camera.visibleBounds;
    final view = GeoBBox(
      b.southWest.longitude,
      b.southWest.latitude,
      b.northEast.longitude,
      b.northEast.latitude,
    );
    final sig = '${view.minLng.toStringAsFixed(2)},'
        '${view.minLat.toStringAsFixed(2)},'
        '${view.maxLng.toStringAsFixed(2)},'
        '${view.maxLat.toStringAsFixed(2)}';
    if (sig == _accessViewSig) return;
    _accessViewSig = sig;
    final parcels = await AccessLandService.instance.parcelsInView(view);
    if (!mounted) return;
    setState(() => _accessParcels = parcels);
  }

  // Palette from the theme (single source of truth); drawn at 40% per the brief.
  static Color _accessColor(String source) => source.startsWith('Open Access')
      ? AppColors.openAccess
      : AppColors.forestryEngland;

  Future<void> _loadOsKey() async {
    final key = await OsMapsKeyStore.instance.read();
    if (!mounted) return;
    setState(() => _osKey = key);
  }

  Future<void> _toggleBasemap() async {
    if (_useOsMap) {
      setState(() => _useOsMap = false);
      return;
    }
    // Switching to OS — re-read the key in case it was added after this tab built.
    final key = _osKey ?? await OsMapsKeyStore.instance.read();
    if (!mounted) return;
    if (key == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an OS Maps API key in the Info tab to use the OS map.'),
        ),
      );
      return;
    }
    setState(() {
      _osKey = key;
      _useOsMap = true;
    });
  }

  TileLayer _buildTileLayer() {
    if (_useOsMap && _osKey != null) {
      return TileLayer(
        urlTemplate:
            'https://api.os.uk/maps/raster/v1/zxy/Outdoor_3857/{z}/{x}/{y}.png?key=${_osKey!}',
        userAgentPackageName: 'com.nfosborn.hikeguide',
        // OS Maps API EPSG:3857 spans z7–20, but only z7–16 are free OpenData
        // (z17–20 are Premium). Cap native fetches at 16 so a free key never
        // requests premium tiles — flutter_map upscales z16 for deeper zooms
        // (slightly soft, never blank).
        minNativeZoom: 7,
        maxNativeZoom: 16,
      );
    }
    return TileLayer(
      // flutter_map 8.x removed `subdomains`; use a single Carto host.
      urlTemplate: 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.nfosborn.hikeguide',
      maxNativeZoom: 20,
    );
  }

  List<String> _attributionLines() {
    if (_useOsMap && _osKey != null) {
      return [
        'Contains OS data © Crown copyright and database rights ${DateTime.now().year}'
      ];
    }
    return const ['OpenStreetMap contributors', 'CARTO'];
  }

  /// The live track as a run of polylines: solid amber for first-pass track,
  /// pale amber for stretches you've doubled back over. Consecutive segments of
  /// the same kind are merged and share their boundary point so the line stays
  /// connected. A segment is classed by the retrace flag of the point it ends on.
  List<Polyline> _tripPolylines() {
    final rec = TripRecorder.instance;
    final pts = rec.points;
    if (pts.length < 2) return const [];
    final flags = rec.retraced;
    bool isLight(int idx) => idx < flags.length && flags[idx];

    final lines = <Polyline>[];
    var i = 0;
    while (i < pts.length - 1) {
      final light = isLight(i + 1);
      final seg = <LatLng>[pts[i]];
      var j = i;
      while (j < pts.length - 1 && isLight(j + 1) == light) {
        seg.add(pts[j + 1]);
        j++;
      }
      lines.add(Polyline(
        points: seg,
        strokeWidth: 4,
        color: light ? _retraceColor : AppColors.accent,
      ));
      i = j;
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _defaultCentre,
            initialZoom: _defaultZoom,
            minZoom: 4,
            maxZoom: 18,
            onMapReady: () {
              _mapReady = true;
              _refreshAccess(_mapController.camera);
              // If a fix already arrived before the map was ready, centre now.
              final fix = _gps;
              if (fix != null && !_hasCentred) {
                _hasCentred = true;
                _mapController.move(fix, 15.0);
              }
            },
            onPositionChanged: (camera, hasGesture) {
              // A manual pan/zoom means "let me look around" — stop chasing the
              // GPS until the user taps recenter.
              if (hasGesture && _followMe) {
                setState(() => _followMe = false);
              }
              _refreshAccess(camera);
            },
          ),
          children: [
            _buildTileLayer(),
            if (_accessParcels.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final parcel in _accessParcels)
                    Polygon(
                      points: parcel.outline,
                      holePointsList:
                          parcel.holes.isEmpty ? null : parcel.holes,
                      color: _accessColor(parcel.source)
                          .withValues(alpha: 0.40),
                      borderColor: _accessColor(parcel.source)
                          .withValues(alpha: 0.9),
                      borderStrokeWidth: 1.4,
                    ),
                ],
              ),
            // Live trip track while recording — solid amber, with doubled-back
            // stretches drawn in a lighter amber.
            if (TripRecorder.instance.isRecording &&
                TripRecorder.instance.points.length >= 2)
              PolylineLayer(polylines: _tripPolylines()),
            if (_gps != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _gps!,
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    child: const PulsingGpsMarker(),
                  ),
                ],
              ),
          ],
        ),
        // Attribution (top-left; tap the ⓘ to expand). Kept clear of the
        // bottom position panel and the top-right basemap toggle.
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 12),
              child: _AttributionControl(lines: _attributionLines()),
            ),
          ),
        ),
        // Access-land legend (top-left, below the attribution ⓘ) — only while
        // overlay polygons are actually on screen.
        if (_accessParcels.isNotEmpty)
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 56, left: 12),
                child: _AccessLegend(
                  sources: {for (final p in _accessParcels) p.source},
                  colourOf: _accessColor,
                ),
              ),
            ),
          ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: _StatusPill(locating: _locating, reason: _gpsReason),
          ),
        ),
        // Basemap toggle (top-right).
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, right: 12),
              child: _BasemapToggle(useOsMap: _useOsMap, onTap: _toggleBasemap),
            ),
          ),
        ),
        // Recenter button — only when we've drifted off the live position.
        // Tapping re-engages follow and snaps back to the marker. Sits clear of
        // the bottom panel (taller when the access banner is showing).
        if (_gps != null && !_followMe)
          Positioned(
            right: 12,
            bottom: _accessStatus != null ? 132 : 92,
            child: _RecenterButton(onTap: _recenter),
          ),
        // Field info panel along the bottom: tappable land-access banner (live;
        // updates as boundaries are crossed) above the grid ref + declination.
        if (_gps != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.secondaryText.withValues(alpha: 0.2)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_accessStatus != null) ...[
                      _AccessBanner(
                        status: _accessStatus!,
                        onTap: () => showAccessInfo(context, _accessStatus),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.secondaryText.withValues(alpha: 0.15),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: PositionInfo(location: _gps),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small status pill: "Locating…" while we read GPS, or a calm reason if we
/// couldn't get a fix (the map still shows the default region).
class _StatusPill extends StatelessWidget {
  final bool locating;
  final String? reason;
  const _StatusPill({required this.locating, required this.reason});

  @override
  Widget build(BuildContext context) {
    final String? label = locating
        ? 'Locating…'
        : (reason != null ? '$reason — showing default region' : null);
    if (label == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secondaryText.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locating ? Icons.my_location : Icons.location_off,
            size: 18,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: AppColors.primaryText, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// Custom map attribution control (flutter_map's built-in one only supports the
/// bottom corners). Sits top-left as a small ⓘ; tap to expand the credits in
/// place, tap again to collapse.
class _AttributionControl extends StatefulWidget {
  final List<String> lines;
  const _AttributionControl({required this.lines});

  @override
  State<_AttributionControl> createState() => _AttributionControlState();
}

class _AttributionControlState extends State<_AttributionControl> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(_expanded ? 12 : 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(_expanded ? 12 : 20),
        onTap: () => setState(() => _expanded = !_expanded),
        child: _expanded ? _expandedView() : _collapsedView(),
      ),
    );
  }

  Widget _collapsedView() => const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.info_outline, size: 18, color: AppColors.accent),
      );

  Widget _expandedView() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 15, color: AppColors.accent),
                SizedBox(width: 6),
                Text('Map data',
                    style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                SizedBox(width: 10),
                Icon(Icons.close, size: 14, color: AppColors.secondaryText),
              ],
            ),
            const SizedBox(height: 6),
            ...widget.lines.map(
              (l) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  l,
                  style: const TextStyle(
                      color: AppColors.primaryText, fontSize: 12, height: 1.3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small legend for the access-land overlay; lists only the dataset(s) actually
/// visible, with their fill colour.
class _AccessLegend extends StatelessWidget {
  final Set<String> sources;
  final Color Function(String) colourOf;
  const _AccessLegend({required this.sources, required this.colourOf});

  @override
  Widget build(BuildContext context) {
    final ordered = sources.toList()..sort();
    return Material(
      color: AppColors.surface.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Access land',
                style: TextStyle(color: AppColors.secondaryText, fontSize: 11)),
            const SizedBox(height: 6),
            for (final source in ordered)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colourOf(source).withValues(alpha: 0.35),
                        border: Border.all(color: colourOf(source)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(source,
                        style: const TextStyle(
                            color: AppColors.primaryText, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pill button showing the active basemap; tap to switch. Labelled with the
/// CURRENT layer so it's clear what you're looking at.
class _BasemapToggle extends StatelessWidget {
  final bool useOsMap;
  final VoidCallback onTap;
  const _BasemapToggle({required this.useOsMap, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.layers, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                useOsMap ? 'OS Outdoor' : 'Dark map',
                style: const TextStyle(color: AppColors.primaryText, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round button that re-engages "follow my position" and snaps the view back to
/// the live marker. Shown only once the user has panned away.
class _RecenterButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RecenterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.my_location, size: 22, color: AppColors.accent),
        ),
      ),
    );
  }
}

/// Tappable land-access banner at the top of the bottom panel. Shows the live
/// classification with a category colour; tapping opens the legal-guidance modal.
class _AccessBanner extends StatelessWidget {
  final String status;
  final VoidCallback onTap;
  const _AccessBanner({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final category = accessCategoryForStatus(status);
    final color = accessCategoryColor(category);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(accessCategoryIcon(category), size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('ACCESS',
                      style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 11,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(
                    status,
                    style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text('What can I do?',
                style: TextStyle(color: AppColors.accent, fontSize: 13)),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
