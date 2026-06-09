import 'package:flutter/material.dart';

import 'screens/root_nav.dart';
import 'services/access_land_service.dart';
import 'services/cache_repository.dart';
import 'services/content_service.dart';
import 'services/trip_recorder.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Two cheap DB touches at startup, both non-fatal so they never block launch:
  //  - drop stale detections if the bundled access data changed since last run;
  //  - finalize any trip left "active" by an app kill (no zombie recordings).
  try {
    await CacheRepository.instance.reconcileAccessDataVersion(kAccessDataVersion);
  } catch (_) {}
  try {
    // Drop stale opportunity/guide caches when the content prompts change.
    await CacheRepository.instance.reconcileContentVersion(kContentVersion);
  } catch (_) {}
  try {
    await TripRecorder.instance.finalizeOrphans();
  } catch (_) {}
  runApp(const HikeGuideApp());
}

class HikeGuideApp extends StatelessWidget {
  const HikeGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HikeGuide',
      debugShowCheckedModeBanner: false,
      theme: buildHikeGuideTheme(),
      home: const RootNav(),
    );
  }
}
