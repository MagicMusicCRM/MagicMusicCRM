import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/services/access_invalidation_provider.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'routerProvider keeps one GoRouter across auth and gate updates',
    () async {
      final authController = StreamController<MagicAuthSession?>.broadcast();
      final gateCompleter = Completer<ReleaseGateStatus>();
      final container = ProviderContainer(
        overrides: [
          magicAuthStateProvider.overrideWith((ref) => authController.stream),
          releaseGateStatusProvider.overrideWith((ref) => gateCompleter.future),
          accessInvalidationProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );

      addTearDown(() async {
        container.dispose();
        await authController.close();
      });

      final router = container.read(routerProvider);

      authController.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(identical(container.read(routerProvider), router), isTrue);

      authController.add(
        const MagicAuthSession(
          accessToken: 'access-token-a',
          refreshToken: 'refresh-token-a',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(identical(container.read(routerProvider), router), isTrue);

      gateCompleter.complete(
        const ReleaseGateStatus(
          role: 'client',
          profileComplete: true,
          legalAccepted: true,
          deletionPending: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(identical(container.read(routerProvider), router), isTrue);
    },
  );
}
