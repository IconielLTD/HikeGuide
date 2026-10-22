import 'package:flutter_test/flutter_test.dart';
import 'package:hike_guide/services/log_redaction.dart';

void main() {
  group('redactSecrets', () {
    test('masks tile-URL keys (how flutter_map logs a failed tile)', () {
      const line = 'HTTP request failed, statusCode: 401, '
          'https://basemaps.cartocdn.com/rastertiles/dark_all/15/1/2.png?key=abc123XYZ';
      expect(redactSecrets(line), isNot(contains('abc123XYZ')));
      expect(redactSecrets(line), endsWith('2.png?key=•••'));
    });

    test('masks the key but keeps the other query parameters', () {
      expect(redactSecrets('https://x.test/t.png?key=SECRET&style=dark'),
          'https://x.test/t.png?key=•••&style=dark');
      expect(redactSecrets('https://x.test/?a=1&api_key=SECRET'),
          'https://x.test/?a=1&api_key=•••');
    });

    test('masks Anthropic keys and x-api-key headers', () {
      expect(redactSecrets('key sk-ant-api03-AbC_d-1 rejected'),
          'key sk-ant-••• rejected');
      expect(redactSecrets('{x-api-key: s3cr3t, content-type: json}'),
          '{x-api-key: •••, content-type: json}');
    });

    test('leaves ordinary log lines alone', () {
      const line = 'Overpass https://overpass-api.de/api/interpreter failed: '
          'badResponse (HTTP 502)';
      expect(redactSecrets(line), line);
    });
  });
}
