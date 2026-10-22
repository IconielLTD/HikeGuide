import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the CARTO basemaps key in the device secure store — required (since
/// late 2026) for the dark basemap on the Map tab. Each user adds their own.
/// Notifies listeners on change so the long-lived Map tab picks up a key added
/// in the Info tab without a restart.
class CartoKeyStore extends ChangeNotifier {
  CartoKeyStore._();
  static final CartoKeyStore instance = CartoKeyStore._();

  static const String _key = 'carto_api_key';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<bool> hasKey() async => (await read()) != null;

  Future<void> write(String key) async {
    await _storage.write(key: _key, value: key.trim());
    notifyListeners();
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
    notifyListeners();
  }
}
