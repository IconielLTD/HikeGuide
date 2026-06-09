import 'package:flutter/material.dart';

import '../models/region_pack.dart';
import '../services/api_key_store.dart';
import '../services/cache_repository.dart';
import '../services/os_maps_key_store.dart';
import '../services/region_pack_service.dart';
import '../theme/app_theme.dart';

/// Info tab: API keys (Anthropic + OS Maps), cache management, credits, legal.
class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  final TextEditingController _anthropicController = TextEditingController();
  final TextEditingController _osController = TextEditingController();
  bool _anthropicObscure = true;
  bool _osObscure = true;
  bool _hasAnthropic = false;
  bool _hasOsKey = false;
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
    super.dispose();
  }

  Future<void> _refresh() async {
    final hasAnthropic = await ApiKeyStore.instance.hasKey();
    final hasOs = await OsMapsKeyStore.instance.hasKey();
    final guides = await CacheRepository.instance.countCachedGuides();
    final opps = await CacheRepository.instance.countCachedOpportunities();
    final packs = await _loadPacks();
    if (!mounted) return;
    setState(() {
      _hasAnthropic = hasAnthropic;
      _hasOsKey = hasOs;
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

  Future<void> _saveAnthropic() async {
    final text = _anthropicController.text.trim();
    if (text.isEmpty) return;
    await ApiKeyStore.instance.write(text);
    _anthropicController.clear();
    await _refresh();
    _snack('Anthropic key saved.');
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
    _snack('OS Maps key saved.');
  }

  Future<void> _clearOs() async {
    await OsMapsKeyStore.instance.clear();
    await _refresh();
    _snack('OS Maps key removed.');
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
          const Text('Version 1.0.0',
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
            helper: 'Generates opportunities and guides. Stored in the device '
                'secure store — never in the app database.',
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
                'Free from osdatahub.os.uk (OS Maps API, OpenData plan — no card).',
            onSave: _saveOs,
            onClear: _hasOsKey ? _clearOs : null,
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
              child: ElevatedButton(onPressed: onSave, child: const Text('Save key')),
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
      ],
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
