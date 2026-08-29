import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      for (final file in archive.files.where((file) => file.isFile)) {
        final content = file.readBytes();
        if (content == null ||
            content.length != file.size ||
            (file.crc32 != null && getCrc32(content) != file.crc32)) {
          throw const FormatException(
            'Сервер вернул повреждённый файл отчёта.',
          );
        }
      }

      final contentTypes = archive.findFile('[Content_Types].xml');
      final packageRelationships = archive.findFile('_rels/.rels');
      final workbook = archive.findFile('xl/workbook.xml');
      final workbookRelationships = archive.findFile(
        'xl/_rels/workbook.xml.rels',
      );
      final worksheet = archive.files.where((file) {
        return file.isFile &&
            file.name.startsWith('xl/worksheets/') &&
            file.name.endsWith('.xml');
      }).firstOrNull;
      if (contentTypes == null ||
          packageRelationships == null ||
          workbook == null ||
          workbookRelationships == null ||
          worksheet == null ||
          !utf8.decode(contentTypes.content).contains('/xl/workbook.xml') ||
          !utf8
              .decode(packageRelationships.content)
              .contains('officeDocument') ||
          !utf8.decode(workbook.content).contains('<sheets') ||
          !utf8.decode(workbookRelationships.content).contains('worksheet') ||
          !utf8.decode(worksheet.content).contains('<sheetData')) {
        throw const FormatException('Сервер вернул повреждённый файл отчёта.');
      }
    } on FormatException {
      rethrow;
    } catch (_) {
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
