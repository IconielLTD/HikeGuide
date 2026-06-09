import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/cache_repository.dart';
import '../services/trip_recorder.dart';
import '../theme/app_theme.dart';
import 'trip_detail_screen.dart';

/// Journal tab: the list of saved trips. Tap one to see its route; swipe to
/// delete. Auto-refreshes when a recording finishes (so a just-saved trip
/// appears without a manual pull).
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final TripRecorder _rec = TripRecorder.instance;
  List<Trip>? _trips;
  bool _wasRecording = false;

  @override
  void initState() {
    super.initState();
    _wasRecording = _rec.isRecording;
    _rec.addListener(_onRecorderChange);
    _load();
  }

  @override
  void dispose() {
    _rec.removeListener(_onRecorderChange);
    super.dispose();
  }

  void _onRecorderChange() {
    // Reload once when a trip stops, so the new trip shows up.
    if (_wasRecording && !_rec.isRecording) _load();
    _wasRecording = _rec.isRecording;
  }

  Future<void> _load() async {
    final trips = await CacheRepository.instance.listTrips();
    if (!mounted) return;
    setState(() => _trips = trips);
  }

  Future<bool> _confirmDelete(Trip trip) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete this trip?'),
        content: Text(
          '"${trip.title}" and its recorded route will be permanently removed. '
          'This cannot be undone.',
          style: const TextStyle(color: AppColors.secondaryText, height: 1.4),
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
    return yes ?? false;
  }

  Future<void> _delete(Trip trip) async {
    await CacheRepository.instance.deleteTrip(trip.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Trip deleted.')));
    }
  }

  Future<void> _openDetail(Trip trip) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip)),
    );
    // Detail may have renamed or deleted — refresh on return.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    if (trips == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (trips.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Icon(Icons.route_outlined, size: 56, color: AppColors.secondaryText),
            SizedBox(height: 20),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'No trips yet.\nStart one from the Now tab and your route will '
                  'be saved here with its distance and duration.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.secondaryText, fontSize: 16, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: trips.length,
        itemBuilder: (context, i) {
          final trip = trips[i];
          return Dismissible(
            key: ValueKey(trip.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmDelete(trip),
            onDismissed: (_) => _delete(trip),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.fire.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TripCard(trip: trip, onTap: () => _openDetail(trip)),
            ),
          );
        },
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;
  const _TripCard({required this.trip, required this.onTap});

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
            children: [
              const Icon(Icons.route, color: AppColors.accent, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.title,
                      style: const TextStyle(
                          color: AppColors.primaryText,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trip.dateLabel,
                      style: const TextStyle(
                          color: AppColors.secondaryText, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _chip(Icons.straighten,
                            TripRecorder.formatDistance(trip.distanceMetres ?? 0)),
                        const SizedBox(width: 16),
                        _chip(
                            Icons.schedule,
                            TripRecorder.formatDuration(
                                trip.duration ?? Duration.zero)),
                      ],
                    ),
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

  Widget _chip(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.secondaryText),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  color: AppColors.primaryText, fontSize: 15)),
        ],
      );
}
