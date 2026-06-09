import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../models/region_pack.dart';
import 'pack_resolver.dart';

/// Whether a pack's data is on the device right now.
enum PackState {
  /// Shipped inside the APK — always usable offline.
  bundled,

  /// A remote pack already downloaded + cached.
  downloaded,

  /// A remote pack not yet downloaded.
  notDownloaded,
}

/// Decides which region pack applies to the user's location, and makes its data
/// available offline.
///
/// By default the manifest, coverage index, and packs are all bundled assets,
/// so everything resolves locally with no network. Set [remoteBaseUrl] to a
/// published location (a GitHub Release's download URL) and the app instead
/// fetches `manifest.json` + `coverage.geojson` from there on launch — falling
/// back to the bundled copies when offline — and downloads each pack by URL
/// (verifying its sha256, caching it on disk). That lets you add or refresh
/// regions by re-uploading those files, with no app update.
class RegionPackService extends ChangeNotifier {
  RegionPackService._();
  static final RegionPackService instance = RegionPackService._();

  /// Base URL of the published pack assets — a GitHub Release's download URL,
  /// e.g. https://github.com/<you>/<repo>/releases/download/<tag>. Leave empty
  /// to run fully bundled/offline (manifest + coverage + packs from assets).
  /// When set, the app fetches `manifest.json` and `coverage.geojson` from this
  /// base on launch (falling back to the bundled copies if offline), so regions
  /// can be added or refreshed by re-uploading files — no app update needed.
  static const String remoteBaseUrl = '';

  static const String _bundledManifest = 'assets/packs/manifest.json';
  static const String _bundledCoverage = 'assets/packs/coverage.geojson';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Future<PackManifest>? _manifestFuture;
  Future<PackResolver>? _resolverFuture;

  String? _packsDirOverride;

  /// Inject a writable directory in tests (avoids needing a sqflite factory).
  @visibleForTesting
  set packsDirForTest(String path) => _packsDirOverride = path;

  // --- manifest + coverage (lazy, cached) ----------------------------------

  Future<PackManifest> manifest() => _manifestFuture ??= _loadManifest();

  Future<PackManifest> _loadManifest() async {
    final raw = await _loadIndex('manifest.json', _bundledManifest);
    return PackManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PackResolver> _resolver() => _resolverFuture ??= _loadResolver();

  Future<PackResolver> _loadResolver() async {
    final raw = await _loadIndex('coverage.geojson', _bundledCoverage);
    return PackResolver(PackResolver.parseCoverage(raw));
  }

  /// Load a small index file (manifest or coverage): from [remoteBaseUrl] when
  /// set, otherwise from the bundled asset. Any network error falls back to the
  /// bundled copy, so the app always works offline.
  Future<String> _loadIndex(String remoteName, String bundledAsset) async {
    if (remoteBaseUrl.isNotEmpty) {
      try {
        final base = remoteBaseUrl.replaceAll(RegExp(r'/+$'), '');
        final res = await _dio.get<String>('$base/$remoteName',
            options: Options(responseType: ResponseType.plain));
        final body = res.data;
        if (body != null && body.isNotEmpty) return body;
      } catch (e) {
        debugPrint('RegionPackService: remote $remoteName failed ($e); using bundled');
      }
    }
    return rootBundle.loadString(bundledAsset);
  }

  // --- resolution ----------------------------------------------------------

  Future<CoverageArea?> coverageAt(LatLng at) async =>
      (await _resolver()).areaAt(at.latitude, at.longitude);

  /// Nation whose access law applies at [at]. Known from the bundled coverage
  /// index even before the pack data is downloaded; null if uncovered.
  Future<String?> nationAt(LatLng at) async => (await coverageAt(at))?.nation;

  /// The pack covering [at], or null if outside all coverage.
  Future<RegionPack?> packFor(LatLng at) async {
    final area = await coverageAt(at);
    if (area == null) return null;
    return (await manifest()).byId(area.packId);
  }

  Future<List<RegionPack>> allPacks() async => (await manifest()).packs;

  // --- availability + data -------------------------------------------------

  Future<PackState> stateOf(RegionPack pack) async {
    if (pack.isBundled) return PackState.bundled;
    return await File(await _packPath(pack)).exists()
        ? PackState.downloaded
        : PackState.notDownloaded;
  }

  Future<bool> isAvailable(RegionPack pack) async =>
      (await stateOf(pack)) != PackState.notDownloaded;

  /// Raw GeoJSON for [pack] if it's available offline, else null.
  Future<String?> rawGeoJson(RegionPack pack) async {
    if (pack.isBundled) {
      try {
        return await rootBundle.loadString(pack.asset!);
      } catch (_) {
        return null;
      }
    }
    final file = File(await _packPath(pack));
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Ensure [pack]'s data is on the device, downloading it if needed. No-op for
  /// bundled packs. Returns true once the pack is usable offline. Lets a user
  /// pre-download a region at home before heading out of signal.
  Future<bool> ensureAvailable(RegionPack pack,
      {void Function(int received, int total)? onProgress}) async {
    if (await isAvailable(pack)) return true;
    if (pack.url == null) return false;
    try {
      final res = await _dio.get<List<int>>(
        pack.url!,
        onReceiveProgress: onProgress,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return false;
      if (pack.sha256 != null &&
          sha256.convert(bytes).toString() != pack.sha256) {
        debugPrint('RegionPackService: ${pack.id} sha256 mismatch — discarding');
        return false;
      }
      final file = File(await _packPath(pack));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      notifyListeners(); // a pack just became available — let the Map/Now refresh
      return true;
    } catch (e) {
      debugPrint('RegionPackService: download ${pack.id} failed ($e)');
      return false;
    }
  }

  /// Versioned filename so a bumped pack downloads fresh rather than reusing a
  /// stale cached copy.
  Future<String> _packPath(RegionPack pack) async {
    final dir =
        _packsDirOverride ?? p.join(p.dirname(await getDatabasesPath()), 'packs');
    return p.join(dir, '${pack.id}-${pack.version}.geojson');
  }
}
