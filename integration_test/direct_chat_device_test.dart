import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_bubble.dart';

import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('direct chat renders persisted text and media state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const _DirectChatEvidenceHome(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Преподаватель ↔ Управляющий'), findsOneWidget);
    expect(find.text('Исправленный текст'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('rules.pdf'), findsOneWidget);
    expect(find.text('00:01'), findsOneWidget);
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Переслано от: Преподаватель'), findsOneWidget);
    await captureEvidence(tester, 'direct-chat-media');

    debugPrint('V7_DIRECT_CHAT_DEVICE_PASS');
  });
}

class _DirectChatEvidenceHome extends StatelessWidget {
  const _DirectChatEvidenceHome();

  static const _createdAt = '2026-08-12T10:00:00.000Z';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Преподаватель ↔ Управляющий'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 24),
            child: Center(child: Text('прочитано')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: [
              MessageBubble(
                message: const {
                  'id': 'text-a',
                  'sender_id': 'teacher-a',
                  'content': 'Исправленный текст',
                  'message_type': 'text',
                  'created_at': _createdAt,
                  'is_edited': true,
                  'is_read': true,
                  'pinned_at': _createdAt,
                },
                isMe: false,
                senderName: 'Преподаватель',
                showSenderName: true,
                reactions: const [
                  {'emoji': '👍', 'count': 1, 'reactedByMe': true},
                ],
              ),
              MessageBubble(
                message: const {
                  'id': 'image-a',
                  'sender_id': 'teacher-a',
                  'content': 'Фото с занятия',
                  'message_type': 'image',
                  'attachment_name': 'photo.png',
                  'attachment_mime_type': 'application/octet-stream',
                  'created_at': _createdAt,
                  'is_read': true,
                },
                isMe: false,
              ),
              MessageBubble(
                message: const {
                  'id': 'file-a',
                  'sender_id': 'manager-a',
                  'content': 'Правила школы',
                  'message_type': 'file',
                  'attachment_name': 'rules.pdf',
                  'attachment_mime_type': 'application/pdf',
                  'attachment_size': 2048,
                  'created_at': _createdAt,
                  'is_read': true,
                },
                isMe: true,
              ),
              MessageBubble(
                message: const {
                  'id': 'voice-a',
                  'sender_id': 'teacher-a',
                  'content': 'Голосовое сообщение',
                  'message_type': 'voice',
                  'attachment_file_id': '11111111-1111-4111-8111-111111111111',
                  'voice_duration_ms': 1750,
                  'created_at': _createdAt,
                  'is_read': true,
                },
                isMe: false,
              ),
              MessageBubble(
                message: const {
                  'id': 'forward-a',
                  'sender_id': 'manager-a',
                  'content': 'Пересланный текст',
                  'message_type': 'text',
                  'forwarded_from_id': 'source-message-a',
                  'created_at': _createdAt,
                  'is_read': true,
                },
                isMe: true,
                forwardedFromName: 'Преподаватель',
              ),
              MessageBubble(
                message: const {
                  'id': 'deleted-a',
                  'sender_id': 'teacher-a',
                  'content': null,
                  'message_type': 'image',
                  'deleted_at': _createdAt,
                  'created_at': _createdAt,
                },
                isMe: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
