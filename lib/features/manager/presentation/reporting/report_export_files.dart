import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

typedef ReportFileOpener =
    Future<ReportFileOpenResult> Function(List<int> bytes, String filename);

@immutable
class ReportFileOpenResult {
  const ReportFileOpenResult({required this.path, required this.opened});

  final String path;
  final bool opened;
}

void validateReportExportBytes(List<int> bytes, String format) {
  if (format == 'xlsx') {
    final isZip =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (!isZip) {
      throw const FormatException('Сервер вернул повреждённый файл отчёта.');
    }
    return;
  }
  if (format == 'csv') {
    final hasUtf8Bom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    if (!hasUtf8Bom) {
      throw const FormatException(
        'Не удалось подготовить таблицу в выбранном формате.',
      );
    }
    utf8.decode(bytes.sublist(3));
    return;
  }
  throw FormatException('Неподдерживаемый формат экспорта: $format');
}

final reportFileOpenerProvider = Provider<ReportFileOpener>((ref) {
  return (bytes, filename) async {
    Directory directory;
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      directory = downloads;
    } else if (Platform.isAndroid) {
      directory =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    } else {
      directory = await getTemporaryDirectory();
    }
    await directory.create(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}$filename';
    await File(path).writeAsBytes(bytes, flush: true);
    final opened = await OpenFilex.open(path);
    return ReportFileOpenResult(
      path: path,
      opened: opened.type == ResultType.done,
    );
  };
});
