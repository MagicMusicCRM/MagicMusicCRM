# F1 — MessengerController hoist: исполнительная спецификация

_Составлено 2026-07-15 после полного чтения `messenger_screen.dart` (3364).
Цель: превратить рискованный hoist в МЕХАНИЧЕСКИЙ проход. Делать в отдельной
сессии с полным контекст-бюджетом (F1 целиком = один зелёный коммит: нет
analyze-green промежутка — виджет сломан, пока не перевязаны ВСЕ ~77 setState и
11 realtime-хендлеров)._

## Архитектурное решение (низкориск, faithful)

НЕ immutable-`Notifier<State>` с copyWith (высокий churn на ~35 полях +
десятках in-place мутаций `_messages[i]=...` → баги на identity-сравнении).
Вместо этого — **revision-Notifier**:

```dart
class MessengerController extends Notifier<int> {
  @override int build() { ref.onDispose(() { _alive = false; _disposeInfra(); }); return 0; }
  bool _alive = true;
  void _emit(void Function() fn) { fn(); if (_alive) state++; } // замена setState
  // ...все ~35 полей как ПУБЛИЧНЫЕ поля контроллера (мутабельные)...
  // ...все методы логики, тела ПОЧТИ ВЕРБАТИМ...
}
final messengerControllerProvider =
    NotifierProvider<MessengerController, int>(MessengerController.new);
```

Виджет: `ref.watch(messengerControllerProvider)` (ребилд на bump revision),
данные читает `final c = ref.read(messengerControllerProvider.notifier); c.chatItems`.

### Механические замены (одинаковые везде)
1. `setState(() { BODY })` → `_emit(() { BODY })`.
2. `mounted` → `_alive`. (в контроллере нет `mounted`.)
3. `ref.read(...)` — работает как есть (Notifier имеет `ref`).
4. `widget.role` → поле `role` контроллера. Прокинуть: провайдер-family ИЛИ
   `c.role = widget.role` в `initState` виджета до первого использования.
5. `context`-зависимые методы (snackbar/showDialog/showClientCard/Navigator) —
   **НЕ переносить целиком**. Разбить на: (a) чистая state+async часть → контроллер,
   (b) UI-эффект → колбэк. Паттерн: контроллер держит
   `void Function(String msg, {Color? bg})? onSnack;` (виджет присваивает в
   initState); методы контроллера зовут `onSnack?.call(...)` вместо
   `ScaffoldMessenger.of(context)`. Диалоги подтверждения (delete, chat-row-menu)
   ОСТАЮТСЯ в виджете — виджет показывает диалог, при подтверждении зовёт
   `c.confirmDeleteMessage(mid)` (чистую).

## Инвентарь состояния (→ поля контроллера)

**Данные (ребилдят UI):** `selectedChatId, selectedChatType, selectedChatRawType,
selectedChatSlug, selectedChatName, selectedChatAvatarUrl, selectedPartnerId,
adminAvatarUrl, chatItems, messages, pinnedMessages, hiddenPinnedBars,
reactionsMap, unreadCounts, mutedChatIds, pinnedChatIds, loadingChats,
loadingMessages, searchQuery, selectedCrmTab, selectedReportsTab,
showProfilePanel, showMyProfile, adminIds, isSearchingInChat, searchResults,
currentMatchIndex, replyingTo, editingMessage, typingText, onlineUsers,
currentUserId, currentUserDisplayName, selectedFolder, openingNavigationPartnerId,
userRolesInitialSearch`.

**Инфра (НЕ в state, приватные поля, dispose в `ref.onDispose`):**
`typingStopTimer, chatListReloadTimer, realtimeFallbackTimer, realtimeConnection,
joinedRealtimeChatId, joinedChannelIds, lastRealtimeEventAt,
lastFallbackChatListAt, currentLoadId`.

**Остаётся в виджете:** `chatSearchController` (TextEditingController — UI-local),
scroll-контроллеры, `pinnedDialogSetState` (StateSetter диалога — чисто
императивный UI, живёт с диалогом), геттеры RBAC (`isAdminRole` и т.д. — чистые от
`widget.role`, можно и там и там).

## Партиция методов

**→ Контроллер (state+async+realtime, БЕЗ context):**
`bootstrapMessenger, loadCurrentProfile, openDirectChatFromNavigation (onSnack),
patchOpenChatAssignment, assignChatToMe/unassignChat (onSnack), archive/unarchiveChat,
connectRealtime, markRealtimeEvent, startRealtimeFallbackPolling,
refreshSelectedMessagesSilently, onRealtimeReconnected, joinAnnouncementChannels,
scheduleChatListReload, ВСЕ 11 handleRealtime*, normalizeRealtimeMessage/ChannelPost,
updateChatItemLastMessage, joinTypingChannel/leaveTypingChannel/trackTyping/handleTyping,
upsertMessage, sortMessagesChronologically, applySentMessage, removeMessageById,
optimisticTextMessage, sendTextMessage (onSnack на ошибках),
sendVoiceMessage/sendFileMessage, selectChat, joinReactions/PresenceChannel,
deselectChat, onMuteChat, getAvatarUrl, fetchReactionsForCurrentMessages,
applyReactionsToMessage, reactionMine, toggleReaction (onSnack), loadChatList/Internal,
loadMessages (onSnack), markMessagesRead, fetchPinnedMessages, formatTime, messagePreview`.

**Остаётся в виджете (context/dialogs/UI):**
`checkDeepLink (читает c.chatItems, зовёт c.selectChat), showChatSnack,
saveContactFromChat/openLeadCard/openContactCard (showClientCard),
showChatRowMenu (диалог→c.archive), deleteMessage (диалог→c.confirmDelete),
showSendFileDialog, hasInternalBackState/consumeBackNavigation (UI-навигация,
читает c.*), canPostToChannel, все _build*/render`.

## Тонкие места (НЕ потерять при переводе — источники багов)
- **Гварды после await:** `if (!mounted) return;` И `if (loadId != _currentLoadId) return;`
  И `if (_selectedChatId != chatId) return;` — ВСЕ сохранить (→ `_alive`, поля контроллера).
- **Оптимистичные откаты:** assign/unassign/mute/reaction/send держат `previous`/`wasMuted`
  и откатывают в catch — перенести дословно.
- **`_handleRealtimeMessageUpdated`:** патчит ТОЛЬКО пришедшие поля (aliases map) —
  не заменять на полный normalize (иначе сообщение схлопнется в «Пользователь»).
- **In-place мутации** (`_messages[idx]={...}`, `_unreadCounts[id]=`, `_reactionsMap`):
  при revision-Notifier это ОК (bump ребилдит, identity не важен). НЕ переусложнять в copyWith.
- **`currentLoadId`** — счётчик гонки загрузок; инкремент в loadMessages, сверка после await.
- **Realtime reconnect** (`onRealtimeReconnected`): re-join user room + активный чат +
  все `joinedChannelIds` — идемпотентно.
- **Fallback polling** (12с): если realtime свежий (<18с) — skip; иначе тихий refresh
  сообщений + (>36с) reload списка. Таймеры dispose в `ref.onDispose`.

## Разбиение на файлы (<800 каждый — DoD)
Контроллер ~2500 → part-файлы: `messenger_controller.dart` (shell+поля+lifecycle+bootstrap+load),
`messenger_controller_realtime.dart` (connect + 11 handlers + normalize + reconnect + fallback),
`messenger_controller_messaging.dart` (send/delete/edit/upsert/sort/optimistic/reaction/typing),
`messenger_controller_chats.dart` (selectChat/deselect/mute/assign/archive/loadChatList).
Все — `part of 'messenger_controller.dart'` + приватные extension ИЛИ методы одного класса
(класс не дробится по part → использовать `extension _X on MessengerController` для групп).
Виджет ~900 (builders) → вынести `_buildChatList`/`_buildChatView`/`_buildCrmBody` как
setState-free (после hoist они зовут `c.method()`, не setState) в `messenger_screen_builders.dart`
(extension). Цель: messenger_screen.dart < 800.

## Runtime чек-лист (ручная проверка после)
1. Открыть мессенджер staff-ролью и client-ролью — список чатов грузится, аватар админ-чата.
2. Выбрать чат → сообщения грузятся, read-маркер сбрасывает unread.
3. Отправить текст (оптимистичный → серверный), voice, файл с подписью.
4. Редактировать своё сообщение; удалить своё (диалог) — обновляется мгновенно.
5. Реакция: поставить/снять — чип мгновенно, после сервера консистентно; ошибка → откат.
6. Реалтайм со 2-го устройства: новое сообщение в открытом чате (появляется + read),
   в закрытом (unread++ + локальное уведомление, если не muted).
7. Typing-индикатор появляется/исчезает; presence (онлайн-точки).
8. Mute/unmute; assign/unassign (админ-чат); archive/unarchive → перебакетизация в папки.
9. Pinned bar; закреплённые сообщения диалог.
10. Deep-link из уведомления открывает нужный чат (в т.ч. до и после загрузки списка).
11. Reconnect: убить сеть на 30с, вернуть — комнаты пере-джойнятся, fallback-поллинг не дублирует.
12. Back-навигация (профиль→поиск→чат→CRM-таб) в правильном порядке.
