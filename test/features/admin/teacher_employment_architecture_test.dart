import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  const root = 'lib/features/admin/presentation/widgets';

  test('teacher employment fields depend only on their clean gateway', () {
    final fields = _source('$root/teacher_employment_fields.dart');

    expect(
      fields,
      contains("import 'teacher_employment_reference_gateway.dart';"),
    );
    expect(fields, contains('required this.gateway'));
    expect(fields, isNot(contains('flutter_riverpod')));
    expect(fields, isNot(contains('MagicCrmService')));
    expect(fields, isNot(contains('MagicSettingsService')));
    expect(fields, isNot(contains('magicCrmServiceProvider')));
    expect(fields, isNot(contains('magicSettingsServiceProvider')));
    expect(fields, isNot(contains('ref.read')));
  });

  test('gateway is pure and service adapter owns infrastructure mapping', () {
    final gatewayFile = File('$root/teacher_employment_reference_gateway.dart');
    final adapterFile = File(
      '$root/magic_teacher_employment_reference_gateway.dart',
    );

    expect(gatewayFile.existsSync(), isTrue);
    expect(adapterFile.existsSync(), isTrue);
    if (!gatewayFile.existsSync() || !adapterFile.existsSync()) return;

    final gateway = gatewayFile.readAsStringSync();
    final adapter = adapterFile.readAsStringSync();
    expect(
      gateway,
      contains('abstract interface class TeacherEmploymentReferenceGateway'),
    );
    expect(gateway, isNot(contains('flutter_riverpod')));
    expect(gateway, isNot(contains('MagicCrmService')));
    expect(gateway, isNot(contains('MagicSettingsService')));
    expect(adapter, contains('implements TeacherEmploymentReferenceGateway'));
    expect(adapter, contains('CrmCustomFieldDefinition'));
  });

  test('create and detail composition roots pass stable gateways', () {
    final create = _source('$root/create_teacher_dialog.dart');
    final detail = _source('$root/teacher_detail_dialog.dart');
    final content = _source('$root/teacher_detail_content.dart');

    expect(create, contains('late final TeacherEmploymentReferenceGateway'));
    expect(create, contains('gateway: _employmentReferenceGateway'));
    expect(detail, contains('late final TeacherEmploymentReferenceGateway'));
    expect(
      detail,
      contains('employmentReferenceGateway: _employmentReferenceGateway'),
    );
    expect(content, contains('required this.employmentReferenceGateway'));
    expect(content, contains('gateway: employmentReferenceGateway'));
  });
}
