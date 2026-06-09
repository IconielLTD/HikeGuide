import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/environment_context.dart';
import '../models/opportunity.dart';
import '../models/skill_category.dart';
import '../services/anthropic_client.dart';
import '../services/content_service.dart';
import '../services/environment_detector.dart';
import '../services/live_location.dart';
import '../services/location_service.dart';
import '../services/trip_recorder.dart';
import '../theme/app_theme.dart';
import '../widgets/access_info_sheet.dart';
import '../widgets/api_failure_view.dart';
import '../widgets/needs_setup_view.dart';
import '../widgets/position_info.dart';
import 'guide_screen.dart';

enum _NowState { loading, loaded, needsSetup, failure }

/// Now tab. PHASE 3: real environment detection (Overpass woodland + nearest
/// water + access-land point-in-polygon, cached per ~500 m cell) drives the
/// Haiku-generated opportunity cards, cached by context_hash. Tapping a card
/// opens its guide. Falls back to a sample context only when there is no GPS fix.
class NowScreen extends StatefulWidget {
  final VoidCallback? onOpenInfo;
  const NowScreen({super.key, this.onOpenInfo});

  @override
  State<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends State<NowScreen> {
  EnvironmentContext _env = EnvironmentContext.mock;
  bool _usingMock = true;

  _NowState _state = _NowState.loading;
  List<Opportunity> _opportunities = const [];
  String? _failureDetail;
  LatLng? _gps;

  // Live land-access status (updates as you cross boundaries), independent of
  // the heavier one-shot environment detection below.
  String? _liveAccess;

  @override
  void initState() {
    super.initState();
    LiveLocation.instance.start(); // idempotent
    _liveAccess = LiveLocation.instance.accessStatus;
    LiveLocation.instance.addListener(_onLiveAccess);
    _load();
  }

  @override
  void dispose() {
    LiveLocation.instance.removeListener(_onLiveAccess);
    super.dispose();
  }

  // Rebuild only when the access category actually changes — not on every
  // position fix — so the card stays cheap.
  void _onLiveAccess() {
    final s = LiveLocation.instance.accessStatus;
    if (s == _liveAccess) return;
    _liveAccess = s;
    if (mounted) setState(() {});
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => _state = _NowState.loading);
    try {
      // 1. GPS fix → 2. detect the environment (cache-first) → 3. opportunities.
      final loc = await const LocationService().getCurrentLatLng();
      final at = loc.latLng;
      final env = at != null
          ? await EnvironmentDetector.instance
              .detect(at, forceRefresh: forceRefresh)
          : EnvironmentContext.mock;

      final items = await ContentService.instance
          .getOpportunities(env, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _gps = at;
        _env = env;
        _usingMock = at == null;
        _opportunities = items;
        _state = _NowState.loaded;
      });
    } on NeedsSetupException {
      if (!mounted) return;
      setState(() => _state = _NowState.needsSetup);
    } on ApiFailureException catch (e) {
      if (!mounted) return;
      setState(() {
        _failureDetail = e.message;
        _state = _NowState.failure;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failureDetail = e.toString();
        _state = _NowState.failure;
      });
    }
  }

  void _openGuide(Opportunity o) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuideScreen(env: _env, title: o.title, category: o.category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _NowState.loading:
        return const _NowLoading();
      case _NowState.needsSetup:
        return NeedsSetupView(onOpenInfo: widget.onOpenInfo, onRetry: _load);
      case _NowState.failure:
        return ApiFailureView(onRetry: _load, detail: _failureDetail);
      case _NowState.loaded:
        return _buildLoaded(context);
    }
  }

  Widget _buildLoaded(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                Text('Your position',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: PositionInfo(location: _gps),
                ),
                const SizedBox(height: 24),
                Text('Where you are',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  _usingMock
                      ? 'No GPS fix — showing a sample context.'
                      : 'Detected from where you are standing.',
                  style: const TextStyle(
                      color: AppColors.secondaryText, fontSize: 14),
                ),
                const SizedBox(height: 16),
                _ContextCard(
                  env: _env,
                  accessStatus: _liveAccess ?? _env.accessStatus,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text('Practice opportunities',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => _load(forceRefresh: true),
                      icon: const Icon(Icons.refresh, color: AppColors.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._opportunities.map(
                  (o) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OpportunityCard(
                        opportunity: o, onTap: () => _openGuide(o)),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _TripControls(),
          ),
        ],
      ),
    );
  }
}

class _NowLoading extends StatelessWidget {
  const _NowLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.accent),
          SizedBox(height: 18),
          Text('Reading the land…',
              style: TextStyle(color: AppColors.secondaryText, fontSize: 16)),
        ],
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  final Opportunity opportunity;
  final VoidCallback onTap;
  const _OpportunityCard({required this.opportunity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(opportunity.category.icon,
                  size: 26, color: opportunity.category.color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opportunity.title,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      opportunity.description,
                      style: const TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 15,
                          height: 1.4),
                    ),
                    if (opportunity.fireWarning) ...[
                      const SizedBox(height: 10),
                      const _FireChip(),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}

class _FireChip extends StatelessWidget {
  const _FireChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.fire.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.fire.withValues(alpha: 0.6)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 16, color: AppColors.fire),
          SizedBox(width: 6),
          Text('Fire — check permission',
              style: TextStyle(color: AppColors.fire, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  final EnvironmentContext env;
  final String accessStatus;
  const _ContextCard({required this.env, required this.accessStatus});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(Icons.park, 'Woodland', env.woodlandType),
          _row(Icons.shield_outlined, 'Access', accessStatus,
              onTap: () => showAccessInfo(context, accessStatus)),
          _row(Icons.public, 'Region', env.region),
          _row(Icons.water_drop_outlined, 'Nearest large body of water',
              env.waterSummary),
          _row(Icons.calendar_today, 'Season', '${env.season} (month ${env.month})'),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {VoidCallback? onTap}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          // Expanded label + Flexible value both wrap/ellipsize, so a long row
          // like "Nearest large body of water" never overflows on a narrow phone.
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.secondaryText, fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
          ),
          // Chevron signals the row opens the access-guidance modal.
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right, size: 18, color: AppColors.accent),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

/// Start Trip ↔ live recording panel, driven by the [TripRecorder] singleton.
/// Owns a 1 s ticker (only while recording) so the elapsed clock advances even
/// between sparse GPS points.
class _TripControls extends StatefulWidget {
  const _TripControls();

  @override
  State<_TripControls> createState() => _TripControlsState();
}

class _TripControlsState extends State<_TripControls> {
  final TripRecorder _rec = TripRecorder.instance;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onChange);
    _syncTicker();
  }

  @override
  void dispose() {
    _rec.removeListener(_onChange);
    _ticker?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
    _syncTicker();
  }

  void _syncTicker() {
    if (_rec.isRecording && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_rec.isRecording && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  Future<void> _start() async {
    final ok = await _rec.start();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_rec.lastError ?? 'Could not start recording.')),
      );
    }
  }

  Future<void> _stop() async {
    final dist = _rec.distanceMetres;
    final dur = _rec.elapsed;
    await _rec.stop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trip saved — ${TripRecorder.formatDistance(dist)} '
              'in ${TripRecorder.formatDuration(dur)}.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_rec.isRecording) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Trip'),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const _RecDot(),
              const SizedBox(width: 8),
              const Text('Recording',
                  style: TextStyle(
                      color: AppColors.primaryText,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(TripRecorder.formatDuration(_rec.elapsed),
                  style: const TextStyle(
                      color: AppColors.primaryText, fontSize: 20)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Distance', TripRecorder.formatDistance(_rec.distanceMetres)),
              // Steps from the device pedometer — shown only once it reports
              // (hidden if the permission is refused or there's no step sensor).
              if (_rec.steps != null) _stat('Steps', '${_rec.steps}'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _stop,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.fire,
                side: BorderSide(color: AppColors.fire.withValues(alpha: 0.7)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.stop),
              label: const Text('Stop & Save'),
            ),
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
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _RecDot extends StatelessWidget {
  const _RecDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
            color: AppColors.fire, shape: BoxShape.circle),
      );
}
