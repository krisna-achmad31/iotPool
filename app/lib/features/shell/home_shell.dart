import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Tab bar kaca mengambang (Beranda · Perangkat · Otomasi · Akun).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    (Icons.memory_outlined, Icons.memory_rounded, 'Perangkat'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Otomasi'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Akun'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 72,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.glassStrong,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: AppColors.glassStroke, width: 1.5),
              ),
              child: Row(children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _Tab(
                      icon: shell.currentIndex == i ? _tabs[i].$2 : _tabs[i].$1,
                      label: _tabs[i].$3,
                      active: shell.currentIndex == i,
                      onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: active,
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: active ? AppColors.blueGradient : null,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 24, color: active ? Colors.white : AppColors.ink2),
              const SizedBox(height: 3),
              Text(label, style: T.s(12, w: active ? FontWeight.w600 : FontWeight.w400, c: active ? Colors.white : AppColors.ink2)),
            ]),
          ),
        ),
      );
}
