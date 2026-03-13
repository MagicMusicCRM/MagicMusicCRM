import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/github_updater_service.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdaterDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> updateInfo;

  const UpdaterDialog({super.key, required this.updateInfo});

  static bool _isCheckingOrShowing = false;

  /// Utility to show dialog and check for updates
  static Future<void> checkAndShow(BuildContext context, WidgetRef ref) async {
    if (_isCheckingOrShowing) return;
    _isCheckingOrShowing = true;

    debugPrint('GitHub Updater: Checking for updates...');
    try {
      final service = ref.read(githubUpdaterServiceProvider);
      final updateInfo = await service.checkForUpdates();
      
      if (updateInfo != null && context.mounted) {
        debugPrint('GitHub Updater: New version found: ${updateInfo['version']}. Showing dialog.');
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => UpdaterDialog(updateInfo: updateInfo),
        );
      } else {
        debugPrint('GitHub Updater: No update needed or context not mounted.');
      }
    } finally {
      _isCheckingOrShowing = false;
    }
  }

  @override
  ConsumerState<UpdaterDialog> createState() => _UpdaterDialogState();
}

class _UpdaterDialogState extends ConsumerState<UpdaterDialog> {
  bool _isDownloading = false;
  double _progress = 0;
  bool _hasError = false;

  Future<void> _startDownload() async {
    // Request storage storage permissions if needed
    if (await Permission.storage.request().isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission is required to download updates.')),
        );
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _hasError = false;
    });

    final service = ref.read(githubUpdaterServiceProvider);
    final success = await service.downloadAndInstallUpdate(
      widget.updateInfo['downloadUrl'],
      onProgress: (received, total) {
        if (total != -1) {
          setState(() {
            _progress = received / total;
          });
        }
      },
    );

    if (mounted) {
      if (success) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _isDownloading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Доступно обновление'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Новая версия ${widget.updateInfo['version']} доступна для скачивания.'),
          const SizedBox(height: 16),
          if (_isDownloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('${(_progress * 100).toStringAsFixed(1)}% загружено'),
          ],
          if (_hasError) ...[
            const SizedBox(height: 8),
            const Text(
              'Ошибка при загрузке или установке. Пожалуйста, попробуйте еще раз.',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Позже'),
          ),
        if (!_isDownloading)
          ElevatedButton(
            onPressed: _startDownload,
            child: const Text('Обновить сейчас'),
          ),
      ],
    );
  }
}
