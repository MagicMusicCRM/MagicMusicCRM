import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class _AdjustmentAdapter implements HttpClientAdapter {
  _AdjustmentAdapter(this.fixture);
  final Map<String, dynamic> fixture;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.method, 'POST');
    expect(options.uri.path, fixture['path']);
    expect(options.uri.queryParameters, isEmpty);
    final bytes = await requestStream!.fold<List<int>>(
      [],
      (all, next) => all..addAll(next),
    );
    expect(jsonDecode(utf8.decode(bytes)), fixture['body']);
    expect(options.headers['X-Request-Id'], isNotEmpty);
    if (!(fixture['path'] as String).endsWith('/preview')) {
      expect(options.headers['Idempotency-Key'], 'payment-adjustment-key');
      expect(options.headers['X-Request-Id'], 'payment-adjustment-request');
    }
    return ResponseBody.fromString(
      jsonEncode(fixture['response']),
      201,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final fixtures =
      jsonDecode(
            File(
              'contracts/payment-adjustments.fixtures.json',
            ).readAsStringSync(),
          )
          as List;
  for (final raw in fixtures) {
    final fixture = Map<String, dynamic>.from(raw as Map);
    test('payment adjustment wire: ${fixture['operationId']}', () async {
      final api = MagicApiClient(
        baseUrl: 'https://example.test/api',
        tokenStore: MemoryMagicTokenStore(),
        dio: Dio()..httpClientAdapter = _AdjustmentAdapter(fixture),
      );
      final service = MagicCrmService(api);
      final body = fixture['body'] as Map;
      final expected = fixture['response'] as Map;
      final parts = (fixture['path'] as String).split('/');
      const identity = MagicMutationIdentity(
        idempotencyKey: 'payment-adjustment-key',
        requestId: 'payment-adjustment-request',
      );
      switch (fixture['operationId']) {
        case 'previewPaymentCorrection':
          final result = await service.previewClientPaymentCorrection(
            parts[4],
            paymentRecordId: parts[6],
            input: PaymentCorrectionInput(
              expectedVersion: body['expectedVersion'] as int,
              amountMinor: BigInt.parse(body['amountMinor'] as String),
              status: ClientPaymentStatus.paid,
              dueAt: DateTime.parse(body['dueAt'] as String),
              method: SubscriptionPaymentMethod.cashless,
              externalIdentifier: body['externalIdentifier'] as String,
              occurredAt: DateTime.parse(body['occurredAt'] as String),
              branchId: body['branchId'] as String,
            ),
          );
          expect(result.paymentRecordId, expected['paymentRecordId']);
          expect(result.expectedVersion, expected['expectedVersion']);
          expect(
            result.before.amountMinor.toString(),
            expected['before']['amountMinor'],
          );
          expect(
            result.after.amountMinor.toString(),
            expected['after']['amountMinor'],
          );
          expect(result.after.branchId, expected['after']['branchId']);
          expect(result.before.verificationNote, isNull);
          expect(
            result.walletDeltaMinor.toString(),
            expected['walletDeltaMinor'],
          );
          expect(
            result.resultingBalanceMinor.toString(),
            expected['resultingBalanceMinor'],
          );
          expect(result.previewToken, expected['previewToken']);
          expect(
            result.expiresAt,
            DateTime.parse(expected['expiresAt'] as String),
          );
        case 'correctPayment':
          expect(
            await service.correctClientPayment(
              parts[4],
              paymentRecordId: parts[6],
              preview: PaymentCorrectionPreview.fromJson(
                Map<String, dynamic>.from(fixtures[0]['response'] as Map),
              ),
              reason: body['reason'] as String,
              identity: identity,
            ),
            expected,
          );
        case 'previewPaymentReversal':
          final result = await service.previewClientPaymentReversal(
            parts[4],
            paymentRecordId: parts[6],
            expectedVersion: 1,
          );
          expect(result.paymentRecordId, expected['paymentRecordId']);
          expect(result.amountMinor.toString(), expected['amountMinor']);
          expect(
            result.walletDeltaMinor.toString(),
            expected['walletDeltaMinor'],
          );
          expect(
            result.resultingBalanceMinor.toString(),
            expected['resultingBalanceMinor'],
          );
          expect(result.operation, expected['operation']);
          expect(result.previewToken, expected['previewToken']);
        case 'reversePayment':
          expect(
            await service.reverseClientPayment(
              parts[4],
              paymentRecordId: parts[6],
              preview: PaymentReversalPreview.fromJson(
                Map<String, dynamic>.from(fixtures[2]['response'] as Map),
              ),
              reason: body['reason'] as String,
              identity: identity,
            ),
            expected,
          );
      }
      api.rawDio.close();
    });
  }
}
