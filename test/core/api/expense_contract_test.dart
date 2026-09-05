import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class _ContractAdapter implements HttpClientAdapter {
  _ContractAdapter(this.fixture);
  final Map<String, dynamic> fixture;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    expect(options.method, fixture['method']);
    expect(options.uri.path, fixture['path']);
    expect(options.uri.queryParameters, <String, String>{
      for (final entry in (fixture['query'] as Map? ?? {}).entries)
        entry.key as String: entry.value.toString(),
    });
    if (fixture['body'] != null) {
      final bytes = await requestStream!.fold<List<int>>(
        [],
        (all, bytes) => all..addAll(bytes),
      );
      expect(jsonDecode(utf8.decode(bytes)), fixture['body']);
    }
    expect(options.headers['X-Request-Id'], isNotEmpty);
    if (options.method != 'GET') {
      expect(
        options.headers['Idempotency-Key'],
        matches(RegExp(r'^[A-Za-z0-9._:-]{8,160}$')),
      );
    }
    return ResponseBody.fromString(
      jsonEncode(fixture['response']),
      fixture['status'] as int,
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
      jsonDecode(File('contracts/expenses.fixtures.json').readAsStringSync())
          as List;
  for (final (index, raw) in fixtures.indexed) {
    final fixture = Map<String, dynamic>.from(raw as Map);
    test(
      'expense wire fixture $index: ${fixture['method']} ${fixture['path']}',
      () async {
        final adapter = _ContractAdapter(fixture);
        final api = MagicApiClient(
          baseUrl: 'https://example.test/api',
          tokenStore: MemoryMagicTokenStore(),
          dio: Dio()..httpClientAdapter = adapter,
        );
        final service = MagicCrmService(api);
        final body = fixture['body'] as Map? ?? {};
        final query = fixture['query'] as Map? ?? {};
        const identity = MagicMutationIdentity(
          idempotencyKey: 'expense-contract-command',
          requestId: 'expense-contract-request',
        );
        late Map<String, dynamic> result;
        switch (fixture['method']) {
          case 'POST':
            result = await service.createExpense(
              amount: body['amount'] as num,
              category: body['category'] as String,
              description: body['description'] as String?,
              occurredAt: body['occurredAt'] as String?,
              identity: identity,
            );
          case 'PATCH':
            result = await service.updateExpense(
              expenseId: (fixture['path'] as String).split('/').last,
              expectedVersion: body['expectedVersion'] as int,
              amount: body['amount'] as num,
              category: body['category'] as String,
              description: body['description'] as String?,
              identity: identity,
            );
          case 'DELETE':
            result = await service.deleteExpense(
              (fixture['path'] as String).split('/').last,
              expectedVersion: query['expectedVersion'] as int,
            );
          default:
            result = await service.listExpenses(
              category: query['category'] as String?,
              from: query['from'] as String?,
              to: query['to'] as String?,
              limit: query['limit'] as int?,
            );
        }
        expect(result, fixture['response']);
        if (fixture['method'] == 'POST' || fixture['method'] == 'PATCH') {
          expect(
            adapter.request!.headers['Idempotency-Key'],
            identity.idempotencyKey,
          );
          expect(adapter.request!.headers['X-Request-Id'], identity.requestId);
        }
        api.rawDio.close();
      },
    );
  }
}
