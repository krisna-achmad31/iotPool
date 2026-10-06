import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/demo_repository.dart';
import 'data/firebase_repository.dart';
import 'data/providers.dart';
import 'data/provisioning.dart';
import 'firebase_options.dart';

/// `flutter run` → mode demo (data contoh).
/// `flutter run --dart-define=SYSNERGI_MODE=firebase` → Firebase asli (butuh `flutterfire configure`).
const _mode = String.fromEnvironment('SYSNERGI_MODE', defaultValue: 'demo');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id');

  final useFirebase = _mode == 'firebase';
  if (useFirebase) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  runApp(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(useFirebase ? FirebaseRepository() : DemoRepository()),
      provisionerProvider.overrideWithValue(useFirebase ? BleHubProvisioner() : DemoProvisioner()),
    ],
    child: const SysnergiApp(),
  ));
}
