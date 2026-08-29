import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';

List<int> minimalXlsxBytes({bool includeWorksheet = true}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        '[Content_Types].xml',
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '</Types>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        '_rels/.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            '</Relationships>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'xl/workbook.xml',
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
            '</workbook>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'xl/_rels/workbook.xml.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            '</Relationships>',
      ),
    );
  if (includeWorksheet) {
    archive.addFile(
      ArchiveFile.string(
        'xl/worksheets/sheet1.xml',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<sheetData/>'
            '</worksheet>',
      ),
    );
  }
  return ZipEncoder().encode(archive);
}

void main() {
  test('accepts a complete minimal XLSX workbook package', () {
    final bytes = minimalXlsxBytes();

    expect(() => validateReportExportBytes(bytes, 'xlsx'), returnsNormally);
  });

  test('rejects a truncated XLSX ZIP payload', () {
    expect(
      () => validateReportExportBytes(const [0x50, 0x4b, 0x03, 0x04], 'xlsx'),
      throwsFormatException,
    );
  });

  test('rejects a ZIP payload without an XLSX worksheet', () {
    expect(
      () => validateReportExportBytes(
        minimalXlsxBytes(includeWorksheet: false),
        'xlsx',
      ),
      throwsFormatException,
    );
  });

  test('rejects an XLSX ZIP payload with a corrupted entry checksum', () {
    final bytes = minimalXlsxBytes();
    expect(bytes.take(4), orderedEquals([0x50, 0x4b, 0x03, 0x04]));
    bytes[14] ^= 0xff;

    expect(
      () => validateReportExportBytes(bytes, 'xlsx'),
      throwsFormatException,
    );
  });
}
