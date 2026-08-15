import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/update/update_check_gate.dart';

void main() {
  test('prevents parallel and overly frequent update checks', () async {
    final gate = WindowsUpdateCheckGate(
      minimumInterval: const Duration(minutes: 5),
    );
    final release = Completer<void>();
    var calls = 0;
    final start = DateTime.utc(2026, 8, 15, 10);

    final first = gate.run(() async {
      calls++;
      await release.future;
    }, now: start);
    final parallel = await gate.run(() async {
      calls++;
    }, now: start.add(const Duration(seconds: 1)));

    expect(parallel, isFalse);
    expect(calls, 1);

    release.complete();
    expect(await first, isTrue);

    final tooSoon = await gate.run(() async {
      calls++;
    }, now: start.add(const Duration(minutes: 4)));
    final afterInterval = await gate.run(() async {
      calls++;
    }, now: start.add(const Duration(minutes: 5)));

    expect(tooSoon, isFalse);
    expect(afterInterval, isTrue);
    expect(calls, 2);
  });

  test('forced startup check bypasses the time gate', () async {
    final gate = WindowsUpdateCheckGate();
    final now = DateTime.utc(2026, 8, 15, 10);
    var calls = 0;

    await gate.run(() async {
      calls++;
    }, now: now);
    final forced = await gate.run(
      () async {
        calls++;
      },
      now: now.add(const Duration(seconds: 1)),
      force: true,
    );

    expect(forced, isTrue);
    expect(calls, 2);
  });
}
