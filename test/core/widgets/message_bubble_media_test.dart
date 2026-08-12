import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_bubble.dart';

void main() {
  Widget harness(MessageBubble bubble) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: Center(child: bubble)),
      ),
    );
  }

  testWidgets('renders the voice duration restored from the server', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        MessageBubble(
          message: {
            'id': 'voice-a',
            'message_type': 'voice',
            'attachment_file_id': 'file-a',
            'voice_duration_ms': 1500,
            'created_at': '2026-08-12T10:00:00.000Z',
          },
          isMe: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('00:01'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('does not offer forwarding when the media caller disables it', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        MessageBubble(
          message: {
            'id': 'image-a',
            'message_type': 'image',
            'attachment_file_id': 'file-a',
            'attachment_name': 'photo.png',
            'attachment_mime_type': 'image/png',
            'content': 'Фото',
            'created_at': '2026-08-12T10:00:00.000Z',
          },
          isMe: true,
          onForward: null,
        ),
      ),
    );

    await tester.longPress(find.text('Фото'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Действия с сообщением'), findsOneWidget);
    expect(find.text('Переслать'), findsNothing);
  });
}
