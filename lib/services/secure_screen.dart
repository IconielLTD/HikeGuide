import 'package:flutter/services.dart';

/// Android FLAG_SECURE for screens that show API keys (the Info tab): while
/// on, the system blocks screenshots and screen recording of the app window
/// and blanks it in the recent-apps switcher, so a key revealed with the eye
/// icon can't be captured. Implemented in MainActivity.kt.
class SecureScreen {
  SecureScreen._();

  static const MethodChannel _channel = MethodChannel('hikeguide/secure_screen');

  /// Best-effort: a failure (e.g. a platform without the channel, as in
  /// widget tests) leaves the screen as it was rather than crashing.
  static Future<void> set(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } catch (_) {}
  }
}
