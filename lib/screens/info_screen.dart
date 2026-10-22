import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/region_pack.dart';
import '../services/api_key_store.dart';
import '../services/cache_repository.dart';
import '../services/carto_key_store.dart';
import '../services/os_maps_key_store.dart';
import '../services/overpass_server_store.dart';
import '../services/region_pack_service.dart';
import '../theme/app_theme.dart';

/// Info tab: API keys (Anthropic, OS Maps, CARTO, Overpass server), cache
/// management, credits, legal.
class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  final TextEditingController _anthropicController = TextEditingController();
  final TextEditingController _osController = TextEditingController();
  final TextEditingController _cartoController = TextEditingController();
  final TextEditingController _overpassController = TextEditingController();
  bool _anthropicObscure = true;
  bool _osObscure = true;
  bool _cartoObscure = true;
  bool _overpassObscure = true; // the URL carries the provider's key
  bool _hasAnthropic = false;
  bool _hasOsKey = false;
  bool _hasCartoKey = false;
  bool _hasOverpass = false;
  int _guideCount = 0;
  int _oppCount = 0;
  List<RegionPack> _packs = const [];
  final Map<String, PackState> _packStates = {};
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _anthropicController.dispose();
    _osController.dispose();
    _cartoController.dispose();
    _overpassController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final hasAnthropic = await ApiKeyStore.instance.hasKey();
    final hasOs = await OsMapsKeyStore.instance.hasKey();
    final hasCarto = await CartoKeyStore.instance.hasKey();
    final hasOverpass = await OverpassServerStore.instance.hasKey();
    final guides = await CacheRepository.instance.countCachedGuides();
    final opps = await CacheRepository.instance.countCachedOpportunities();
    final packs = await _loadPacks();
    if (!mounted) return;
    setState(() {
      _hasAnthropic = hasAnthropic;
      _hasOsKey = hasOs;
      _hasCartoKey = hasCarto;
      _hasOverpass = hasOverpass;
      _guideCount = guides;
      _oppCount = opps;
      _packs = packs;
    });
  }

  /// Load the pack catalogue + each pack's on-device state. Guarded so a missing
  /// asset/manifest never breaks the rest of the Info screen.
  Future<List<RegionPack>> _loadPacks() async {
    try {
      final packs = await RegionPackService.instance.allPacks();
      for (final pack in packs) {
        _packStates[pack.id] = await RegionPackService.instance.stateOf(pack);
      }
      return packs;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _downloadPack(RegionPack pack) async {
    setState(() => _downloading.add(pack.id));
    final ok = await RegionPackService.instance.ensureAvailable(pack);
    if (!mounted) return;
    setState(() => _downloading.remove(pack.id));
    await _refresh();
    _snack(ok ? '${pack.label} downloaded for offline use.' : 'Download failed.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Keys are usually pasted, so after saving one, clear it from the clipboard
  /// — where other apps (e.g. a keyboard's clipboard history) could still pick
  /// it up. Only when the clipboard still holds exactly that key, so nothing
  /// else the user copied is touched. Then confirm with [message].
  Future<void> _savedFromClipboard(String secret, String message) async {
    var cleared = false;
    try {
      final copied = await Clipboard.getData(Clipboard.kTextPlain);
      if (copied?.text?.trim() == secret) {
        await Clipboard.setData(const ClipboardData(text: ''));
        cleared = true;
      }
    } catch (_) {
      // Clipboard unavailable — the key is saved either way.
    }
    _snack(cleared ? '$message Cleared it from the clipboard.' : message);
  }

  Future<void> _saveAnthropic() async {
    final text = _anthropicController.text.trim();
    if (text.isEmpty) return;
    await ApiKeyStore.instance.write(text);
    _anthropicController.clear();
    await _refresh();
    await _savedFromClipboard(text, 'Anthropic key saved.');
  }

  Future<void> _clearAnthropic() async {
    await ApiKeyStore.instance.clear();
    await _refresh();
    _snack('Anthropic key removed.');
  }

  Future<void> _saveOs() async {
    final text = _osController.text.trim();
    if (text.isEmpty) return;
    await OsMapsKeyStore.instance.write(text);
    _osController.clear();
    await _refresh();
    await _savedFromClipboard(text, 'OS Maps key saved.');
  }

  Future<void> _clearOs() async {
    await OsMapsKeyStore.instance.clear();
    await _refresh();
    _snack('OS Maps key removed.');
  }

  Future<void> _saveCarto() async {
    final text = _cartoController.text.trim();
    if (text.isEmpty) return;
    await CartoKeyStore.instance.write(text);
    _cartoController.clear();
    await _refresh();
    await _savedFromClipboard(text, 'CARTO key saved.');
  }

  Future<void> _clearCarto() async {
    await CartoKeyStore.instance.clear();
    await _refresh();
    _snack('CARTO key removed.');
  }

  Future<void> _saveOverpass() async {
    final text = _overpassController.text.trim();
    if (text.isEmpty) return;
    if (!OverpassServerStore.isValid(text)) {
      _snack('Paste the full https:// server address from your provider.');
      return;
    }
    await OverpassServerStore.instance.write(text);
    _overpassController.clear();
    await _refresh();
    await _savedFromClipboard(text, 'Overpass server saved.');
  }

  Future<void> _clearOverpass() async {
    await OverpassServerStore.instance.clear();
    await _refresh();
    _snack('Overpass server removed — using the public servers.');
  }

  Future<void> _openLink(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) _snack('Could not open $url');
  }

  Future<void> _clearGuides() async {
    await CacheRepository.instance.clearGuideCache();
    await _refresh();
    _snack('Cached guides cleared.');
  }

  Future<void> _clearOpportunities() async {
    await CacheRepository.instance.clearOpportunityCache();
    await _refresh();
    _snack('Cached opportunities cleared.');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('HikeGuide', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Version 1.2.0',
              style: TextStyle(color: AppColors.secondaryText, fontSize: 14)),
          const SizedBox(height: 16),
          const Text(
            'A bushcraft field companion for hobbyist bushcrafters in England. '
            'Practice opportunities and guides are generated on demand and '
            'tailored to where you are standing.',
            style: TextStyle(color: AppColors.primaryText, fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 28),
          _keySection(
            title: 'Anthropic API key',
            hasKey: _hasAnthropic,
            controller: _anthropicController,
            obscure: _anthropicObscure,
            onToggleObscure: () =>
                setState(() => _anthropicObscure = !_anthropicObscure),
            hint: _hasAnthropic ? 'Enter a new key to replace' : 'sk-ant-…',
            helper: 'Generates opportunities and guides. Your account needs credit. '
                'Stored in the device secure store — never in the app database.',
            links: const [
              ('Get a key: Claude Console', 'https://platform.claude.com/settings/keys'),
            ],
            onSave: _saveAnthropic,
            onClear: _hasAnthropic ? _clearAnthropic : null,
          ),
          const SizedBox(height: 24),
          _keySection(
            title: 'OS Maps API key',
            hasKey: _hasOsKey,
            controller: _osController,
            obscure: _osObscure,
            onToggleObscure: () => setState(() => _osObscure = !_osObscure),
            hint: _hasOsKey ? 'Enter a new key to replace' : 'OS Data Hub project key',
            helper: 'Optional. Enables the OS "Outdoor" map layer on the Map tab. '
                'Free: add the OS Maps API to a project (OpenData plan — no card) '
                'and use its Project API Key.',
            links: const [
              ('Get a key: OS Data Hub', 'https://osdatahub.os.uk/'),
            ],
            onSave: _saveOs,
            onClear: _hasOsKey ? _clearOs : null,
          ),
          const SizedBox(height: 24),
          _keySection(
            title: 'CARTO basemap key',
            hasKey: _hasCartoKey,
            controller: _cartoController,
            obscure: _cartoObscure,
            onToggleObscure: () => setState(() => _cartoObscure = !_cartoObscure),
            hint: _hasCartoKey ? 'Enter a new key to replace' : 'CARTO basemaps key',
            helper: 'Needed for the dark map on the Map tab. Free, with no account '
                'or card needed.',
            links: const [
              ('Get a key: CARTO', 'https://carto.com/basemaps/apikey'),
            ],
            onSave: _saveCarto,
            onClear: _hasCartoKey ? _clearCarto : null,
          ),
          const SizedBox(height: 24),
          _keySection(
            title: 'Overpass server',
            hasKey: _hasOverpass,
            controller: _overpassController,
            obscure: _overpassObscure,
            onToggleObscure: () =>
                setState(() => _overpassObscure = !_overpassObscure),
            hint: _hasOverpass
                ? 'Enter a new address to replace'
                : 'https://…/interpreter (key included)',
            helper: 'Optional. Overpass finds nearby woodland and water for your '
                'opportunities. The free public servers need no key but are often '
                'overloaded. For a reliable one, sign up with a provider and paste '
                'its full server address, with your key in it. Used first; the '
                'public servers stay as the fallback.',
            links: const [
              ('Overpass.ch (free tier)', 'https://overpass.ch/'),
              (
                'Other providers',
                'https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances'
              ),
            ],
            saveLabel: 'Save server',
            onSave: _saveOverpass,
            onClear: _hasOverpass ? _clearOverpass : null,
          ),
          const SizedBox(height: 28),
          _buildStorageSection(context),
          const SizedBox(height: 28),
          _buildRegionsSection(context),
          const SizedBox(height: 28),
          _heading('Data credits'),
          const SizedBox(height: 8),
          ..._bullets(const [
            'OpenStreetMap contributors (map data)',
            'CARTO (dark basemap)',
            'Ordnance Survey (OS Maps API basemap)',
            'Natural England (CRoW Open Access)',
            'Forestry England',
          ]),
          const SizedBox(height: 24),
          _heading('Legal notice'),
          const SizedBox(height: 8),
          const Text(
            'General guidance only. You are responsible for verifying land '
            'access, fire permission, and any plant identification before acting.',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 24),
          // Year is read at build time, so it always shows the current year.
          Text(
            '© ${DateTime.now().year} Iconiel Ltd / Nathan Osborn',
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _keySection({
    required String title,
    required bool hasKey,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String hint,
    required String helper,
    List<(String label, String url)> links = const [],
    String saveLabel = 'Save key',
    required VoidCallback onSave,
    required VoidCallback? onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(title),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(hasKey ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: hasKey ? AppColors.accent : AppColors.secondaryText),
            const SizedBox(width: 8),
            Text(
              hasKey ? 'A key is stored on this device' : 'No key set',
              style: TextStyle(
                  color: hasKey ? AppColors.primaryText : AppColors.secondaryText,
                  fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(color: AppColors.primaryText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.secondaryText),
            filled: true,
            fillColor: AppColors.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: AppColors.secondaryText.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.secondaryText),
              onPressed: onToggleObscure,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(onPressed: onSave, child: Text(saveLabel)),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onClear,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.fire,
                  side: BorderSide(color: AppColors.fire.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                ),
                child: const Text('Remove'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          helper,
          style: const TextStyle(
              color: AppColors.secondaryText, fontSize: 13, height: 1.4),
        ),
        for (final (label, url) in links) _linkRow(label, url),
      ],
    );
  }

  /// A tappable link that opens [url] in the browser (where to get a key).
  Widget _linkRow(String label, String url) {
    return InkWell(
      onTap: () => _openLink(url),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.open_in_new, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Storage'),
        const SizedBox(height: 12),
        _storageRow('Cached guides', _guideCount, _guideCount == 0 ? null : _clearGuides),
        const SizedBox(height: 12),
        _storageRow('Cached opportunities', _oppCount,
            _oppCount == 0 ? null : _clearOpportunities),
        const SizedBox(height: 10),
        const Text(
          'Cleared guides simply regenerate next time they are opened. Your trip '
          'log is never affected by clearing caches.',
          style: TextStyle(color: AppColors.secondaryText, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildRegionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Offline regions'),
        const SizedBox(height: 12),
        if (_packs.isEmpty)
          const Text(
            'No region data available.',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 14),
          )
        else
          for (final pack in _packs) ...[
            _regionRow(pack),
            const SizedBox(height: 12),
          ],
        const Text(
          'Access-land data is delivered per region. Download the region you '
          'are visiting while you have signal, then use it offline in the field.',
          style: TextStyle(color: AppColors.secondaryText, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  Widget _regionRow(RegionPack pack) {
    final state = _packStates[pack.id] ?? PackState.notDownloaded;
    final busy = _downloading.contains(pack.id);
    final (String status, bool available) = switch (state) {
      PackState.bundled => ('Built in', true),
      PackState.downloaded => ('Downloaded', true),
      PackState.notDownloaded => ('Not downloaded', false),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(available ? Icons.offline_pin : Icons.cloud_download_outlined,
              size: 20,
              color: available ? AppColors.accent : AppColors.secondaryText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${pack.label} · ${pack.nation}',
                    style: const TextStyle(
                        color: AppColors.primaryText, fontSize: 16)),
                const SizedBox(height: 2),
                Text(status,
                    style: const TextStyle(
                        color: AppColors.secondaryText, fontSize: 13)),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (!available)
            TextButton(
              onPressed: () => _downloadPack(pack),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }

  Widget _storageRow(String label, int count, VoidCallback? onClear) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.primaryText, fontSize: 16)),
                const SizedBox(height: 2),
                Text('$count stored',
                    style: const TextStyle(
                        color: AppColors.secondaryText, fontSize: 13)),
              ],
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.fire,
              disabledForegroundColor: AppColors.secondaryText.withValues(alpha: 0.4),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _heading(String title) => Text(
        title,
        style: const TextStyle(
            color: AppColors.primaryText, fontSize: 18, fontWeight: FontWeight.w600),
      );

  List<Widget> _bullets(List<String> items) => items
      .map(
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ',
                  style: TextStyle(color: AppColors.accent, fontSize: 15)),
              Expanded(
                child: Text(i,
                    style: const TextStyle(
                        color: AppColors.secondaryText, fontSize: 15, height: 1.4)),
              ),
            ],
          ),
        ),
      )
      .toList();
}
