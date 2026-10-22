import 'package:flutter/foundation.dart';

/// Keys must never reach the device log: anyone with ADB access or a bug
/// report from the phone can read it. They can get there indirectly — e.g.
/// flutter_map logs the full URL of any map tile that fails to load, and the
/// CARTO and OS keys are `?key=` parameters on those URLs.
///
/// [installLogRedaction] routes every [debugPrint] (ours and packages') through
/// [redactSecrets], and drops log output entirely in release builds, where
/// nobody is reading it anyway. Call it first thing in `main()`.
void installLogRedaction() {
  final DebugPrintCallback platformPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (kReleaseMode || message == null) return;
    platformPrint(redactSecrets(message), wrapWidth: wrapWidth);
  };
}

final List<(RegExp, String)> _patterns = [
  // URL query parameters that carry keys: ?key=…, &api_key=…, &token=…
  (
    RegExp(r'([?&](?:key|api_key|apikey|access_token|token)=)[^&\s"<>]+',
        caseSensitive: false),
    r'$1•••'
  ),
  // Anthropic API keys anywhere in the text.
  (RegExp(r'sk-ant-[A-Za-z0-9_\-]+'), 'sk-ant-•••'),
  // An x-api-key header if a request dump is ever logged.
  (
    RegExp(r'''(x-api-key["']?\s*[:=]\s*["']?)[^\s"',}]+''',
        caseSensitive: false),
    r'$1•••'
  ),
];

/// [text] with any API keys it contains replaced by `•••`.
String redactSecrets(String text) {
  var out = text;
  for (final (pattern, replacement) in _patterns) {
    out = out.replaceAllMapped(
      pattern,
      (m) => replacement.replaceAllMapped(
        RegExp(r'\$(\d)'),
        (g) => m.group(int.parse(g.group(1)!)) ?? '',
      ),
    );
  }
  return out;
}
