import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/main.dart' show warmApiConnection;

void main() {
  test('API warmup failure never blocks application startup', () async {
    var attempted = false;

    await expectLater(
      warmApiConnection(() async {
        attempted = true;
        throw Exception('backend unavailable');
      }),
      completes,
    );
    expect(attempted, isTrue);
  });
}
