import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import '../../support/minimal_xlsx_fixture.dart';

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
