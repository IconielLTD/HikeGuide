import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the Anthropic API key in the platform secure store — NEVER in SQLite.
class ApiKeyStore {
  ApiKeyStore._();
  static final ApiKeyStore instance = ApiKeyStore._();

  static const String _key = 'anthropic_api_key';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Returns a non-empty trimmed key, or null if unset/blank.
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<bool> hasKey() async => (await read()) != null;

  Future<void> write(String key) => _storage.write(key: _key, value: key.trim());

  Future<void> clear() => _storage.delete(key: _key);
}
