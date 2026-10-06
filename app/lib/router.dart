import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/providers.dart';
import 'features/account/account_screen.dart';
import 'features/account/members_screen.dart';
import 'features/account/paywall_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/automation/assistant_screen.dart';
import 'features/automation/automation_screen.dart';
import 'features/devices/add_device_flow.dart';
import 'features/devices/calibration_screen.dart';
import 'features/devices/device_detail_screen.dart';
import 'features/devices/device_list_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/telemetry_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/onboarding/choose_business_screen.dart';
import 'features/shell/home_shell.dart';

class _AuthRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh();
  ref.listen(authUidProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);

  const publicPaths = {'/login', '/otp'};

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authUidProvider);
      if (auth.isLoading) return null;
      final signedIn = auth.value != null;
      final atPublic = publicPaths.contains(state.matchedLocation);
      if (!signedIn && !atPublic) return '/login';
      if (signedIn && atPublic) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/otp', builder: (_, s) => OtpScreen(args: s.extra as OtpArgs)),
      GoRoute(path: '/onboarding', builder: (_, _) => const ChooseBusinessScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/devices', builder: (_, _) => const DeviceListScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/automations', builder: (_, _) => const AutomationScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())]),
        ],
      ),
      GoRoute(
        path: '/telemetry/:hubId/:port',
        builder: (_, s) => TelemetryScreen(hubId: s.pathParameters['hubId']!, initialPort: s.pathParameters['port']!),
      ),
      GoRoute(path: '/device/:hubId', builder: (_, s) => DeviceDetailScreen(hubId: s.pathParameters['hubId']!)),
      GoRoute(
        path: '/calibrate/:hubId/:port',
        builder: (_, s) => CalibrationScreen(hubId: s.pathParameters['hubId']!, port: s.pathParameters['port']!),
      ),
      GoRoute(path: '/add-device', builder: (_, _) => const AddDeviceFlow()),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/assistant', builder: (_, _) => const AssistantScreen()),
      GoRoute(path: '/members', builder: (_, _) => const MembersScreen()),
      GoRoute(path: '/paywall', builder: (_, _) => const PaywallScreen()),
    ],
  );
});
