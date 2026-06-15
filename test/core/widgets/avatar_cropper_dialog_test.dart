import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:magic_music_crm/core/widgets/avatar_cropper_dialog.dart';

void main() {
  test('compressAvatarBytes resizes large images for profile upload', () {
    final source = img.Image(width: 1800, height: 1200);
    img.fill(source, color: img.ColorRgb8(197, 160, 89));
    final pngBytes = Uint8List.fromList(img.encodePng(source));

    final compressed = AvatarCropperDialog.compressAvatarBytes(pngBytes);
    final decoded = img.decodeImage(compressed);

    expect(decoded, isNotNull);
    expect(decoded!.width <= AvatarCropperDialog.maxAvatarEdge, isTrue);
    expect(decoded.height <= AvatarCropperDialog.maxAvatarEdge, isTrue);
    expect(compressed.length < pngBytes.length, isTrue);
    expect(compressed.length <= AvatarCropperDialog.targetOutputBytes, isTrue);
  });
}
