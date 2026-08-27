import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _telegramPath = 'lib/core/widgets/telegram';

void main() {
  test('chat info dialog keeps independent bounded owners', () {
    final shell = File('$_telegramPath/chat_info_dialog.dart');
    final source = shell.readAsStringSync();

    expect(_nloc(shell), lessThanOrEqualTo(260));
    expect(
      RegExp(r'^import ', multiLine: true).allMatches(source).length,
      lessThanOrEqualTo(12),
    );

    for (final name in const [
      'chat_info_models.dart',
      'chat_info_controller.dart',
      'chat_info_view.dart',
      'chat_info_tabs.dart',
      'chat_info_member_dialogs.dart',
    ]) {
      final owner = File('$_telegramPath/$name');
      expect(owner.existsSync(), isTrue, reason: '$name must exist');
      expect(
        _nloc(owner),
        lessThanOrEqualTo(500),
        reason: '$name must remain independently maintainable',
      );
    }

    expect(
      File('$_telegramPath/chat_info_dialog_views.dart').existsSync(),
      isFalse,
    );
    expect(
      File('$_telegramPath/chat_info_dialog_dialogs.dart').existsSync(),
      isFalse,
    );

    for (final forbidden in const [
      'part ',
      'part of',
      '_ChatInfoViews',
      '_AddMembersDialogState',
      'listMessages',
      'listChannelPosts',
      'listProfileNotes',
      'createProfileNote',
      'updateGroupMembers',
    ]) {
      expect(
        source,
        isNot(contains(forbidden)),
        reason: 'forbidden: $forbidden',
      );
    }
  });
}

int _nloc(File file) => file
    .readAsLinesSync()
    .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('//'))
    .length;
