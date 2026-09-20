import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/evidence_screenshot.dart' show evidenceRootKey;
export '../../integration_test/evidence_screenshot.dart' show evidenceRootKey;

Future<void> loadModalFonts() async {
  // Replace the test-only Ahem fallback so unstyled controls remain readable.
  final cache = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final roboto = File(
    '${cache.path}/artifacts/material_fonts/roboto-regular.ttf',
  );
  if (await roboto.exists()) {
    await (FontLoader(
      'Ahem',
    )..addFont(roboto.readAsBytes().then(ByteData.sublistView))).load();
  }
  for (final (family, path) in [
    ('Inter', 'assets/fonts/InterVariable.ttf'),
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(path))).load();
  }
}

Future<void> captureModalLayout(WidgetTester tester, String name) async {
  if (Platform.environment['EVIDENCE_SCREENSHOT_DIR'] == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(evidenceRootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      Platform.environment['EVIDENCE_SCREENSHOT_DIR']!,
    );
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
