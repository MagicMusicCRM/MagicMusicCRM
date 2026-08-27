import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'content is service-free and dialog keeps text and navigation ownership',
    () {
      final content = File(
        'lib/features/admin/presentation/widgets/'
        'reference_catalog_lifecycle_content.dart',
      ).readAsStringSync();
      final dialog = File(
        'lib/features/admin/presentation/widgets/'
        'reference_catalog_lifecycle_dialog.dart',
      ).readAsStringSync();
      final controller = File(
        'lib/features/admin/presentation/widgets/'
        'reference_catalog_lifecycle_controller.dart',
      ).readAsStringSync();
      final state = File(
        'lib/features/admin/presentation/widgets/'
        'reference_catalog_lifecycle_state.dart',
      ).readAsStringSync();

      expect(content, isNot(contains('flutter_riverpod')));
      expect(content, isNot(contains('/services/')));
      expect(content, isNot(contains('/api/')));
      expect(
        content,
        isNot(contains('reference_catalog_lifecycle_controller.dart')),
      );
      expect(content, contains('reference_catalog_lifecycle_state.dart'));
      expect(
        controller,
        isNot(contains('reference_catalog_lifecycle_content.dart')),
      );
      expect(controller, contains('reference_catalog_lifecycle_state.dart'));
      expect(state, isNot(contains('package:flutter')));
      expect(state, isNot(contains('/services/')));
      expect(state, isNot(contains('/api/')));
      expect(dialog, contains('TextEditingController'));
      expect(dialog, contains('Navigator.pop'));
      expect(dialog, contains('magicCrmServiceProvider'));
      expect(dialog, isNot(contains('renameReferenceCatalogItem')));
      expect(dialog, isNot(contains('archiveReferenceCatalogItem')));
      expect(dialog, isNot(contains('restoreReferenceCatalogItem')));
    },
  );
}
