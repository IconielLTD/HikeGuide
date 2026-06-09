import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/environment_context.dart';
import '../models/guide.dart';
import '../models/guide_summary.dart';
import '../models/opportunity.dart';
import '../models/skill_category.dart';
import '../models/trip.dart';

/// Local SQLite store. Holds two kinds of data:
///  - REGENERABLE caches (opportunity_cache, guide_cache, guide_progress) — safe
///    to clear; a deleted guide just regenerates on next open.
///  - IRREPLACEABLE user data (trips, route_points) — NEVER touched by any
///    cache-clearing action. (Trips are written in Phase 4/5.)
///
/// Singleton; open lazily via [instance].
class CacheRepository {
  CacheRepository._();
  static final CacheRepository instance = CacheRepository._();

  Database? _db;

  Future<Database> get _database async {
    return _db ??= await _open();
  }

  /// Close the open handle so the next access reopens. Tests use this to get a
  /// clean database between cases; not for production code.
  @visibleForTesting
  Future<void> resetForTest() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'hikeguide.db');
    return openDatabase(path, version: 5, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2: the Guides library shows the context a guide was written for.
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE guide_cache ADD COLUMN context_label TEXT');
    }
    // v3: cache the detected environment per ~500 m cell so Overpass (flaky,
    // 7–9 s) is queried rarely rather than on every Now-tab open.
    if (oldVersion < 3) {
      await db.execute(_envCacheDdl);
    }
    // v4: tiny key/value table; lets us drop stale detections when the bundled
    // access data changes (see reconcileAccessDataVersion).
    if (oldVersion < 4) {
      await db.execute(_metaDdl);
    }
    // v5: repair installs created before trip recording existed. The trips /
    // route_points tables were added to _onCreate but never to an upgrade step,
    // so phones upgraded from an earlier phase never got them — "Stop & Save"
    // then failed silently (no such table: trips) and the Journal stayed empty.
    // Idempotent (CREATE TABLE IF NOT EXISTS), so it's a no-op for fresh installs.
    if (oldVersion < 5) {
      await db.execute(_tripsDdl);
      await db.execute(_routePointsDdl);
    }
  }

  static const String _tripsDdl = '''
      CREATE TABLE IF NOT EXISTS trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        notes TEXT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        distance_metres REAL
      )''';

  static const String _routePointsDdl = '''
      CREATE TABLE IF NOT EXISTS route_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        recorded_at INTEGER NOT NULL
      )''';

  static const String _envCacheDdl = '''
      CREATE TABLE env_cache (
        grid_key TEXT PRIMARY KEY,
        context_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )''';

  static const String _metaDdl =
      'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)';

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(_tripsDdl);
    await db.execute(_routePointsDdl);
    await db.execute('''
      CREATE TABLE opportunity_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        context_hash TEXT NOT NULL UNIQUE,
        response_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE guide_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        guide_title TEXT NOT NULL,
        skill_category TEXT NOT NULL,
        context_hash TEXT NOT NULL,
        response_json TEXT NOT NULL,
        context_label TEXT,
        cached_at INTEGER NOT NULL,
        UNIQUE(guide_title, context_hash)
      )''');
    await db.execute('''
      CREATE TABLE guide_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        guide_title TEXT NOT NULL,
        context_hash TEXT NOT NULL,
        current_step INTEGER NOT NULL,
        UNIQUE(guide_title, context_hash)
      )''');
    await db.execute(_envCacheDdl);
    await db.execute(_metaDdl);
  }

  // --- context_hash / grid cell -------------------------------------------
  // ~500 m grid cell key. Shared by context_hash (cache key for LLM content)
  // and env_cache (so detection is reused across the same cell).
  static const double _latStep = 0.0045; // ~500 m of latitude
  static const double _lngStep = 0.0075; // ~500 m of longitude at ~53°N

  static String gridKey(double lat, double lng) {
    final int latCell = (lat / _latStep).floor();
    final int lngCell = (lng / _lngStep).floor();
    return '$latCell:$lngCell';
  }

  // STABLE inputs only: ~500m GPS grid cell + woodland_type + access_status +
  // month. Deliberately excludes exact water distance/direction and raw lat/lng,
  // or the cache would never hit.
  static String contextHash(EnvironmentContext env) {
    final raw = '${gridKey(env.lat, env.lng)}'
        '|${env.woodlandType}|${env.accessStatus}|${env.month}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  // --- env_cache (detected environment, per grid cell) --------------------
  /// Cached detection for [gridKey] if present and fresher than [maxAge].
  Future<EnvironmentContext?> getCachedEnv(String gridKey,
      {Duration maxAge = const Duration(days: 7)}) async {
    final db = await _database;
    final rows = await db.query('env_cache',
        columns: ['context_json', 'cached_at'],
        where: 'grid_key = ?',
        whereArgs: [gridKey],
        limit: 1);
    if (rows.isEmpty) return null;
    final cachedAt =
        DateTime.fromMillisecondsSinceEpoch(rows.first['cached_at'] as int);
    if (DateTime.now().difference(cachedAt) > maxAge) return null;
    final decoded = jsonDecode(rows.first['context_json'] as String);
    if (decoded is! Map<String, dynamic>) return null;
    return EnvironmentContext.fromJson(decoded);
  }

  Future<void> putCachedEnv(String gridKey, EnvironmentContext env) async {
    final db = await _database;
    await db.insert(
      'env_cache',
      {
        'grid_key': gridKey,
        'context_json': jsonEncode(env.toJson()),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clear cached detections (e.g. after bundling new access data). Never
  /// touches trips/route_points.
  Future<void> clearEnvCache() async {
    final db = await _database;
    await db.delete('env_cache');
  }

  // --- meta + data-version reconcile --------------------------------------
  Future<String?> _getMeta(String key) async {
    final db = await _database;
    final rows = await db.query('meta',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String value) async {
    final db = await _database;
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Cheap one-shot startup check: if the bundled access data changed since the
  /// last launch (or this is the first launch with access data), drop cached
  /// detections so access status re-resolves against the new data. Just a keyed
  /// read on every launch; the env_cache delete + write happen ONLY when the
  /// version actually differs — no GPS, network, or background work. Returns
  /// true if it cleared the cache.
  Future<bool> reconcileAccessDataVersion(String version) async {
    const key = 'access_data_version';
    final seen = await _getMeta(key);
    if (seen == version) return false;
    await clearEnvCache();
    await _setMeta(key, version);
    return true;
  }

  /// Drop cached opportunities + guides when the content prompts change, so the
  /// improved wording/length regenerates on demand. Like the access reconcile:
  /// one keyed read per launch; the clears run only when the version differs.
  /// Never touches trips/route_points (irreplaceable). Returns true if it cleared.
  Future<bool> reconcileContentVersion(String version) async {
    const key = 'content_prompt_version';
    final seen = await _getMeta(key);
    if (seen == version) return false;
    await clearOpportunityCache();
    await clearGuideCache();
    await _setMeta(key, version);
    return true;
  }

  // --- opportunity_cache --------------------------------------------------
  Future<List<Opportunity>?> getOpportunities(String contextHash) async {
    final db = await _database;
    final rows = await db.query('opportunity_cache',
        columns: ['response_json'],
        where: 'context_hash = ?',
        whereArgs: [contextHash],
        limit: 1);
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['response_json'] as String);
    if (decoded is! List) return null;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Opportunity.fromJson)
        .toList();
  }

  Future<void> putOpportunities(
      String contextHash, List<Opportunity> items) async {
    final db = await _database;
    await db.insert(
      'opportunity_cache',
      {
        'context_hash': contextHash,
        'response_json': jsonEncode(items.map((o) => o.toJson()).toList()),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- guide_cache --------------------------------------------------------
  Future<Guide?> getGuide(String title, String contextHash) async {
    final db = await _database;
    final rows = await db.query('guide_cache',
        columns: ['skill_category', 'response_json'],
        where: 'guide_title = ? AND context_hash = ?',
        whereArgs: [title, contextHash],
        limit: 1);
    if (rows.isEmpty) return null;
    final category = skillCategoryFromString(rows.first['skill_category'] as String?);
    final decoded = jsonDecode(rows.first['response_json'] as String);
    if (decoded is! Map<String, dynamic>) return null;
    return Guide.fromJson(decoded, category: category);
  }

  Future<void> putGuide(Guide guide, String contextHash,
      {String contextLabel = ''}) async {
    final db = await _database;
    await db.insert(
      'guide_cache',
      {
        'guide_title': guide.title,
        'skill_category': guide.category.id,
        'context_hash': contextHash,
        'response_json': jsonEncode(guide.toJson()),
        'context_label': contextLabel,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cached guides in a category, newest first — for the Guides library.
  Future<List<GuideSummary>> listGuidesByCategory(SkillCategory category) async {
    final db = await _database;
    final rows = await db.query(
      'guide_cache',
      columns: ['guide_title', 'skill_category', 'context_hash', 'context_label', 'cached_at'],
      where: 'skill_category = ?',
      whereArgs: [category.id],
      orderBy: 'cached_at DESC',
    );
    return rows
        .map((r) => GuideSummary(
              title: r['guide_title'] as String,
              category: skillCategoryFromString(r['skill_category'] as String?),
              contextHash: r['context_hash'] as String,
              contextLabel: (r['context_label'] as String?) ?? '',
              cachedAt:
                  DateTime.fromMillisecondsSinceEpoch(r['cached_at'] as int),
            ))
        .toList();
  }

  /// Count of cached guides per category, for the library's category cards.
  Future<Map<SkillCategory, int>> guideCountsByCategory() async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT skill_category, COUNT(*) AS c FROM guide_cache GROUP BY skill_category');
    final counts = <SkillCategory, int>{};
    for (final r in rows) {
      counts[skillCategoryFromString(r['skill_category'] as String?)] =
          r['c'] as int;
    }
    return counts;
  }

  // --- guide_progress (resume) -------------------------------------------
  Future<int?> getGuideProgress(String title, String contextHash) async {
    final db = await _database;
    final rows = await db.query('guide_progress',
        columns: ['current_step'],
        where: 'guide_title = ? AND context_hash = ?',
        whereArgs: [title, contextHash],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['current_step'] as int?;
  }

  Future<void> setGuideProgress(
      String title, String contextHash, int step) async {
    final db = await _database;
    await db.insert(
      'guide_progress',
      {
        'guide_title': title,
        'context_hash': contextHash,
        'current_step': step,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- deletion / management ---------------------------------------------
  /// Delete one cached guide AND its progress row (used by swipe-to-delete).
  Future<void> deleteGuide(String title, String contextHash) async {
    final db = await _database;
    await db.delete('guide_cache',
        where: 'guide_title = ? AND context_hash = ?',
        whereArgs: [title, contextHash]);
    await db.delete('guide_progress',
        where: 'guide_title = ? AND context_hash = ?',
        whereArgs: [title, contextHash]);
  }

  /// Clear ALL cached guides + their progress. Never touches trips/route_points.
  Future<void> clearGuideCache() async {
    final db = await _database;
    await db.delete('guide_cache');
    await db.delete('guide_progress');
  }

  /// Clear ALL cached opportunities. Never touches trips/route_points.
  Future<void> clearOpportunityCache() async {
    final db = await _database;
    await db.delete('opportunity_cache');
  }

  // --- trips / route_points (IRREPLACEABLE user data) ---------------------
  // Never touched by any cache-clearing action.
  Future<int> insertTrip({String? name, required DateTime startedAt}) async {
    final db = await _database;
    return db.insert('trips', {
      'name': name,
      'started_at': startedAt.millisecondsSinceEpoch,
    });
  }

  Future<void> insertRoutePoint(
      int tripId, double lat, double lng, DateTime at) async {
    final db = await _database;
    await db.insert('route_points', {
      'trip_id': tripId,
      'lat': lat,
      'lng': lng,
      'recorded_at': at.millisecondsSinceEpoch,
    });
  }

  Future<void> finishTrip(int tripId,
      {required DateTime endedAt, required double distanceMetres}) async {
    final db = await _database;
    await db.update(
      'trips',
      {
        'ended_at': endedAt.millisecondsSinceEpoch,
        'distance_metres': distanceMetres,
      },
      where: 'id = ?',
      whereArgs: [tripId],
    );
  }

  /// Trips with no ended_at — used to finalize a trip orphaned by an app kill.
  Future<List<Map<String, Object?>>> activeTrips() async {
    final db = await _database;
    return db.query('trips', where: 'ended_at IS NULL', orderBy: 'started_at DESC');
  }

  /// Finished trips, newest first — for the Journal list.
  Future<List<Trip>> listTrips() async {
    final db = await _database;
    final rows = await db.query('trips',
        where: 'ended_at IS NOT NULL', orderBy: 'started_at DESC');
    return rows.map(Trip.fromRow).toList();
  }

  Future<void> renameTrip(int id, String name) async {
    final db = await _database;
    await db.update('trips', {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Delete a trip and its route points (user-initiated; irreversible).
  Future<void> deleteTrip(int id) async {
    final db = await _database;
    await db.delete('route_points', where: 'trip_id = ?', whereArgs: [id]);
    await db.delete('trips', where: 'id = ?', whereArgs: [id]);
  }

  /// Ordered route for a trip (oldest first).
  Future<List<({LatLng latLng, DateTime recordedAt})>> routePoints(
      int tripId) async {
    final db = await _database;
    final rows = await db.query('route_points',
        columns: ['lat', 'lng', 'recorded_at'],
        where: 'trip_id = ?',
        whereArgs: [tripId],
        orderBy: 'recorded_at ASC');
    return rows
        .map((r) => (
              latLng: LatLng(
                  (r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
              recordedAt:
                  DateTime.fromMillisecondsSinceEpoch(r['recorded_at'] as int),
            ))
        .toList();
  }

  Future<int> countCachedGuides() => _count('guide_cache');
  Future<int> countCachedOpportunities() => _count('opportunity_cache');

  Future<int> _count(String table) async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
