import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/telegram/send_file_dialog.dart';

void main() {
  testWidgets('does not autofocus caption and remains visible above keyboard', (
    tester,
  ) async {
    await _pumpHarness(
      tester,
      onSend: (_) async {},
      media: const MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 24),
        viewInsets: EdgeInsets.only(bottom: 320),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SendFileDialog), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('waits for upload before closing', (tester) async {
    final completer = Completer<void>();
    await _pumpHarness(tester, onSend: (_) => completer.future);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.byType(SendFileDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SendFileDialog), findsNothing);
  });

  testWidgets('keeps dialog open and surfaces upload failure', (tester) async {
    await _pumpHarness(
      tester,
      onSend: (_) async => throw StateError('upload failed'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byType(SendFileDialog), findsOneWidget);
    expect(find.text('Не удалось отправить файл.'), findsOneWidget);
  });
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required Future<void> Function(String caption) onSend,
  MediaQueryData media = const MediaQueryData(size: Size(390, 844)),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(data: media, child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SendFileDialog(
                fileName: 'document.pdf',
                fileSize: 8,
                onSend: onSend,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}
