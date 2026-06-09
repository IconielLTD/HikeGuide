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
/// Phase 1: the manifest + the single "East Midlands" pack are bundled assets,
/// so everything resolves locally with no network. The remote path (fetch the
/// manifest from [remoteManifestUrl], download a pack by URL, verify its
/// sha256, cache it on disk) is implemented and ready — it activates as soon as
/// packs are published to GitHub Releases and the manifest lists `url`s.
class RegionPackService {
  RegionPackService._();
  static final RegionPackService instance = RegionPackService._();

  /// Where the published manifest will live once packs ship on GitHub Releases.
  /// Empty → use the bundled bootstrap manifest only (Phase 1).
  static const String remoteManifestUrl = '';

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
    if (remoteManifestUrl.isNotEmpty) {
      try {
        final res = await _dio.get<String>(remoteManifestUrl,
            options: Options(responseType: ResponseType.plain));
        final decoded = jsonDecode(res.data ?? '');
        if (decoded is Map<String, dynamic>) return PackManifest.fromJson(decoded);
      } catch (e) {
        debugPrint('RegionPackService: remote manifest failed ($e); using bundled');
      }
    }
    final raw = await rootBundle.loadString(_bundledManifest);
    return PackManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PackResolver> _resolver() => _resolverFuture ??= _loadResolver();

  Future<PackResolver> _loadResolver() async {
    final raw = await rootBundle.loadString(_bundledCoverage);
    return PackResolver(PackResolver.parseCoverage(raw));
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
