import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/providers.dart';
import 'router.dart';

class SysnergiApp extends ConsumerWidget {
  const SysnergiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final largeText = ref.watch(profileProvider).value?.largeText ?? false;
    return MaterialApp.router(
      title: 'Sysnergi',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      // Sakelar "Tulisan lebih besar" (Akun · Kenyamanan) memperbesar seluruh teks.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: largeText ? const TextScaler.linear(1.2) : mq.textScaler),
          child: child!,
        );
      },
    );
  }
}
