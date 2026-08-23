import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/compat/messenger_legacy_map_adapter.dart';
import 'package:magic_music_crm/core/compat/profile_admin_legacy_map_adapter.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';

void main() {
  const messenger = DefaultMessengerLegacyMapAdapter();
  const profile = DefaultProfileAdminLegacyMapAdapter();

  test('messenger adapter preserves chat, message, and member map shapes', () {
    final restChat = <String, dynamic>{
      'id': 'chat-1',
      'type': 'administration',
      'title': 'Оператор',
      'partnerId': 'user-1',
      'partner': <String, dynamic>{
        'id': 'user-1',
        'firstName': 'Анна',
        'lastName': 'Иванова',
        'email': 'anna@example.com',
        'avatarFileId': 'avatar-1',
        'role': 'manager',
      },
      'lastMessageId': 'message-1',
      'lastMessageContent': 'Привет',
      'lastMessageCreatedAt': '2026-08-22T10:00:00.000Z',
      'unreadCount': 2,
      'isMuted': false,
      'createdAt': '2026-08-20T10:00:00.000Z',
      'updatedAt': '2026-08-22T10:00:00.000Z',
      'slug': 'administration',
      'isSystem': true,
      'folder': 'students',
      'assignedTo': <String, dynamic>{'id': 'manager-1'},
      'archived': false,
      'ownerName': 'Мария',
      'branchId': 'branch-1',
      'branchName': 'Центральный',
    };
    expect(messenger.chat(restChat), <String, dynamic>{
      'id': 'chat-1',
      'type': 'direct',
      'raw_type': 'administration',
      'title': 'Администрация',
      'created_by': null,
      'last_message_id': 'message-1',
      'partner_id': 'user-1',
      'partner': restChat['partner'],
      'last_message_content': 'Привет',
      'last_message_created_at': '2026-08-22T10:00:00.000Z',
      'unread_count': 2,
      'is_muted': false,
      'created_at': '2026-08-20T10:00:00.000Z',
      'updated_at': '2026-08-22T10:00:00.000Z',
      'slug': 'administration',
      'is_system': true,
      '_item_type': 'direct',
      '_partner_id': 'user-1',
      '_partner_data': <String, dynamic>{
        'id': 'user-1',
        'email': 'anna@example.com',
        'first_name': 'Анна',
        'last_name': 'Иванова',
        'avatar_file_id': 'avatar-1',
      },
      '_avatar_url': 'avatar-1',
      '_display_name': 'Администрация',
      '_last_message': <String, dynamic>{
        'id': 'message-1',
        'content': 'Привет',
        'created_at': '2026-08-22T10:00:00.000Z',
      },
      '_last_message_time': '2026-08-22T10:00:00.000Z',
      'folder': 'students',
      'assigned_to': <String, dynamic>{'id': 'manager-1'},
      'archived': false,
      'owner_name': 'Мария',
      'branch_id': 'branch-1',
      'branch_name': 'Центральный',
    });

    expect(
      messenger.message(<String, dynamic>{
        'id': 'message-1',
        'chatId': 'chat-1',
        'senderId': 'user-1',
        'content': 'Файл',
        'messageType': 'file',
        'attachment': <String, dynamic>{
          'originalFileName': 'lesson.pdf',
          'sizeBytes': 42,
          'contentType': 'application/pdf',
          'durationMs': 123,
        },
        'read': true,
        'reactions': <Map<String, dynamic>>[
          <String, dynamic>{'emoji': '👍', 'count': 1},
        ],
        'sender': <String, dynamic>{
          'id': 'user-1',
          'email': 'anna@example.com',
          'firstName': 'Анна',
          'lastName': 'Иванова',
          'role': 'client',
          'avatarFileId': null,
        },
      }),
      <String, dynamic>{
        'id': 'message-1',
        'chat_id': 'chat-1',
        'sender_id': 'user-1',
        'content': 'Файл',
        'message_type': 'file',
        'attachment_file_id': null,
        'attachment_name': 'lesson.pdf',
        'attachment_size': 42,
        'attachment_mime_type': 'application/pdf',
        'voice_duration_ms': 123,
        'reply_to_id': null,
        'forwarded_from_id': null,
        'pinned_by': null,
        'pinned_at': null,
        'created_at': null,
        'updated_at': null,
        'deleted_at': null,
        'is_read': true,
        'reactions': <Map<String, dynamic>>[
          <String, dynamic>{'emoji': '👍', 'count': 1},
        ],
        'profiles': <String, dynamic>{
          'id': 'user-1',
          'email': 'anna@example.com',
          'first_name': 'Анна',
          'last_name': 'Иванова',
          'role': 'client',
          'avatar_file_id': null,
        },
      },
    );

    expect(
      messenger.chatMember(<String, dynamic>{
        'profileId': 'profile-1',
        'userId': 'user-1',
        'email': 'member@example.com',
        'role': 'client',
        'userRole': 'student',
        'firstName': null,
        'lastName': null,
        'phone': null,
        'avatarFileId': null,
        'joinedAt': null,
        'isCurrentUser': true,
      }),
      <String, dynamic>{
        'profile_id': 'profile-1',
        'user_id': 'user-1',
        'id': 'user-1',
        'email': 'member@example.com',
        'role': 'client',
        'user_role': 'student',
        'first_name': null,
        'last_name': null,
        'phone': null,
        'avatar_file_id': null,
        'joined_at': null,
        'is_current_user': true,
        '_display_name': 'member@example.com',
      },
    );
  });

  test(
    'realtime chat summary uses the public entry point without partner data',
    () {
      final realtimeSummary = <String, dynamic>{
        'id': 'chat-realtime-1',
        'type': 'administration',
        'title': 'Администрация',
        'createdBy': 'manager-1',
        'lastMessageId': 'message-realtime-1',
        'lastMessageContent': 'Добрый день',
        'lastMessageCreatedAt': '2026-08-22T12:00:00.000Z',
        'partnerId': 'client-1',
        'unreadCount': 4,
        'isMuted': false,
        'createdAt': '2026-08-20T10:00:00.000Z',
        'updatedAt': '2026-08-22T12:00:00.000Z',
        'ownerName': 'Мария Петрова',
        'assignedTo': <String, dynamic>{'id': 'manager-1', 'name': 'Мария'},
        'folder': 'leads',
        'archived': false,
        'branchId': 'branch-1',
        'branchName': 'Центральный',
        'slug': 'administration',
        'isSystem': true,
        'canWrite': true,
      };
      final restChat = <String, dynamic>{
        'id': 'chat-realtime-1',
        'type': 'administration',
        'title': 'Администрация',
        'createdBy': 'manager-1',
        'lastMessageId': 'message-realtime-1',
        'lastMessageContent': 'Добрый день',
        'lastMessageCreatedAt': '2026-08-22T12:00:00.000Z',
        'partnerId': 'client-1',
        'partner': null,
        'unreadCount': 4,
        'isMuted': false,
        'createdAt': '2026-08-20T10:00:00.000Z',
        'updatedAt': '2026-08-22T12:00:00.000Z',
        'ownerName': 'Мария Петрова',
        'assignedTo': <String, dynamic>{'id': 'manager-1', 'name': 'Мария'},
        'folder': 'leads',
        'archived': false,
        'branchId': 'branch-1',
        'branchName': 'Центральный',
        'slug': 'administration',
        'isSystem': true,
      };
      final service = MagicMessengerService(
        MagicApiClient(
          baseUrl: 'https://api.example.test',
          tokenStore: MemoryMagicTokenStore(),
        ),
      );

      expect(
        service.legacyChatFromSummary(realtimeSummary),
        messenger.chat(restChat),
      );
    },
  );

  test(
    'messenger adapter preserves channel, permission, and post map shapes',
    () {
      expect(
        messenger.channel(<String, dynamic>{
          'id': 'channel-1',
          'title': 'Новости',
          'description': null,
          'createdBy': 'admin-1',
          'createdAt': 'created',
          'updatedAt': 'updated',
        }),
        <String, dynamic>{
          'id': 'channel-1',
          'title': 'Новости',
          'name': 'Новости',
          'description': null,
          'created_by': 'admin-1',
          'created_at': 'created',
          'updated_at': 'updated',
          '_item_type': 'channel',
          '_display_name': 'Новости',
        },
      );
      expect(
        messenger.channelPermission(<String, dynamic>{
          'id': 'permission-1',
          'channelId': 'channel-1',
          'userId': null,
          'role': 'client',
          'canRead': true,
          'canWrite': false,
          'user': null,
        }),
        <String, dynamic>{
          'id': 'permission-1',
          'channel_id': 'channel-1',
          'user_id': null,
          'role': 'client',
          'can_read': true,
          'can_write': false,
          'profiles': null,
          '_display_name': 'Клиенты',
        },
      );
      expect(
        messenger.channelPost(<String, dynamic>{
          'id': 'post-1',
          'channelId': 'channel-1',
          'authorId': 'admin-1',
          'content': 'Пост',
          'attachmentFileId': 'file-1',
          'publishedAt': 'published',
          'updatedAt': 'updated',
        }),
        <String, dynamic>{
          'id': 'post-1',
          'channel_id': 'channel-1',
          'author_id': 'admin-1',
          'sender_id': 'admin-1',
          'content': 'Пост',
          'attachment_file_id': 'file-1',
          'message_type': 'file',
          'published_at': 'published',
          'created_at': 'published',
          'updated_at': 'updated',
          'is_read': true,
        },
      );
    },
  );

  test('profile adapter preserves profile and note map shapes', () {
    expect(
      profile.profile(<String, dynamic>{
        'id': 'profile-1',
        'userId': 'user-1',
        'email': 'anna@example.com',
        'role': 'client',
        'firstName': 'Анна',
        'lastName': 'Иванова',
        'phone': null,
        'dob': null,
        'avatarFileId': null,
        'emailOtp2faEnabled': true,
        'isAppAccount': false,
        'phoneVerifiedAt': null,
        'createdAt': 'created',
        'updatedAt': 'updated',
      }),
      <String, dynamic>{
        'id': 'profile-1',
        'user_id': 'user-1',
        'email': 'anna@example.com',
        'role': 'client',
        'first_name': 'Анна',
        'last_name': 'Иванова',
        'phone': null,
        'dob': null,
        'avatar_file_id': null,
        'email_otp_2fa_enabled': true,
        'is_app_account': false,
        'phone_verified_at': null,
        'linked_students': 0,
        'linked_leads': 0,
        'linked_teachers': 0,
        'linked_staff': 0,
        'candidate_students': 0,
        'candidate_leads': 0,
        'candidate_teachers': 0,
        'candidate_staff': 0,
        'created_at': 'created',
        'updated_at': 'updated',
      },
    );
    expect(
      profile.profileNote(<String, dynamic>{
        'id': 'note-1',
        'profileId': 'profile-1',
        'authorId': 'author-1',
        'body': 'Позвонить',
        'createdAt': 'created',
        'author': <String, dynamic>{
          'id': 'author-1',
          'email': 'author@example.com',
          'firstName': 'Мария',
          'lastName': 'Петрова',
        },
      }),
      <String, dynamic>{
        'id': 'note-1',
        'profile_id': 'profile-1',
        'author_id': 'author-1',
        'body': 'Позвонить',
        'content': 'Позвонить',
        'created_at': 'created',
        'author': <String, dynamic>{
          'id': 'author-1',
          'email': 'author@example.com',
          'first_name': 'Мария',
          'last_name': 'Петрова',
        },
      },
    );
  });

  test(
    'commerce adapter preserves subscription, payment, and balance shapes',
    () {
      final account = CommerceAccount.fromJson(<String, dynamic>{
        'currencyCode': 'RUB',
        'actualPaymentsMinor': '1250',
        'adjustmentsMinor': '0',
        'obligationDebitsMinor': '0',
        'obligationCreditsMinor': '0',
        'writeOffsMinor': '2500',
        'balanceMinor': '-1250',
        'debtMinor': '1250',
      });
      final subscription = CommerceSubscription.fromJson(<String, dynamic>{
        'id': 'subscription-1',
        'status': 'active',
        'startsAt': '2026-01-01T00:00:00.000Z',
        'expiresAt': null,
        'units': <String, dynamic>{
          'total': 10,
          'used': 2,
          'reserved': 1,
          'paid': 8,
          'available': 7,
          'remaining': 8,
        },
        'financial': <String, dynamic>{
          'actualPaidMinor': '1250',
          'obligationMinor': '2500',
          'debtMinor': '1250',
          'pendingMinor': null,
          'remainingObligationMinor': null,
          'overpaymentMinor': '0',
          'nextPaymentAt': null,
        },
        'terms': <String, dynamic>{
          'displayName': '8 занятий',
          'validityDays': 30,
          'basePriceMinor': '2500',
          'finalPriceMinor': '2500',
          'currencyCode': 'RUB',
          'discount': <String, dynamic>{'type': 'none'},
        },
        'installments': <Object?>[],
      });
      final payment = CommerceMovement.fromJson(<String, dynamic>{
        'id': 'payment-1',
        'kind': 'payment',
        'direction': 'credit',
        'amountMinor': '1250',
        'currencyCode': 'RUB',
        'occurredAt': '2026-01-02T00:00:00.000Z',
        'method': 'card',
        'factType': null,
        'chargeType': 'subscription',
        'branchId': 'branch-1',
        'branchName': 'Центральный',
        'comment': null,
        'invoiceIdentifier': 'invoice-1',
        'status': 'accepted',
        'acceptedByName': 'Мария',
        'issuedSubscriptionId': 'subscription-1',
        'subscriptionName': '8 занятий',
        'sourcePaymentId': 'source-1',
        'paymentRecordVersion': null,
        'installmentId': null,
        'dueAt': null,
      });

      expect(account.toLegacyBalance('student-1'), <String, dynamic>{
        'student_id': 'student-1',
        'balance': -12.5,
        'total_paid': 12.5,
        'total_cost': 25.0,
      });
      final subscriptionMap = subscription.toLegacyMap('student-1');
      expect(subscriptionMap, isNot(contains('funding_mode')));
      expect(subscriptionMap, isNot(contains('payment_id')));
      expect(subscriptionMap['id'], 'subscription-1');
      expect(subscriptionMap['student_id'], 'student-1');
      expect(subscriptionMap, <String, dynamic>{
        'id': 'subscription-1',
        'student_id': 'student-1',
        'lessons_total': 10,
        'lessons_used': 2,
        'lessons_remaining': 8,
        'starts_at': '2026-01-01T00:00:00.000Z',
        'expires_at': null,
        'valid_until': null,
        'status': 'active',
        'type': 'Абонемент',
        'package_name': '8 занятий',
        'package_price': 25.0,
        'paid_amount': 12.5,
        'actual_paid_minor': '1250',
        'debt_minor': '1250',
        'pending_minor': '0',
        'overpayment_minor': '0',
        'next_payment_at': null,
        'base_price': 25.0,
        'currency_code': 'RUB',
      });
      expect(payment.toLegacyPayment('student-1'), <String, dynamic>{
        'id': 'payment-1',
        'student_id': 'student-1',
        'amount': 12.5,
        'currency': 'RUB',
        'payment_date': '2026-01-02T00:00:00.000Z',
        'method': 'card',
        'type': 'card',
        'description': 'subscription',
        'branch_id': 'branch-1',
        'branch_name': 'Центральный',
        'notes': 'subscription',
        'external_id': 'invoice-1',
        'status': 'accepted',
        'accepted_by_name': 'Мария',
        'students': <String, dynamic>{
          'id': 'student-1',
          'first_name': '',
          'last_name': '',
        },
      });
    },
  );
}
