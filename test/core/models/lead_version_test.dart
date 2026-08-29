import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/lead.dart';

void main() {
  test('Lead exposes the server optimistic concurrency version', () {
    expect(Lead.fromMap(const {'version': 7}).version, 7);
  });
}
