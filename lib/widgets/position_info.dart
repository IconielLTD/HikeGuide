import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/geomagnetic.dart';
import '../services/grid_reference.dart';
import '../theme/app_theme.dart';

/// Compact readout of OS grid reference + magnetic declination for a location.
/// Both are computed offline (the grid transform and the geomagnetic model are
/// non-trivial), so they're memoized and only recomputed when [location]
/// changes — not on every parent rebuild. Shows a muted line when there's no fix.
class PositionInfo extends StatefulWidget {
  final LatLng? location;
  final String? unavailableLabel;

  const PositionInfo({super.key, required this.location, this.unavailableLabel});

  @override
  State<PositionInfo> createState() => _PositionInfoState();
}

class _PositionInfoState extends State<PositionInfo> {
  String? _grid;
  String? _declination;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(PositionInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _recompute();
  }

  void _recompute() {
    final loc = widget.location;
    if (loc == null) {
      _grid = null;
      _declination = null;
      return;
    }
    _grid =
        GridReference.fromLatLng(loc.latitude, loc.longitude) ?? '— outside GB';
    _declination = Geomagnetic.formatForLatLng(loc.latitude, loc.longitude);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.location == null) {
      return Row(
        children: [
          const Icon(Icons.gps_not_fixed, size: 18, color: AppColors.secondaryText),
          const SizedBox(width: 8),
          Text(
            widget.unavailableLabel ?? 'Waiting for GPS…',
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 14),
          ),
        ],
      );
    }

    final grid = _grid ?? '— outside GB';
    final declination = _declination ?? '';

    return Row(
      children: [
        Expanded(child: _item(Icons.grid_on, 'Grid ref', grid)),
        Container(
          width: 1,
          height: 34,
          color: AppColors.secondaryText.withValues(alpha: 0.25),
        ),
        Expanded(child: _item(Icons.compass_calibration, 'Declination', declination)),
      ],
    );
  }

  Widget _item(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.secondaryText, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
