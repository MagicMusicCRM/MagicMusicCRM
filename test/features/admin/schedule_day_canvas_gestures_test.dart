import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';

/// Pointer handling on the day grid.
///
/// Two owner-reported faults, both about the grid acting on a gesture the user
/// did not make:
///   1. Scrolling the day with a precision touchpad drew a new booking instead
///      of scrolling. Flutter reports two-finger scrolling as a pan-zoom
///      sequence, and the column's pan recognizer — deeper than the scroll view
///      — won the arena and took it for a drag-select.
///   2. On touch there was no way to reach a resize handle without risking an
///      open, and no way to open without risking a resize.

final _day = DateTime(2026, 7, 9);

ScheduleEntry _entry({String id = 'l1', bool movable = true}) {
  return ScheduleEntry(
    lesson: {'id': id},
    id: id,
    columnId: 'room-1',
    startLocal: DateTime(2026, 7, 9, 12),
    durationMinutes: 60,
    title: 'Степан Белоусов',
    subtitle: 'Антон Кондрашов',
    isTrial: false,
    conflicts: const [],
    movable: movable,
    highlighted: false,
  );
}

class _Recorder {
  final List<String> created = [];
  final List<String> opened = [];
}

Widget _host({
  required TargetPlatform platform,
  required _Recorder rec,
  List<ScheduleEntry> entries = const [],
}) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: Scaffold(
      body: ScheduleDayCanvas(
        date: _day,
        columns: const [
          ScheduleColumn(id: 'room-1', name: 'Кабинет 1', color: Colors.blue),
        ],
        entries: entries,
        onCreateSlot: (col, start, dur) => rec.created.add('$col@$start+$dur'),
        onMove: (_, _, _) {},
        onResize: (_, _, _) {},
        onOpenLesson: (l) => rec.opened.add(l['id'].toString()),
      ),
    ),
  );
}

/// The grid's vertical body scroll — the one with something to scroll.
ScrollPosition _verticalBody(WidgetTester tester) {
  final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
  return states
      .map((s) => s.position)
      .firstWhere(
        (p) => p.axis == Axis.vertical && p.maxScrollExtent > 0,
      );
}

void main() {
  testWidgets('a trackpad two-finger scroll scrolls, it does not book a slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rec = _Recorder();
    await tester.pumpWidget(
      _host(platform: TargetPlatform.windows, rec: rec),
    );
    await tester.pumpAndSettle();

    final before = _verticalBody(tester).pixels;
    final centre = tester.getCenter(find.byType(ScheduleDayCanvas));

    // Exactly what a precision touchpad emits: a pan-zoom sequence, not a drag.
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(centre));
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(centre, pan: Offset(0, -20.0 * i)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();

    expect(
      rec.created,
      isEmpty,
      reason: 'two-finger scrolling must never open a create dialog',
    );
    expect(
      _verticalBody(tester).pixels,
      greaterThan(before),
      reason: 'the gesture must reach the scroll view instead of being '
          'swallowed by the column pan recognizer',
    );
  });

  testWidgets('on touch a single tap selects and a double tap opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rec = _Recorder();
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.android,
        rec: rec,
        entries: [_entry()],
      ),
    );
    await tester.pumpAndSettle();

    final card = find.text('Степан Белоусов');

    // One tap picks the card — it must NOT open it. Selecting is what reveals
    // the resize handles, so a tap that opened would make resize unreachable.
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(rec.opened, isEmpty);

    // Two taps open it.
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(rec.opened, ['l1']);
  });

  testWidgets('a bare drag across empty grid books nothing', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rec = _Recorder();
    await tester.pumpWidget(
      _host(platform: TargetPlatform.windows, rec: rec),
    );
    await tester.pumpAndSettle();

    final centre = tester.getCenter(find.byType(ScheduleDayCanvas));
    final g = await tester.startGesture(centre, kind: PointerDeviceKind.mouse);
    // Moving straight away — no hold. Whatever produced this (a flick, a
    // touchpad), it is not someone asking for a booking.
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(rec.created, isEmpty);
  });

  testWidgets('holding first, then dragging, books the picked range', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rec = _Recorder();
    await tester.pumpWidget(
      _host(platform: TargetPlatform.windows, rec: rec),
    );
    await tester.pumpAndSettle();

    final centre = tester.getCenter(find.byType(ScheduleDayCanvas));
    final g = await tester.startGesture(centre, kind: PointerDeviceKind.mouse);
    // Sit still past the long-press threshold — the deliberate part.
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(
      rec.created,
      isNotEmpty,
      reason: 'picking a range on purpose must still work, just one beat later',
    );
  });

  testWidgets('on desktop a click opens the lesson straight away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rec = _Recorder();
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.windows,
        rec: rec,
        entries: [_entry()],
      ),
    );
    await tester.pumpAndSettle();

    // Hover already exposes the handles on a mouse, so there is nothing to
    // select and no reason to charge the user a second click.
    await tester.tap(find.text('Степан Белоусов'));
    await tester.pumpAndSettle();
    expect(rec.opened, ['l1']);
  });
}
