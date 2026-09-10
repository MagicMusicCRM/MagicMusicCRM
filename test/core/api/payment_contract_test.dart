import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class _PaymentAdapter implements HttpClientAdapter {
  _PaymentAdapter(this.fixture);
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
    expect(options.headers['Idempotency-Key'], 'payment-contract-key');
    expect(options.headers['X-Request-Id'], 'payment-contract-request');
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
      jsonDecode(File('contracts/payments.fixtures.json').readAsStringSync())
          as List;
  for (final (i, raw) in fixtures.indexed) {
    final fixture = Map<String, dynamic>.from(raw as Map);
    test(
      'payment wire fixture $i preserves minor units, version and command identity',
      () async {
        final api = MagicApiClient(
          baseUrl: 'https://example.test/api',
          tokenStore: MemoryMagicTokenStore(),
          dio: Dio()..httpClientAdapter = _PaymentAdapter(fixture),
        );
        final service = MagicCrmService(api);
        final body = fixture['body'] as Map;
        final parts = (fixture['path'] as String).split('/');
        const identity = MagicMutationIdentity(
          idempotencyKey: 'payment-contract-key',
          requestId: 'payment-contract-request',
        );
        final result = i == 0
            ? await service.createClientPaymentRecord(
                parts[4],
                input: CreateClientPaymentRecordInput(
                  amountMinor: BigInt.parse(body['amountMinor'] as String),
                  currencyCode: body['currencyCode'] as String,
                  status: ClientPaymentStatus.unpaid,
                  dueAt: DateTime.parse(body['dueAt'] as String),
                  reason: body['reason'] as String,
                ),
                identity: identity,
              )
            : await service.transitionClientPaymentRecord(
                parts[4],
                paymentRecordId: parts[6],
                input: TransitionClientPaymentRecordInput(
                  expectedVersion: body['expectedVersion'] as int,
                  targetStatus: ClientPaymentStatus.values.firstWhere(
                    (s) => s.apiValue == body['targetStatus'],
                  ),
                  method: body['method'] == null
                      ? null
                      : SubscriptionPaymentMethod.cashless,
                  externalIdentifier: body['externalIdentifier'] as String?,
                  occurredAt: body['occurredAt'] == null
                      ? null
                      : DateTime.parse(body['occurredAt'] as String),
                  reason: body['reason'] as String,
                ),
                identity: identity,
              );
        expect(result, fixture['response']);
        api.rawDio.close();
      },
    );
  }
}
