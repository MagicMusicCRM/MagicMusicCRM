import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_image/crop_image.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

class AvatarCropperDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const AvatarCropperDialog({super.key, required this.imageBytes});

  static const int maxInputBytes = 25 * 1024 * 1024;
  static const int maxAvatarEdge = 512;
  static const int targetOutputBytes = 900 * 1024;

  static Uint8List compressAvatarBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final largestEdge = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final normalized = largestEdge > maxAvatarEdge
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxAvatarEdge : null,
            height: decoded.height > decoded.width ? maxAvatarEdge : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    for (final quality in const [88, 82, 76, 70]) {
      final encoded = Uint8List.fromList(
        img.encodeJpg(normalized, quality: quality),
      );
      if (encoded.length <= targetOutputBytes || quality == 70) {
        return encoded;
      }
    }

    return Uint8List.fromList(img.encodeJpg(normalized, quality: 70));
  }

  /// Opens file picker, crops and returns compressed avatar bytes.
  static Future<Uint8List?> pickAndCropAvatar(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    if (file.bytes == null) return null;

    if (file.size > maxInputBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Файл слишком большой. Максимальный размер - 25 МБ.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    final imageBytes = file.bytes!;

    if (!context.mounted) return null;

    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AvatarCropperDialog(imageBytes: imageBytes),
    );
  }

  @override
  State<AvatarCropperDialog> createState() => _AvatarCropperDialogState();
}

class _AvatarCropperDialogState extends State<AvatarCropperDialog> {
  late CropController _controller;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = CropController(
      aspectRatio: 1,
      defaultCrop: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _crop() async {
    setState(() => _isProcessing = true);
    try {
      final ui.Image bitmap = await _controller.croppedBitmap();
      final ByteData? data = await bitmap.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data != null) {
        final compressed = AvatarCropperDialog.compressAvatarBytes(
          data.buffer.asUint8List(),
        );
        if (mounted) Navigator.pop(context, compressed);
      } else {
        if (mounted) Navigator.pop(context, null);
      }
    } catch (e) {
      debugPrint('Crop error: $e');
      if (mounted) Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Обрезать фото', textAlign: TextAlign.center),
      content: SizedBox(
        width: 400,
        height: 400,
        child: CropImage(
          controller: _controller,
          image: Image.memory(widget.imageBytes),
          paddingSize: 25.0,
          alwaysMove: true,
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context, null),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _crop,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
