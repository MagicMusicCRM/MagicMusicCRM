import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_image/crop_image.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:ui' as ui;

class AvatarCropperDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const AvatarCropperDialog({super.key, required this.imageBytes});

  /// Opens file picker, checks size (1MB max), crops and returns cropped bytes.
  static Future<Uint8List?> pickAndCropAvatar(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    if (file.bytes == null) return null;

    if (file.size > 1024 * 1024) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Файл слишком большой. Максимальный размер - 1 МБ.'),
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
      final ByteData? data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) {
        if (mounted) Navigator.pop(context, data.buffer.asUint8List());
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
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Сохранить'),
        ),
      ],
    );
  }
}
