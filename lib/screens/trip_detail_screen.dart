import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip.dart';
import '../services/cache_repository.dart';
import '../services/trip_recorder.dart';
import '../theme/app_theme.dart';

/// A single saved trip: its route drawn on a dark map (fitted to the track),
/// with date / duration / distance / point count, plus rename and delete.
class TripDetailScreen extends StatefulWidget {
  final Trip trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  static const String _cartoDark =
      'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

  List<LatLng>? _points;
  late String? _name = widget.trip.name;

  @override
  void initState() {
    super.initState();
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    final rows = await CacheRepository.instance.routePoints(widget.trip.id);
    if (!mounted) return;
    setState(() => _points = [for (final r in rows) r.latLng]);
  }

  String get _title =>
      (_name != null && _name!.trim().isNotEmpty) ? _name!.trim() : 'Untitled trip';

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Name this trip'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.primaryText),
          decoration: const InputDecoration(
            hintText: 'e.g. Sherwood loop',
            hintStyle: TextStyle(color: AppColors.secondaryText),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await CacheRepository.instance.renameTrip(widget.trip.id, result);
    if (!mounted) return;
    setState(() => _name = result);
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete this trip?'),
        content: const Text(
          'This trip and its recorded route will be permanently removed. '
          'This cannot be undone.',
          style: TextStyle(color: AppColors.secondaryText, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.fire),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await CacheRepository.instance.deleteTrip(widget.trip.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMapArea()),
          _StatsPanel(trip: widget.trip),
        ],
      ),
    );
  }

  Widget _buildMapArea() {
    final pts = _points;
    if (pts == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (pts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No GPS points were recorded for this trip.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondaryText, fontSize: 16),
          ),
        ),
      );
    }
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: pts.length >= 2
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(pts),
                padding: const EdgeInsets.all(36),
              )
            : null,
        initialCenter: pts.first,
        initialZoom: 15,
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: _cartoDark,
          userAgentPackageName: 'com.nfosborn.hikeguide',
          maxNativeZoom: 20,
        ),
        if (pts.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: pts, strokeWidth: 4, color: AppColors.accent),
            ],
          ),
        MarkerLayer(
          markers: [
            _marker(pts.first, Icons.trip_origin, const Color(0xFF7DBE6A)),
            if (pts.length >= 2) _marker(pts.last, Icons.place, AppColors.fire),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
            TextSourceAttribution('CARTO'),
          ],
        ),
      ],
    );
  }

  Marker _marker(LatLng point, IconData icon, Color color) => Marker(
        point: point,
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 28),
      );
}

class _StatsPanel extends StatelessWidget {
  final Trip trip;
  const _StatsPanel({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
            top: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trip.dateLabel,
              style: const TextStyle(
                  color: AppColors.secondaryText, fontSize: 14)),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('Distance',
                  TripRecorder.formatDistance(trip.distanceMetres ?? 0)),
              _stat('Duration',
                  TripRecorder.formatDuration(trip.duration ?? Duration.zero)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.secondaryText, fontSize: 13)),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
