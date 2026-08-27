import 'package:flutter_test/flutter_test.dart';

import '../../../../support/architecture/dart_architecture_guard.dart';

const _shellFilename = 'schedule_reference_settings.dart';
const _providerNames = {'magicCrmServiceProvider'};

void main() {
  test('cast and await wrappers preserve provider receiver ownership', () {
    final inspection = inspectDartSource(_shellFilename, r'''
void castReceiver(dynamic ref) {
  (ref.read(magicCrmServiceProvider) as dynamic).futureCastWrite();
}
Future<void> awaitedReceiver(dynamic ref) async {
  final p = magicCrmServiceProvider;
  final read = ref.read;
  final crm = await read(p);
  crm.futureAwaitWrite();
}
''');

    expect(inspection.invocationsOnProviderDerivedReceivers(_providerNames), {
      'futureCastWrite',
      'futureAwaitWrite',
    });
  });

  test('cast and await wrappers keep local receivers clean', () {
    final inspection = inspectDartSource(_shellFilename, r'''
void castLocal() {
  final crm = LocalSchedulePreview() as dynamic;
  crm.refreshCastPreview();
}
Future<void> awaitLocal(dynamic localFuture) async {
  final crm = await localFuture;
  crm.refreshAwaitPreview();
}
''');

    expect(
      inspection.invocationsOnProviderDerivedReceivers(_providerNames),
      isEmpty,
    );
  });
}
