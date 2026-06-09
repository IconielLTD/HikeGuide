import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_key_store.dart';

/// The Haiku model used for ALL guide/opportunity content. This string is
/// current as of mid-2026 but WILL be deprecated eventually — it lives here, in
/// ONE place. See README for the periodic-update note.
const String kHaikuModel = 'claude-haiku-4-5-20251001';

/// Thrown when no API key is configured — screens should route the user to the
/// Info tab rather than firing a doomed request.
class NeedsSetupException implements Exception {
  final String message;
  NeedsSetupException([this.message = 'No Anthropic API key set']);
  @override
  String toString() => message;
}

/// Thrown on network failure or unparseable output after one retry. Screens must
/// render a calm failure state with a retry button — never a permanent spinner.
class ApiFailureException implements Exception {
  final String message;
  ApiFailureException([this.message = 'Could not generate this here']);
  @override
  String toString() => message;
}

class _ParseFailure implements Exception {
  final String message;
  _ParseFailure(this.message);
}

/// Single entry point to the Anthropic Messages API. Returns parsed JSON.
///
/// Forces valid JSON by PREFILLING the assistant turn with "{" and prepending
/// "{" back to the returned text before parsing; strips ``` fences defensively.
/// Retries once, then throws [ApiFailureException].
class AnthropicClient {
  AnthropicClient._();
  static final AnthropicClient instance = AnthropicClient._();

  static const String _endpoint = 'https://api.anthropic.com/v1/messages';
  static const String _anthropicVersion = '2023-06-01';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Future<Map<String, dynamic>> generateJson({
    required String system,
    required String userPrompt,
    int maxTokens = 1024,
  }) async {
    final String? apiKey = await ApiKeyStore.instance.read();
    if (apiKey == null) throw NeedsSetupException();

    final Map<String, dynamic> body = {
      'model': kHaikuModel,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': userPrompt},
        // PREFILL: force the model to start a JSON object.
        {'role': 'assistant', 'content': '{'},
      ],
    };

    Object? lastError;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final Response<dynamic> res = await _dio.post(
          _endpoint,
          data: body,
          options: Options(headers: {
            'x-api-key': apiKey,
            'anthropic-version': _anthropicVersion,
            'content-type': 'application/json',
          }),
        );
        final String text = _extractText(res.data);
        return _parseJsonObject(text);
      } on DioException catch (e) {
        lastError = _describeDio(e);
        // retry once on transient network/server issues
      } on _ParseFailure catch (e) {
        lastError = e.message;
        // retry once on bad JSON
      } catch (e) {
        lastError = e;
      }
    }
    debugPrint('AnthropicClient failure after retry: $lastError');
    throw ApiFailureException('$lastError');
  }

  String _extractText(dynamic data) {
    if (data is Map && data['content'] is List) {
      final buffer = StringBuffer();
      for (final block in (data['content'] as List)) {
        if (block is Map && block['type'] == 'text' && block['text'] != null) {
          buffer.write(block['text']);
        }
      }
      final out = buffer.toString();
      if (out.trim().isEmpty) throw _ParseFailure('Empty response');
      return out;
    }
    throw _ParseFailure('Unexpected response shape');
  }

  Map<String, dynamic> _parseJsonObject(String modelText) {
    String s = _stripFences(modelText).trim();
    // The assistant turn was prefilled with "{"; if the model continued from it
    // (so its text doesn't already start with "{"), restore the brace.
    if (!s.startsWith('{')) s = '{$s';

    final direct = _tryDecodeObject(s);
    if (direct != null) return direct;

    // Defensive: trim to the outermost braces in case of trailing prose.
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start != -1 && end > start) {
      final trimmed = _tryDecodeObject(s.substring(start, end + 1));
      if (trimmed != null) return trimmed;
    }
    throw _ParseFailure('Not a valid JSON object');
  }

  Map<String, dynamic>? _tryDecodeObject(String s) {
    try {
      final decoded = jsonDecode(s);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _stripFences(String input) {
    var out = input.trim();
    out = out.replaceFirst(RegExp(r'^```(json)?', caseSensitive: false), '');
    if (out.endsWith('```')) out = out.substring(0, out.length - 3);
    return out.trim();
  }

  String _describeDio(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    // Anthropic errors come back as {"type":"error","error":{"type","message"}}.
    String apiMsg = '';
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      apiMsg = '${err['type'] ?? ''}: ${err['message'] ?? ''}'.trim();
    } else if (data is String && data.trim().isNotEmpty) {
      apiMsg = data.length > 200 ? data.substring(0, 200) : data;
    }
    if (code != null) {
      return 'HTTP $code${apiMsg.isEmpty ? '' : ' — $apiMsg'}';
    }
    // No HTTP response = real connectivity/TLS/DNS problem.
    final msg = e.message;
    return '${e.type.name}${msg == null ? '' : ' ($msg)'}';
  }
}
