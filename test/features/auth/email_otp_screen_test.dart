import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/email_otp_screen.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

void main() {
  testWidgets('password OTP stays fail-closed when no session is returned', (
    tester,
  ) async {
    final adapter = _OtpWithoutSessionAdapter();
    final service = MagicAuthService(_client(adapter, MemoryMagicTokenStore()));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicAuthServiceProvider.overrideWithValue(service)],
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(0.8)),
          child: MaterialApp(
            home: EmailOtpScreen(
              data: EmailOtpRouteData(
                email: 'system-admin@example.com',
                purpose: EmailOtpPurpose.passwordMfa,
              ),
            ),
          ),
        ),
      ),
    );

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(emailOtpCodeLength));
    for (var index = 0; index < emailOtpCodeLength; index++) {
      await tester.enterText(fields.at(index), '${index + 1}');
    }
    expect(
      List.generate(
        emailOtpCodeLength,
        (index) => tester.widget<TextField>(fields.at(index)).controller?.text,
      ),
      ['1', '2', '3', '4', '5', '6'],
    );
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();

    expect(adapter.verifyRequests, 1);
    expect(
      find.text('Не удалось завершить вход. Запросите новый код.'),
      findsOneWidget,
    );
    expect(await service.currentSession(), isNull);
  });
}

MagicApiClient _client(HttpClientAdapter adapter, MemoryMagicTokenStore store) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.example.test',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return MagicApiClient(
    baseUrl: 'https://api.example.test',
    tokenStore: store,
    dio: dio,
  );
}

class _OtpWithoutSessionAdapter implements HttpClientAdapter {
  int verifyRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.uri.path, '/auth/otp/verify');
    verifyRequests++;
    return ResponseBody.fromString(
      jsonEncode({
        'user': {
          'id': 'system-admin-a',
          'email': 'system-admin@example.com',
          'role': 'system_admin',
          'emailVerified': true,
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
