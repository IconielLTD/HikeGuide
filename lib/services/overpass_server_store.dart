import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores an optional Overpass server address in the device secure store. The
/// public Overpass servers need no key but are often overloaded; keyed
/// providers (Overpass.ch, NextGIS, Geofabrik, …) put the key INSIDE the URL,
/// each in its own format, so we store the provider's full interpreter URL —
/// key included — rather than a bare key. Tried before the public servers.
class OverpassServerStore {
  OverpassServerStore._();
  static final OverpassServerStore instance = OverpassServerStore._();

  static const String _key = 'overpass_server_url';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// The stored address, normalised to the provider's interpreter endpoint.
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : normalise(trimmed);
  }

  Future<bool> hasKey() async => (await read()) != null;

  Future<void> write(String url) => _storage.write(key: _key, value: url.trim());

  Future<void> clear() => _storage.delete(key: _key);

  /// Providers' dashboards often show the BASE address meant for Overpass Turbo
  /// / JOSM (e.g. `https://api.overpass.ch/v1/<KEY>/`), which those tools
  /// complete with `interpreter`. Every provider's API endpoint ends in
  /// `…/interpreter`, so complete it here too; a full address is unchanged.
  static String normalise(String url) {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.last == 'interpreter') return trimmed;
    return uri.replace(pathSegments: [...segments, 'interpreter']).toString();
  }

  /// True for an https URL with a host — the minimum to be worth trying.
  static bool isValid(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }
}
