import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the OS Data Hub (OS Maps API) key in the device secure store — used
/// only for the optional OS "Outdoor" basemap. Separate from the Anthropic key.
class OsMapsKeyStore {
  OsMapsKeyStore._();
  static final OsMapsKeyStore instance = OsMapsKeyStore._();

  static const String _key = 'os_maps_api_key';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<bool> hasKey() async => (await read()) != null;

  Future<void> write(String key) => _storage.write(key: _key, value: key.trim());

  Future<void> clear() => _storage.delete(key: _key);
}
