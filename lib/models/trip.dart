/// A recorded trip row (trips table). Pure data + light, self-contained
/// formatting — deliberately no service imports, so CacheRepository can return
/// it without an import cycle. Distance/duration are formatted in the UI via
/// TripRecorder.formatDistance/formatDuration.
class Trip {
  final int id;
  final String? name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double? distanceMetres;

  const Trip({
    required this.id,
    this.name,
    required this.startedAt,
    this.endedAt,
    this.distanceMetres,
  });

  factory Trip.fromRow(Map<String, Object?> r) => Trip(
        id: r['id'] as int,
        name: r['name'] as String?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
        endedAt: r['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['ended_at'] as int),
        distanceMetres: (r['distance_metres'] as num?)?.toDouble(),
      );

  Duration? get duration => endedAt?.difference(startedAt);

  bool get hasName => name != null && name!.trim().isNotEmpty;
  String get title => hasName ? name!.trim() : 'Untitled trip';

  /// e.g. "Thu 5 Jun 2026, 14:30".
  String get dateLabel => _formatDateTime(startedAt);
}

const List<String> _weekdays = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' //
];
const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final wd = _weekdays[d.weekday - 1];
  final mon = _months[d.month - 1];
  return '$wd ${d.day} $mon ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}
