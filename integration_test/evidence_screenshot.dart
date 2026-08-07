import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const evidenceRootKey = Key('evidence-screenshot-root');

Future<void> captureEvidence(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(evidenceRootKey),
  );
  final image = await boundary.toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List();
  final configured = Platform.environment['EVIDENCE_SCREENSHOT_DIR'];
  final directory = Directory(
    configured?.isNotEmpty == true
        ? configured!
        : '${Directory.systemTemp.path}${Platform.pathSeparator}magic-evidence',
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$name.png');
  await file.writeAsBytes(bytes, flush: true);
  // Stable marker for adb/CI collection.
  // ignore: avoid_print
  print('EVIDENCE_SCREENSHOT ${file.path}');
}
