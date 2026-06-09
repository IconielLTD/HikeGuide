import 'package:flutter/foundation.dart';

/// One on-demand region of access-land data, plus the nation whose access law
/// applies inside it. A pack is either **bundled** in the APK (`asset`) or
/// **downloaded** from a URL (future remote packs hosted on GitHub Releases).
/// RegionPackService resolves which, and where the data lives on the device.
@immutable
class RegionPack {
  final String id; // stable key, e.g. "east-midlands"
  final String nation; // "England" | "Scotland" | "Wales"
  final String label; // human name, e.g. "East Midlands"
  final String version; // bump to trigger re-download / cache refresh
  final String? asset; // bundled asset path (null for remote packs)
  final String? url; // remote download URL (null for bundled packs)
  final String? sha256; // integrity check for a downloaded pack
  final int? sizeBytes; // for showing a download size in the UI

  const RegionPack({
    required this.id,
    required this.nation,
    required this.label,
    required this.version,
    this.asset,
    this.url,
    this.sha256,
    this.sizeBytes,
  });

  /// True for packs shipped inside the APK — always available offline.
  bool get isBundled => asset != null;

  factory RegionPack.fromJson(Map<String, dynamic> json) => RegionPack(
        id: json['id'] as String,
        nation: json['nation'] as String? ?? 'England',
        label: json['label'] as String? ?? (json['id'] as String? ?? 'Region'),
        version: json['version']?.toString() ?? '0',
        asset: json['asset'] as String?,
        url: json['url'] as String?,
        sha256: json['sha256'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      );
}

/// Parsed `manifest.json` — the catalogue of packs the app can offer.
@immutable
class PackManifest {
  final int schema;
  final List<RegionPack> packs;

  const PackManifest({required this.schema, required this.packs});

  RegionPack? byId(String id) {
    for (final p in packs) {
      if (p.id == id) return p;
    }
    return null;
  }

  factory PackManifest.fromJson(Map<String, dynamic> json) {
    final raw = (json['packs'] as List?) ?? const [];
    return PackManifest(
      schema: (json['schema'] as num?)?.toInt() ?? 1,
      packs: raw
          .whereType<Map>()
          .map((m) => RegionPack.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }
}
