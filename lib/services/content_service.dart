import '../models/environment_context.dart';
import '../models/guide.dart';
import '../models/opportunity.dart';
import '../models/skill_category.dart';
import 'anthropic_client.dart';
import 'cache_repository.dart';

/// Bump when the prompts below change so stale cached opportunities/guides are
/// dropped on next launch (see CacheRepository.reconcileContentVersion) and the
/// new wording/length is regenerated on demand. Date-stamped for readability.
const String kContentVersion = 'plain-beginner-2026-06-09';

/// Ties the prompts + the shared API utility + the cache together.
///   getOpportunities: cache by context_hash, call Haiku only on miss/refresh.
///   getGuide:         cache by (title, context_hash), call Haiku only on miss.
class ContentService {
  ContentService._();
  static final ContentService instance = ContentService._();

  final AnthropicClient _client = AnthropicClient.instance;
  final CacheRepository _cache = CacheRepository.instance;

  Future<List<Opportunity>> getOpportunities(
    EnvironmentContext env, {
    bool forceRefresh = false,
  }) async {
    final hash = CacheRepository.contextHash(env);
    if (!forceRefresh) {
      final cached = await _cache.getOpportunities(hash);
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final json = await _client.generateJson(
      system: _opportunitiesSystem,
      userPrompt: _opportunitiesUser(env),
      maxTokens: 1024,
    );

    final raw = (json['opportunities'] as List?) ?? const [];
    final opportunities = raw
        .whereType<Map<String, dynamic>>()
        .map(Opportunity.fromJson)
        .where((o) => o.title.isNotEmpty)
        .toList();
    if (opportunities.isEmpty) {
      throw ApiFailureException('No opportunities returned');
    }

    await _cache.putOpportunities(hash, opportunities);
    return opportunities;
  }

  Future<Guide> getGuide(
    EnvironmentContext env, {
    required String title,
    required SkillCategory category,
    bool forceRefresh = false,
  }) async {
    final hash = CacheRepository.contextHash(env);
    if (!forceRefresh) {
      final cached = await _cache.getGuide(title, hash);
      if (cached != null) return cached;
    }

    final json = await _client.generateJson(
      system: _guideSystem,
      userPrompt: _guideUser(env, title),
      maxTokens: 2048,
    );

    final parsed = Guide.fromJson(json, category: category);
    // Store/display under the tapped opportunity title + its category so the
    // cache key stays stable and re-opens hit (the LLM may word the title
    // differently). Keep the LLM's steps/fire_warning/legal_note.
    final guide = Guide(
      title: title,
      category: category,
      steps: parsed.steps,
      fireWarning: parsed.fireWarning,
      legalNote: parsed.legalNote,
    );
    if (guide.steps.isEmpty) {
      throw ApiFailureException('Empty guide returned');
    }

    await _cache.putGuide(guide, hash, contextLabel: _contextLabel(env));
    return guide;
  }

  /// Short human label shown in the Guides library, e.g. "mixed deciduous · summer".
  String _contextLabel(EnvironmentContext env) =>
      '${env.woodlandType} · ${env.season}';

  // --- Prompts ------------------------------------------------------------
  // Audience + voice: an ordinary adult with NO bushcraft, map or compass
  // experience, who wants to feel at home and capable in nature — the hunter,
  // not the prey. Plain English, short, doable-right-now, never dramatised.
  // NOTE: the shared utility forces a JSON OBJECT via assistant prefill "{", so
  // the opportunities prompt asks for an object wrapping the array (rather than
  // a bare top-level array) — same data, one parse path.
  static const String _opportunitiesSystem =
      'You are a warm, encouraging bushcraft mentor in the calm, unhurried '
      'tradition of Ray Mears. You write for an ordinary adult with NO prior '
      'bushcraft, map or compass experience. The aim of the app is to help people '
      'feel at home in nature — capable, calm and quietly confident, the hunter '
      'not the prey, never scared or lost. '
      'Suggest realistic, satisfying things they can actually DO right now in the '
      'place described, with little or no special equipment — hands-on tasks '
      '(reading animal tracks and signs, following a simple direction to a '
      'landmark, finding a sheltered spot, noticing useful plants to identify '
      'properly) over abstract theory. Keep every suggestion grounded in THIS '
      'habitat and season. Use plain, everyday words — no jargon, no acronyms. '
      'For any plant, describe only what to look for and how to confirm it with a '
      'trusted source; NEVER state a plant is safe to eat. '
      'Respond only in JSON, no prose, no fences.';

  String _opportunitiesUser(EnvironmentContext env) {
    final water = env.hasWater
        ? '${env.waterDistanceMetres.round()}m ${env.waterDirection}'
            '${env.waterKind.isEmpty ? '' : ' (${env.waterKind})'}'
        : 'no surface water within ~1.5 km';
    return 'Suggest practice opportunities for: woodland type '
        '${env.woodlandType}, season ${env.season}, month ${env.month}, land '
        'access ${env.accessStatus}, nearest water $water, region ${env.region}. '
        'Return a JSON object with a single key "opportunities" whose value is an '
        'array of 4-6 objects, each with: '
        'skill_category (one of navigation|tracking|shelter|fire|foraging); '
        'title (max 8 words, inviting and plain, e.g. "Read deer tracks by the '
        'stream"); '
        'description (ONE short, plain-English sentence on what to do here and why '
        "it's worth it); "
        'fire_warning (boolean, true only for fire-lighting tasks). '
        'Include at least one wildlife tracking task when the habitat suits it, '
        'and prefer tasks that need no special kit.';
  }

  static const String _guideSystem =
      'You are a warm, encouraging bushcraft mentor in the calm, unhurried '
      'tradition of Ray Mears. You write for an ordinary adult with NO prior '
      'bushcraft, map or compass experience, who wants to feel at home and '
      'capable in nature — the hunter, not the prey. '
      'Write SHORT, plain-English, do-this-now instructions: 3 to 6 steps, NEVER '
      'more than 6. One simple action per step, in everyday words — no jargon or '
      'acronyms; if a term is unavoidable, explain it in a few plain words. Say '
      'what to do and why, not the theory behind it. Encourage, never dramatise. '
      'Always include leaving no trace. '
      'For fire, state whether the given access type permits fires, and that Open '
      'Access and Forestry England land do NOT grant fire permission. For '
      'foraging, describe how to identify and confirm with a trusted source, and '
      'NEVER assert anything is safe to eat. The app already shows the user their '
      'live OS grid reference and the local magnetic declination on screen, so '
      'for navigation tell them to read those on-screen values rather than fetch '
      'a paper map or look up declination separately. '
      'Respond only in JSON, no prose, no fences.';

  String _guideUser(EnvironmentContext env, String title) {
    return 'Write a short beginner guide for: $title. Context: woodland '
        '${env.woodlandType}, season ${env.season}, month ${env.month}, access '
        '${env.accessStatus}, region ${env.region}. Use 3-6 plain steps (never '
        'more than 6). Return JSON: { title, steps: [{step, text}], fire_warning: '
        'boolean, legal_note: string|null }';
  }
}
