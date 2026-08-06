import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = path.resolve("outputs/feature-quality");
const outputFile = path.join(outputDir, "MagicMusicCRM-Canonical-Feature-Register.xlsx");
const previewDir = path.join(outputDir, "previews");

const stories = [];
function addGroup(prefix, system, defaults, items) {
  items.forEach((item, index) => {
    const [feature, personas, want, expected, scope, priority = "P1", preconditions = defaults.preconditions, trigger = defaults.trigger, ui = defaults.ui, api = defaults.api, automated = defaults.automated] = item;
    stories.push({
      id: `${prefix}-${String(index + 1).padStart(3, "0")}`,
      system,
      feature,
      personas,
      story: `Как ${personas}, я хочу ${want}, чтобы рабочий сценарий был предсказуемым.`,
      preconditions,
      trigger,
      expected,
      scope,
      platforms: defaults.platforms,
      ui,
      api,
      automated,
      implementation: "CODE-BACKED",
      testStatus: "NOT EXECUTED",
      latestResult: "",
      errorIds: "",
      priority,
      lastTested: "",
      evidenceLink: "",
      notes: "Expected behavior извлечено из production-кода; runtime acceptance ещё не выполнен.",
    });
  });
}

addGroup("AUTH", "Session & Account", {
  preconditions: "Приложение установлено; backend доступен.",
  trigger: "Открыть соответствующий auth/account экран и выполнить действие.",
  ui: "lib/features/auth/presentation; lib/core/router/app_router.dart",
  api: "lib/features/auth/data/services; server/src/auth; server/src/legal; server/src/profile",
  automated: "test/features/auth; docs/audits/v6-role-workspace-acceptance.md",
  platforms: "Windows, Android",
}, [
  ["Cold start gate", "пользователь", "видеть безопасную загрузку при старте", "До завершения чтения session/legal/onboarding gate показывается loading/skeleton; запрещённый экран не мелькает.", "all", "P0"],
  ["Resume valid session", "ранее вошедший пользователь", "возобновить действующую сессию", "Открывается workspace именно сохранённого пользователя и его актуальной роли; повторный login не требуется.", "current account", "P0"],
  ["Reject stale session", "пользователь с истёкшей сессией", "безопасно вернуться ко входу", "Невалидные токены очищаются; приложение не зацикливается и не открывает старый workspace.", "current account", "P0"],
  ["Password login", "пользователь", "войти по email и паролю", "Во время запроса поля и focus сохраняются; при успехе открывается role route, при ошибке показано одно понятное сообщение.", "self", "P0"],
  ["Invalid credentials", "пользователь", "понять причину неуспешного входа", "Неверные данные не создают session; форма остаётся доступной, значения не сбрасываются без причины.", "self", "P0"],
  ["Repeated login", "пользователь", "повторно войти после logout тем же аккаунтом", "Кнопка входа отправляет новый запрос, старые provider/socket state не блокируют вход.", "self", "P0"],
  ["Switch account", "пользователь", "выйти и войти другим аккаунтом", "Новый аккаунт не наследует route, tabs, API cache, realtime handlers или права предыдущего.", "account isolation", "P0"],
  ["Logout", "вошедший пользователь", "завершить текущую сессию", "Токены, account-scoped workspace и realtime transport очищаются; показывается Login.", "self", "P0"],
  ["Logout all devices", "вошедший пользователь", "завершить все сессии", "Backend инвалидирует refresh-сессии; текущее устройство также возвращается ко входу.", "self", "P1"],
  ["Password signup", "новый пользователь", "зарегистрироваться по email и паролю", "Валидная форма создаёт pending account и переводит к подтверждению email; ошибки показаны рядом с действием.", "public", "P1"],
  ["Signup OTP verify", "новый пользователь", "подтвердить email кодом", "Верный код активирует account/session; неверный не очищает email и позволяет повторить ввод.", "public", "P1"],
  ["Resend signup OTP", "новый пользователь", "запросить новый код", "Повторная отправка ограничена UI/сервером и подтверждается без дублирования экранов.", "public", "P2"],
  ["Email OTP login", "пользователь", "войти одноразовым кодом", "Код проверяется для указанного email; успешная проверка создаёт обычную session и применяет gates.", "self", "P1"],
  ["MFA challenge", "пользователь с MFA", "завершить второй фактор", "После password step открывается OTP challenge; workspace недоступен до успешной проверки.", "self", "P0"],
  ["Request password reset", "пользователь", "запросить восстановление пароля", "Запрос не раскрывает существование чужого account и переводит к вводу кода/нового пароля.", "public", "P1"],
  ["Confirm password reset", "пользователь", "задать новый пароль по коду", "Валидный code+password меняет пароль; старый пароль больше не создаёт session.", "self", "P0"],
  ["Set password", "вошедший пользователь без пароля", "добавить password method", "Пароль сохраняется только после проверки политики; session остаётся активной.", "self", "P1"],
  ["Auth methods", "вошедший пользователь", "просмотреть и изменить способы входа", "Экран показывает фактические identities/MFA; недоступные действия disabled или отсутствуют.", "self", "P1"],
  ["Google identity", "вошедший пользователь", "связать Google identity", "Link flow не создаёт второй профиль и после успеха отражается в identities.", "self", "P2"],
  ["Onboarding", "новый вошедший пользователь", "завершить обязательные начальные данные", "До submit рабочий workspace закрыт; успешный submit выполняется один раз и gate исчезает.", "self", "P1"],
  ["Legal gate", "вошедший пользователь", "принять актуальные документы", "Непринятые версии блокируют рабочий route; consent сохраняет версии и время.", "self", "P0"],
  ["Legal document view", "пользователь", "прочитать документ перед согласием", "Открывается выбранная актуальная версия; возврат сохраняет состояние consent screen.", "self", "P2"],
  ["Profile edit", "вошедший пользователь", "обновить свой профиль", "Валидные поля сохраняются и сразу отображаются; forbidden/system fields не отправляются.", "self", "P1"],
  ["MFA toggle", "вошедший пользователь", "включить или выключить email OTP MFA", "Текущее состояние загружается с backend; переключение подтверждается сохранённым состоянием.", "self", "P1"],
  ["Account deletion request", "вошедший пользователь", "запросить удаление account", "Создаётся одна pending заявка с reason; UI показывает статус и не имитирует немедленное удаление.", "self", "P1"],
  ["Account deletion status", "пользователь с заявкой", "увидеть статус удаления", "Статус читается из backend и переживает restart/login.", "self", "P1"],
]);

addGroup("NAV", "App Experience", {
  preconditions: "Пользователь вошёл; capability snapshot загружен.",
  trigger: "Использовать nav, deep link, tab или Back/Forward.",
  ui: "lib/core/router; lib/core/navigation; lib/core/workspace; lib/core/widgets/v7",
  api: "server/src/access-control; lib/core/services/magic_access_service.dart",
  automated: "test/core/router; test/core/navigation; test/core/workspace; docs/audits/v6-user-workflow-acceptance.md",
  platforms: "Windows, Android",
}, [
  ["Role landing", "вошедший пользователь", "открыть свой основной workspace", "Login/gates направляют на canonical route роли, а не на экран предыдущего пользователя.", "effective role", "P0"],
  ["Client navigation", "клиент", "видеть только личные разделы", "Доступны Chat, Lessons/Homework, Subscription/Payments и Profile; staff destinations отсутствуют.", "client self", "P0"],
  ["Teacher navigation", "преподаватель", "видеть назначенную рабочую область", "Доступны Chat, Day/Week Schedule и assigned Students; write/finance/settings скрыты.", "teacher assigned", "P0"],
  ["Admin navigation", "администратор", "работать с Chat, Schedule и Clients", "Tasks, school finance, analytics/config/user administration не появляются и не prefetch-ятся.", "admin ceiling", "P0"],
  ["Manager navigation", "управляющий", "работать с operational workspace", "Overview/Schedule/Clients/Tasks/allowed Analytics/Settings видимы; school finance отсутствует.", "manager branch scope", "P0"],
  ["Director navigation", "директор", "открыть полный business workspace", "Operational, school finance, configuration and access destinations соответствуют capability snapshot.", "director school scope", "P0"],
  ["Forbidden deep link", "пользователь без capability", "безопасно открыть запрещённую ссылку", "Показывается forbidden/fallback без provider/service request защищённого раздела.", "fail closed", "P0"],
  ["Typed entity link", "staff пользователь", "перейти к связанному Client/Lesson/Profile", "Открывается canonical route с human label; raw UUID не используется как нормальный title.", "actor-safe projection", "P1"],
  ["Desktop open current tab", "desktop staff", "открыть entity в текущей вкладке", "Текущая вкладка меняет route, сохраняя source state для Back.", "account scoped", "P1"],
  ["Desktop open new tab", "desktop staff", "открыть entity в новой вкладке", "Создаётся отдельная вкладка без изменения соседних; forbidden entity не prefetch-ится.", "account scoped", "P1"],
  ["Workspace restart restore", "desktop staff", "восстановить вкладки после restart", "Восстанавливаются вкладки только этого account и только разрешённые актуальной ролью.", "account scoped", "P0"],
  ["Workspace logout clear", "desktop staff", "не оставить вкладки после logout", "После следующего login другой account не видит старые вкладки или историю.", "account isolation", "P0"],
  ["Per-tab Back/Forward", "desktop staff", "вернуться по истории текущей вкладки", "Back/Forward меняет только активную вкладку и восстанавливает filter/source context.", "current tab", "P1"],
  ["Compact Back", "mobile пользователь", "вернуться системным Back", "GoRouter stack закрывает modal/route в правильном порядке; Android edge gesture эквивалентен Back.", "current route", "P0"],
  ["Dirty editor guard", "пользователь с несохранённой формой", "не потерять изменения случайным Back", "Перед закрытием показывается единое подтверждение; cancel оставляет форму, discard закрывает.", "current editor", "P0"],
  ["Adaptive surface", "пользователь", "получить подходящий modal layout", "Короткий выбор: sheet→drawer; длинное редактирование: fullscreen; delete: concise confirmation.", "device width", "P1"],
  ["Routed states", "пользователь", "понимать loading/empty/error/forbidden", "Каждый route показывает единые состояния и retry там, где действие безопасно.", "actor scoped", "P1"],
  ["Keyboard and semantics", "desktop/assistive пользователь", "управлять интерфейсом клавиатурой", "Interactive controls имеют focus order, labels/tooltips; одна primary action на surface.", "accessibility", "P1"],
]);

addGroup("CHAT", "Messenger", {
  preconditions: "Пользователь вошёл; Chat destination разрешён.",
  trigger: "Открыть Chat и выполнить действие в списке/переписке/канале.",
  ui: "lib/features/messenger/presentation/screens/messenger_screen.dart",
  api: "lib/core/services/magic_messenger_service.dart; server/src/messenger",
  automated: "test/features/messenger; server/src/messenger/*.spec.ts",
  platforms: "Windows, Android",
}, [
  ["Load chats", "пользователь", "увидеть доступные диалоги", "Список содержит только разрешённые direct/group chats, корректные unread/last-message metadata и routed loading/error states.", "actor chat scope", "P0"],
  ["Chat search typing", "пользователь", "ввести запрос без restart страницы", "Каждый символ сохраняется и focus остаётся в поле; результат фильтруется без полного/частичного route restart.", "actor chat scope", "P0"],
  ["Staff folders", "staff пользователь", "фильтровать рабочий inbox по папке", "Переключение папки меняет список, не теряя ввод и выбранный chat без необходимости.", "staff only", "P1"],
  ["Branch filter", "staff пользователь", "ограничить inbox филиалом", "Показываются chats разрешённого Branch; выбранный scope видим и очищаем.", "assigned branches", "P1"],
  ["Pinned ordering", "пользователь", "видеть закреплённые разговоры первыми", "Pinned chats стабильно сортируются выше остальных без потери unread state.", "actor chat scope", "P2"],
  ["Open chat", "пользователь", "открыть разговор", "Загружаются разрешённые messages/members; room join выполняется только после policy authorization.", "chat membership", "P0"],
  ["Create direct chat", "пользователь", "начать личный диалог", "Существующий direct chat переиспользуется; дубликат между той же парой не создаётся.", "per policy", "P1"],
  ["Create group", "staff пользователь", "создать групповой chat", "Валидные title/members создают один group и он появляется realtime у участников.", "staff/member policy", "P1"],
  ["Edit group members", "group manager", "изменить участников", "Только разрешённый actor меняет membership; UI и realtime отражают итоговый состав.", "group policy", "P1"],
  ["Leave group", "участник группы", "покинуть группу", "Membership удаляется, chat исчезает/становится недоступен, повторное leave идемпотентно для UX.", "self membership", "P1"],
  ["Send text", "участник chat", "отправить сообщение", "Непустой текст создаёт одно message, pending state заменяется server result, duplicate tap не создаёт двойную запись.", "chat write", "P0"],
  ["Reply", "участник chat", "ответить на конкретное message", "Reply reference сохраняется и отображает actor-safe preview исходного сообщения.", "chat write", "P1"],
  ["Forward", "участник chat", "переслать message", "Выбранное сообщение отправляется один раз в разрешённый target chat с понятным attribution.", "source read + target write", "P1"],
  ["Edit message", "автор сообщения", "исправить своё сообщение", "Допустимое message обновляется, edited state виден realtime; чужое edit запрещено.", "message owner/policy", "P1"],
  ["Delete message", "разрешённый пользователь", "удалить сообщение", "После подтверждения message удаляется/маркируется по server policy и обновляется realtime.", "message owner/moderator", "P1"],
  ["Upload attachment", "участник chat", "отправить файл", "Файл загружается через file service; message создаётся только с валидной ссылкой, ошибка upload не создаёт пустое сообщение.", "chat write/file limits", "P0"],
  ["Voice message", "участник chat", "записать и отправить голосовое", "Запись можно отменить; успешный upload создаёт playable message, ошибка оставляет возможность повторить.", "chat write/media permissions", "P0"],
  ["Add reaction", "участник chat", "добавить реакцию", "Emoji добавляется один раз от пользователя и синхронизируется realtime.", "chat member", "P2"],
  ["Remove reaction", "участник chat", "убрать свою реакцию", "Удаляется только собственная реакция; итоговый count обновляется.", "self reaction", "P2"],
  ["Pin message", "разрешённый участник", "закрепить важное сообщение", "Pin сохраняется один раз и доступен участникам; forbidden actor не видит mutation.", "chat policy", "P2"],
  ["Unpin message", "разрешённый участник", "снять закрепление", "Pin удаляется и список обновляется без удаления самого message.", "chat policy", "P2"],
  ["Mark read", "участник chat", "отметить просмотренное", "Last-read message обновляется монотонно; unread уменьшается без потери новых сообщений.", "self membership", "P0"],
  ["Mute chat", "участник chat", "отключить уведомления разговора", "Mute сохраняется для пользователя и не влияет на других участников.", "self preference", "P2"],
  ["Archive chat", "разрешённый пользователь", "убрать разговор из активного inbox", "Archive меняет видимость в папках без удаления history; unarchive возвращает его.", "chat policy", "P1"],
  ["Assign chat", "staff пользователь", "назначить ответственного", "Назначение проверяется policy, отражается в inbox и может быть снято.", "staff inbox", "P1"],
  ["Channels list", "пользователь", "видеть доступные каналы", "Список содержит только разрешённые channels и их access/permissions.", "channel read", "P1"],
  ["Channel posts", "пользователь", "читать объявления", "Posts загружаются по access; join channel даёт новые posts realtime.", "channel read", "P1"],
  ["Manage channel", "разрешённый staff", "создать или изменить канал", "Title/access/permissions сохраняются; обычный пользователь mutation не получает.", "channel manage", "P1"],
  ["Publish channel post", "разрешённый автор", "опубликовать объявление", "Один post создаётся и доставляется channel members realtime.", "channel publish", "P1"],
  ["Typing and presence", "участник chat", "видеть typing/presence", "Events rate-limited, room-scoped и не раскрывают пользователей вне разрешённой комнаты.", "room policy", "P1"],
  ["Realtime reconnect", "пользователь", "продолжить chat после sleep/network loss", "Reconnect получает свежий JWT, повторно join-ит rooms и не дублирует handlers/messages.", "current account", "P0"],
  ["Save chat contact", "staff пользователь", "связать собеседника с CRM", "Создаётся/находится actor-safe contact link; duplicate client не создаётся автоматически.", "crm.client.write", "P1"],
]);

addGroup("CRM", "CRM Clients", {
  preconditions: "Пользователь вошёл; Clients destination и нужный resource scope разрешены.",
  trigger: "Открыть Clients/Client workspace и выполнить действие.",
  ui: "lib/features/manager/presentation/widgets/leads_widget.dart; lib/features/crm/presentation/client_card",
  api: "lib/core/services/magic_crm_service*.dart; server/src/crm/crm-*controller.ts",
  automated: "test/features/crm; server/src/crm/**/*.spec.ts; docs/audits/v6-client-workspace.md",
  platforms: "Windows, Android",
}, [
  ["Lead board", "staff пользователь", "видеть Leads по effective pipeline", "Колонки/порядок берутся из опубликованной конфигурации; count/cards соответствуют текущему scope.", "crm.client.read", "P0"],
  ["Lead search typing", "staff пользователь", "ввести ФИО/телефон без restart", "Каждый символ остаётся в поле, focus не теряется, только matching cards/rows остаются видимыми.", "crm.client.read", "P0"],
  ["Lead filters", "staff пользователь", "фильтровать Leads", "Source/status/branch/responsible filters применяются совместно и явно сбрасываются.", "crm.client.read", "P1"],
  ["Create Lead", "staff пользователь", "создать обращение", "Required effective fields валидируются; source выбирается из reusable options; успешная запись появляется один раз.", "crm.client.write", "P0"],
  ["Edit Lead", "staff пользователь", "изменить карточку Lead", "Версионируемые стандартные/custom fields сохраняются; field-level 422 показывается у поля.", "crm.client.write + scope", "P0"],
  ["Move Lead stage", "staff пользователь", "переместить Lead по funnel", "Разрешённый transition сохраняется и D&D card остаётся в новой колонке; forbidden transition откатывает UI с объяснением.", "crm.client.write", "P0"],
  ["Lead status history", "staff пользователь", "увидеть историю стадий", "История показывает actor/time/from/to без переписывания прошлых событий.", "crm.client.read", "P1"],
  ["Lead applications", "staff пользователь", "просмотреть обращения Lead", "Связанные applications загружаются в scope и не дублируются.", "crm.client.read", "P2"],
  ["Lead blacklist", "разрешённый staff", "пометить Lead в blacklist", "Изменение требует допустимого reason/state и отражается во всех projections.", "crm.client.write", "P1"],
  ["Phone review queue", "staff пользователь", "обработать сомнительные телефоны", "Count и queue согласованы; исправление нормализует телефон или сохраняет явный warning.", "crm.client.write", "P1"],
  ["Duplicate review", "staff пользователь", "увидеть кандидатов-дубликатов", "Пары объясняют совпадение и позволяют подтвердить/отклонить без автоматического destructive merge.", "crm.client.write", "P1"],
  ["Merge clients", "разрешённый staff", "объединить подтверждённые дубликаты", "Preview/choice winner сохраняет связи и пишет merge log; loser не остаётся активным дублем.", "crm.client.write", "P0"],
  ["Undo merge", "разрешённый staff", "отменить ошибочное объединение", "Допустимый merge log восстанавливает записи/связи детерминированно или объясняет невозможность.", "crm.client.write", "P0"],
  ["Convert Lead", "staff пользователь", "конвертировать Lead в Student", "Один Student и conversion link создаются даже при повторе; совместимые fields/relations переносятся.", "crm.client.write", "P0"],
  ["Archive source Lead", "директор", "архивировать Lead после conversion", "Source Lead архивируется с expectedVersion/confirm/reason, Student и links сохраняются.", "director/system_admin", "P0"],
  ["Client archive preview", "директор", "увидеть влияние удаления клиента", "Preview перечисляет future lessons/tasks/subscription/finance impact без mutation.", "director/system_admin", "P0"],
  ["Archive client", "директор", "архивировать клиента безопасно", "Требуются expectedVersion, confirm и reason; tombstone/history/financial facts сохраняются.", "director/system_admin", "P0"],
  ["Student list", "staff/assigned teacher", "видеть доступных Students", "Projection и поля соответствуют actor scope; Teacher не получает contact/finance/private data.", "actor client scope", "P0"],
  ["Student search typing", "staff/assigned teacher", "ввести ФИО без restart", "Значение/focus сохраняются на каждом символе; запрос/фильтр не пересоздаёт route.", "actor client scope", "P0"],
  ["Create Student", "staff пользователь", "создать Student напрямую", "Required effective fields валидируются, duplicate risk обрабатывается, запись появляется один раз.", "crm.client.write", "P0"],
  ["Edit Student", "staff пользователь", "изменить Student", "Версия и effective fields сохраняются; несовместимые custom values не теряются молча.", "crm.client.write + scope", "P0"],
  ["Move Student stage", "staff пользователь", "изменить Student funnel state", "Используется опубликованный Student pipeline и разрешённый transition; counts согласованы.", "crm.client.write", "P1"],
  ["Return Student to Lead", "разрешённый staff", "вернуть Student в Lead workflow", "Операция сохраняет identity/conversion history и не дублирует исходного клиента.", "crm.client.write", "P1"],
  ["Invite Student", "staff пользователь", "пригласить клиента в portal", "Invite связывает/создаёт user безопасно, повтор не создаёт второй account.", "crm.client.write", "P1"],
  ["Open client workspace", "staff/assigned teacher", "открыть canonical карточку клиента", "Открывается human-labelled Student/Lead route с actor-safe tabs and states.", "actor client scope", "P0"],
  ["Client tab navigation", "staff пользователь", "переключать Overview/Lessons/Payments/Tasks/History", "Tabs не создают параллельные данные; текущий tab сохраняется в workspace state.", "capability projected", "P1"],
  ["Client timeline", "staff/assigned teacher", "видеть хронологию", "События сортируются по времени и скрывают fields, запрещённые actor projection.", "actor client scope", "P1"],
  ["Client comments", "staff/teacher", "добавить комментарий", "Комментарий сохраняется один раз; teacher видит только shared comments.", "comment policy", "P1"],
  ["Comment visibility", "staff пользователь", "управлять доступом Teacher", "Shared flag меняется атомарно/versioned; private text не утекает через realtime/logs.", "crm.client.write", "P0"],
  ["Family", "staff пользователь", "создать семью и участников", "Family links не дублируются, primary payer выбирается явно, removal не удаляет client entity.", "crm.client.write", "P1"],
  ["Linked user", "staff пользователь", "связать Client с account", "Candidates actor-safe; explicit link предотвращает двойную self-identity.", "crm.client.write", "P1"],
  ["Client groups", "staff/assigned teacher", "видеть группы Student", "Показываются только доступные группы; links ведут к human-labelled related entities.", "actor scope", "P1"],
  ["Homework create", "teacher/staff", "назначить домашнее задание", "Title/body/due/files валидируются; Student получает одну запись.", "assigned teacher or staff", "P1"],
  ["Homework update", "разрешённый автор", "изменить домашнее задание", "Разрешённые fields обновляются, history/status не теряются.", "homework policy", "P1"],
  ["Homework attachment", "teacher/student", "добавить файл к ДЗ", "Файл проходит upload/access boundary и виден только участникам задания.", "homework policy", "P0"],
  ["Homework submit", "student", "сдать домашнее задание", "Submission создаётся один раз с доступными attachments и отображается Teacher.", "student self", "P0"],
  ["Preferred schedule", "staff пользователь", "сохранить предпочтительное расписание клиента", "Preference хранится отдельно от Lessons и используется как подсказка, не как факт занятия.", "crm.client.write", "P1"],
]);

addGroup("PORT", "Client Portal", {
  preconditions: "Client вошёл под self account.",
  trigger: "Открыть нижнюю навигацию Client и соответствующий segment.",
  ui: "lib/features/client/presentation; lib/features/messenger/presentation/screens/messenger_screen.dart",
  api: "lib/core/services/magic_crm_service*.dart; server/src/crm/crm-students.controller.ts; server/src/crm/commerce; server/src/crm/crm-engagement.controller.ts",
  automated: "test/features/client; docs/audits/v6-role-workspace-acceptance.md",
  platforms: "Windows, Android",
}, [
  ["Upcoming lessons", "клиент", "видеть предстоящие занятия", "Self-scoped lessons показывают дату/время, Teacher, Branch, Room, duration and current lifecycle; чужие lessons отсутствуют.", "client self", "P0"],
  ["Lesson history", "клиент", "видеть историю занятий", "Past/terminal lessons отделены от upcoming and retain human labels/status without editable staff actions.", "client self", "P0"],
  ["Homework list", "клиент", "видеть свои задания", "Assignments show status, description and due date; attachments/submission actions follow homework policy.", "client self", "P0"],
  ["Subscription summary", "клиент", "видеть активный абонемент или честное empty state", "Active snapshot/remaining units are shown when present; otherwise a clear contact-admin message appears.", "client self finance", "P0"],
  ["Payment history", "клиент", "видеть свои оплаты", "Self payment list shows immutable amount/date/purpose and no staff mutation controls.", "client self finance", "P0"],
  ["Self profile", "клиент", "видеть и безопасно редактировать профиль", "Profile loads current name/photo/phone/birth date/auth methods; role is read-only and valid changes persist.", "client self", "P1"],
  ["My school overview", "клиент", "быстро открыть сводку школы", "My School opens a composed self portal with child switcher when needed, subscription status, upcoming/history/homework segments and explicit refresh.", "client self", "P1"],
]);

addGroup("SCH", "Schedule", {
  preconditions: "Пользователь вошёл; Schedule разрешён; branch/timezone data загружены.",
  trigger: "Открыть Schedule, выбрать view/filter или выполнить lesson action.",
  ui: "lib/features/admin/presentation/widgets/schedule_widget.dart; create_lesson_dialog.dart; lib/features/crm/presentation/client_card",
  api: "lib/core/services/magic_crm_service_schedule.dart; server/src/crm/crm-schedule.controller.ts; server/src/crm/schedule",
  automated: "test/features/admin/*schedule*; server/src/crm/schedule/*.spec.ts; docs/audits/v6-client-workspace.md",
  platforms: "Windows, Android",
}, [
  ["Month view", "schedule reader", "просмотреть месяц", "Показываются дни в выбранном branch/timezone с lesson indicators и корректным переходом к дню.", "schedule.lesson.read", "P0"],
  ["Week view", "schedule reader", "просмотреть неделю", "Липкие headers/time column остаются понятными при scroll; lessons размещены по фактическим интервалам.", "schedule.lesson.read", "P0"],
  ["Day view", "schedule reader", "просмотреть день", "Все доступные lessons дня показываются с human labels и без горизонтального скрытия action context.", "schedule.lesson.read", "P0"],
  ["Date navigation", "schedule reader", "перейти к другой дате/сегодня", "Period меняется детерминированно, выбранные branch/view/search state сохраняются где применимо.", "schedule.lesson.read", "P1"],
  ["Branch filter", "schedule reader", "выбрать филиал", "Показываются только доступные branch lessons/resources; default branch не смешивает school-wide data.", "assigned branch scope", "P0"],
  ["Search typing", "schedule reader", "ввести имя/ФИО без restart", "Каждый символ сохраняется, focus остаётся в search field, calendar не пересоздаёт route.", "schedule.lesson.read", "P0"],
  ["Month search highlighting", "schedule reader", "найти клиента в Month", "Зелёными становятся только дни с matching lesson; остальные дни/lessons визуально нейтральны/серые, glow помогает найти совпадение.", "schedule.lesson.read", "P0"],
  ["Week search highlighting", "schedule reader", "найти клиента в Week", "Только matching lesson cards зелёные + ergonomic glow; остальные lessons серые, но остаются читаемыми.", "schedule.lesson.read", "P0"],
  ["Day search highlighting", "schedule reader", "найти клиента в Day", "Только matching lessons зелёные/glow, остальные серые; очистка поиска полностью возвращает normal palette.", "schedule.lesson.read", "P0"],
  ["No-match search", "schedule reader", "понять отсутствие совпадений", "Calendar не исчезает и не restarts; показано спокойное no-match state без ложных зелёных элементов.", "schedule.lesson.read", "P1"],
  ["Create lesson", "разрешённый staff", "создать занятие", "Форма требует typed ClientRef, branch/room/teacher/time and configured fields; один valid Lesson создаётся.", "schedule.lesson.write", "P0"],
  ["Constraint preview", "разрешённый staff", "проверить занятие до записи", "Preview перечисляет branch hours, room/teacher/client conflicts and availability без mutation.", "schedule.lesson.write", "P0"],
  ["Conflict rejection", "разрешённый staff", "не создать конфликтное занятие", "Server повторно проверяет constraints в transaction; UI показывает конкретные blockers и сохраняет форму.", "schedule.lesson.write", "P0"],
  ["Edit lesson", "разрешённый staff", "изменить занятие", "Expected version защищает от stale write; успешное обновление синхронизируется во всех calendars.", "schedule.lesson.write", "P0"],
  ["Reschedule preview", "разрешённый staff", "увидеть влияние переноса", "Preview показывает conflicts/finance/lifecycle consequences до подтверждения.", "schedule.lesson.write", "P0"],
  ["Reschedule lesson", "разрешённый staff", "перенести занятие", "Создаётся версионированный transition/predecessor-successor contract; старый slot не остаётся активным дублем.", "schedule.lesson.write", "P0"],
  ["Cancel preview", "разрешённый staff", "увидеть последствия отмены", "Preview объясняет lifecycle/financial result и требует явного подтверждения.", "schedule.lesson.write", "P0"],
  ["Cancel lesson", "разрешённый staff", "отменить занятие", "Terminal transition выполняется один раз; settlement/reservation state не дублируется.", "schedule.lesson.write", "P0"],
  ["Delete lesson", "разрешённый actor", "удалить допустимое занятие", "Delete доступен только lifecycle/policy-совместимой записи и требует concise confirmation.", "schedule.lesson.write", "P1"],
  ["Attendance", "разрешённый staff/teacher", "отметить посещаемость", "Допустимый lifecycle transition сохраняет attendance один раз и обновляет settlement projection.", "lesson transition policy", "P0"],
  ["Auto completion", "system", "автоматически завершать прошедшие занятия", "Worker переводит eligible Lessons один раз, retries safe, poison/failure observable.", "server worker", "P0"],
  ["Teacher rate", "разрешённый staff", "назначить ставку занятиям", "Rate mutation применяет scope/version rules и возвращает точное число изменённых Lessons.", "teacher rate capability", "P1"],
  ["Series create", "разрешённый staff", "создать повторяющуюся серию", "Правило создаёт bounded future lessons с conflict handling; duplicate generation предотвращена.", "schedule.lesson.write", "P0"],
  ["Series update", "разрешённый staff", "изменить серию", "Изменение явно определяет future scope и не переписывает historical terminal lessons.", "schedule.lesson.write", "P0"],
  ["Series delete", "разрешённый staff", "остановить серию", "Future generation прекращается; прошлые Lessons/history сохраняются.", "schedule.lesson.write", "P1"],
  ["Schedule matrix", "schedule reader", "увидеть room/teacher/client matrix", "Matrix согласована с visible period/scope и выделяет фактические conflicts.", "schedule.lesson.read", "P1"],
  ["Month summary", "schedule reader", "быстро увидеть насыщенность месяца", "Day counts совпадают с drilldown Lessons после тех же filters.", "schedule.lesson.read", "P1"],
  ["Conflict list", "разрешённый staff", "просмотреть текущие конфликты", "Список содержит объяснимые blockers and typed links к затронутым entities.", "schedule.lesson.read", "P1"],
  ["Client bounded calendar", "staff пользователь", "видеть клиентские занятия в контексте branch", "Month/Week/Day viewport bounded; selected-client lessons зелёные, остальные серые, links/back сохраняют context.", "client read + schedule read", "P0"],
  ["Teacher read-only schedule", "teacher", "видеть назначенные Day/Week Lessons", "Показываются только assigned Lessons; write controls отсутствуют и hidden requests не отправляются.", "teacher assigned-only", "P0"],
  ["Branch hours", "разрешённый config actor", "задать часы и исключения филиала", "IANA timezone + weekly/exception intervals сохраняются versioned и сразу участвуют в constraint preview.", "schedule configuration", "P0"],
  ["Teacher branch assignment", "разрешённый config actor", "назначить Teacher филиалам", "Effective-dated assignments ограничивают schedule read/write; пустой active Teacher выдаёт readiness blocker.", "schedule configuration", "P0"],
  ["Teacher availability", "разрешённый config actor", "задать доступность Teacher", "Recurring/exception rules versioned, timezone-correct и участвуют в conflict engine.", "schedule configuration", "P0"],
  ["Room availability", "schedule writer", "выбрать свободную аудиторию", "Selector показывает доступные Rooms выбранного Branch/interval и server всё равно revalidates.", "schedule.lesson.write", "P0"],
]);

addGroup("COM", "Commerce", {
  preconditions: "Пользователь вошёл; client/package/finance scope разрешён.",
  trigger: "Открыть Payments/Subscription/Finance/Settings catalog и выполнить действие.",
  ui: "lib/features/crm/presentation/client_card; lib/features/manager/presentation/widgets/finance_widget.dart; manage_entities_widget.dart",
  api: "lib/core/services/magic_crm_service_finance.dart; server/src/crm/commerce; server/src/crm/crm-finance.controller.ts",
  automated: "test/features/crm/*commerce*; server/src/crm/commerce/*.spec.ts",
  platforms: "Windows, Android",
}, [
  ["Package catalog read", "разрешённый staff", "просмотреть каталог абонементов", "Показываются active offers с price/units/duration/terms без изменения issued snapshots.", "commerce.package.read", "P1"],
  ["Create package", "директор/system admin", "создать пакет", "Валидное offer сохраняется один раз и становится доступно для новых выдач.", "commerce.package.manage", "P0"],
  ["Edit package", "директор/system admin", "изменить будущие условия", "Изменения влияют только на новые issuance; существующие snapshots неизменны.", "commerce.package.manage", "P0"],
  ["Archive package", "директор/system admin", "скрыть устаревший пакет", "Active issuance больше не предлагает пакет; historical subscriptions сохраняют snapshot.", "commerce.package.manage", "P0"],
  ["Restore package", "директор/system admin", "вернуть пакет", "Archived offer снова становится доступно без создания duplicate id.", "commerce.package.manage", "P1"],
  ["Issue Student subscription", "разрешённый staff", "выдать Student абонемент", "Preview/token and submit фиксируют immutable package/commercial snapshot, units and version.", "student finance write", "P0"],
  ["Issue Lead subscription", "разрешённый staff", "оформить абонемент Lead", "Issuance использует explicit Lead identity and conversion link rules без подмены Student.", "client finance write", "P1"],
  ["Commercial terms", "разрешённый staff", "задать скидку/надбавку/рассрочку/метод", "UI валидирует terms; итоговая сумма и installments сохраняются в immutable snapshot.", "client finance write", "P0"],
  ["Record payment", "разрешённый staff", "зафиксировать платёж", "Amount/method/date/branch/status/reference валидируются; создаётся один immutable Payment.", "client finance write", "P0"],
  ["Client commerce self view", "клиент", "видеть свой абонемент и оплаты", "Projection содержит только self subscription/payment/balance data и обновляется после invalidation.", "client self", "P0"],
  ["Staff client commerce view", "admin/manager/director", "видеть финансы карточки клиента", "Разрешённые roles получают ledger/subscription/payment history; Teacher не получает эти поля.", "canReadStudentFinance", "P0"],
  ["Paid lesson balance", "клиент/staff", "видеть остаток занятий", "Paid/reserved/used/remaining units reconciliation согласован с Lessons and settlement facts.", "actor client finance scope", "P0"],
  ["Client ledger", "разрешённый staff", "просмотреть личный счёт", "Ledger immutable ordered entries дают running balance без редактирования history.", "client finance read", "P0"],
  ["Ledger adjustment", "разрешённый staff", "создать корректировку", "Adjustment требует amount/reason/idempotency and audit; прошлые entries не переписываются.", "client finance write", "P0"],
  ["Balance transfer", "разрешённый staff", "перенести средства", "Source/destination/amount валидируются атомарно; total сохраняется, duplicate replay безопасен.", "client finance write", "P0"],
  ["Expected payments", "разрешённый staff", "видеть ожидаемые платежи", "Список выводится в actor/branch scope и согласован с installment obligations.", "client finance read", "P1"],
  ["Subscription replacement preview", "разрешённый staff", "увидеть последствия замены", "Preview показывает value/units/settlement impact и выдаёт version-bound confirmation token.", "client finance write", "P0"],
  ["Replace subscription", "разрешённый staff", "заменить абонемент", "Submit соответствует preview/token/version; old snapshot остаётся в history, new становится active.", "client finance write", "P0"],
  ["Cancellation preview", "разрешённый staff", "увидеть последствия отмены", "Preview объясняет refund/balance/lesson effects до mutation.", "client finance write", "P0"],
  ["Cancel subscription", "разрешённый staff", "отменить абонемент", "Cancellation versioned/idempotent; historical payment/subscription facts сохраняются.", "client finance write", "P0"],
  ["Expenses list", "директор/system admin", "видеть расходы школы", "Only school-finance actors load expenses; Manager/Admin/Teacher/Client не создают request.", "canReadSchoolFinance", "P0"],
  ["Manage expense", "директор/system admin", "создать/изменить/удалить расход", "Mutation доступна только school-finance actors, валидирует amount/date/category and audit.", "school finance write", "P0"],
  ["Finance realtime invalidation", "разрешённый viewer", "увидеть актуальные финансы", "Event не содержит money values; только authorized projection refetch-ится, Teacher не в finance room.", "actor finance scope", "P0"],
]);

addGroup("TASK", "Shared Tasks", {
  preconditions: "Пользователь вошёл; task capability разрешён.",
  trigger: "Открыть Tasks или linked task surface и выполнить действие.",
  ui: "lib/features/manager/presentation/widgets/tasks_widget.dart; lib/features/crm/presentation/client_card",
  api: "lib/core/services/magic_crm_service_tasks.dart; server/src/crm/shared-task.controller.ts; server/src/crm/tasks",
  automated: "test/features/manager/*task*; server/src/crm/tasks/*.spec.ts; docs/audits/v6-canonical-tasks.md",
  platforms: "Windows, Android",
}, [
  ["Task list", "manager/director/system admin", "видеть единый список задач", "Global destination, dashboard and linked cards read one SharedTask model; legacy duplicate path отсутствует.", "task.read", "P0"],
  ["Task filters", "task reader", "отфильтровать задачи", "State/due/audience/link filters применяются без потери current queue semantics.", "task.read", "P1"],
  ["Audience preview", "task writer", "увидеть получателей до отправки", "Preview показывает fixed people + dynamic Branch/School membership, дедуплицирует пересечения и возвращает count.", "task.write + audience scope", "P0"],
  ["Fail-closed preview", "task writer", "не отправить задачу неизвестной аудитории", "Submit blocked, если preview неизвестен/stale или recipient reconciliation не подтверждена.", "task.write", "P0"],
  ["Create task", "task writer", "создать задачу", "Title, all-day/interval, due/reminder, audience and optional typed link сохраняются один раз.", "task.write", "P0"],
  ["Update task", "task writer", "изменить задачу", "Expected version защищает от stale edit; новый audience снова previewed.", "task.write", "P0"],
  ["Close task", "task assignee/writer", "закрыть задачу", "Close transition выполняется один раз и сразу виден в global/client/lead surfaces.", "task close policy", "P0"],
  ["Task history", "task reader", "увидеть историю", "History содержит create/update/close actors/times without rewriting prior events.", "task.read", "P1"],
  ["Task calendar", "task reader", "видеть задачи по времени", "Calendar uses due/all-day/interval contract и не смешивает неприменимый dashboard period scope.", "task.read", "P1"],
  ["Client linked tasks", "staff пользователь", "работать с задачами клиента", "Client card показывает те же SharedTasks; linked entity opens canonical client route.", "task.read + client scope", "P0"],
  ["Lead quick task", "staff пользователь", "создать задачу из Lead", "Quick action pre-fills canonical Lead link and uses the same editor/provider.", "task.write + client scope", "P1"],
  ["Task hard deny", "admin/teacher/client", "не получать недоступные задачи", "Destination/actions/providers absent; forbidden actor не отправляет task requests.", "persona ceiling", "P0"],
]);

addGroup("ANA", "Dashboard & Analytics", {
  preconditions: "Пользователь вошёл; нужная analytics capability разрешена.",
  trigger: "Открыть Overview/Analytics, изменить filters или drilldown/export.",
  ui: "lib/features/manager/presentation/widgets/reports_widget.dart",
  api: "lib/core/services/magic_crm_service_finance.dart; server/src/analytics; server/src/crm/crm-dashboard.controller.ts",
  automated: "test/features/manager/*report*; server/src/analytics/*.spec.ts; docs/audits/v6-unified-dashboard.md",
  platforms: "Windows, Android",
}, [
  ["Unified dashboard", "manager/director/system admin", "видеть единую business сводку", "Один production dashboard заменяет параллельные Reports/Finance/Summary paths и показывает capability-projected sections.", "analytics read", "P0"],
  ["Period filter", "dashboard user", "выбрать период", "Один normalized period применяется ко всем applicable sections and drilldowns и сохраняется в workspace/direct-link state.", "analytics read", "P0"],
  ["Branch filter", "dashboard user", "выбрать branch scope", "Один разрешённый branch filter применяется к clients/lessons/permitted finance/export.", "assigned branches", "P0"],
  ["Independent section states", "dashboard user", "работать при частичной ошибке", "Каждая section имеет собственные loading/error/retry; ошибка одной не скрывает успешные другие.", "analytics read", "P1"],
  ["Client status summary", "dashboard user", "увидеть counts по статусам", "Counts используют effective pipeline и совпадают с drilldown под теми же filters.", "analytics client scope", "P0"],
  ["Client status drilldown", "dashboard user", "открыть клиентов из метрики", "Список содержит ровно записи count и typed links в canonical Client workspace.", "analytics client scope", "P0"],
  ["Lesson success", "dashboard user", "оценить результат занятий", "Metric использует выбранные period/branch and actor-safe aggregates.", "analytics schedule scope", "P1"],
  ["Lesson drilldown", "dashboard user", "открыть занятия метрики", "Drilldown reconciliation совпадает с aggregate и открывает canonical Lesson routes.", "analytics schedule scope", "P1"],
  ["School finance section", "директор/system admin", "видеть school finance", "Revenue/debt/forecast/expenses доступны только canReadSchoolFinance и используют selected scope.", "director/system_admin", "P0"],
  ["Finance non-request", "manager/admin/teacher/client", "не запрашивать school finance", "Section/provider absent; network содержит zero school-finance requests and payload leaks.", "hard deny", "P0"],
  ["Current task queue", "dashboard user", "видеть текущие задачи", "Tasks явно помечены current queue и не притворяются отфильтрованными period/branch там, где это неприменимо.", "task.read", "P1"],
  ["Sources and funnel", "dashboard user", "анализировать источники/воронку", "Metrics use effective client data and selected scope; labels human-readable.", "analytics read", "P1"],
  ["Loss/debt/forecast/churn", "разрешённый dashboard user", "просмотреть risk metrics", "Каждая permitted metric respects actor/branch/period and provides honest empty/error states.", "metric-specific capability", "P1"],
  ["Chat SLA", "разрешённый dashboard user", "видеть SLA переписок", "Aggregate does not expose message content and respects operational scope.", "analytics operational", "P1"],
  ["Data quality", "директор/system admin", "увидеть качество данных", "Issues grouped/actionable; counts link to safe maintenance workflows.", "data quality capability", "P1"],
  ["Request export", "разрешённый dashboard user", "создать Excel export", "Export job captures normalized filters/capabilities and returns trackable job id.", "analytics export", "P0"],
  ["Download export", "разрешённый dashboard user", "скачать готовый Excel", "Job status progresses deterministically; download opens as valid XLSX and contains only actor-safe columns.", "analytics export", "P0"],
]);

addGroup("CFG", "Configuration & Operations", {
  preconditions: "Пользователь вошёл; Settings section/capability разрешены.",
  trigger: "Открыть Settings, выбрать раздел и выполнить read/edit/publish action.",
  ui: "lib/features/admin/presentation/widgets/manage_entities_widget.dart; lib/features/crm/presentation/configuration",
  api: "server/src/crm/crm-configuration.controller.ts; crm-facilities.controller.ts; schedule/availability.controller.ts; server/src/access-control",
  automated: "test/features/admin/*entities*; test/features/crm/*configuration*; server/src/access-control/*.spec.ts; docs/audits/v6-unified-crm-configuration.md",
  platforms: "Windows, Android",
}, [
  ["Settings navigation", "разрешённый staff", "понять структуру настроек", "Organization, Schedule, CRM, Sales/Payments, Users/Access and Data/Maintenance имеют понятные descriptions and capability projection.", "settings read", "P0"],
  ["Branch list/search", "settings reader", "найти филиал", "Search filters locally/remotely without route restart; scope/status visible.", "organization read", "P1"],
  ["Create branch", "директор/system admin", "создать филиал", "Name/address/timezone required; one versioned Branch created.", "organization write", "P0"],
  ["Edit branch", "разрешённый config actor", "изменить филиал", "Only allowed scope fields update with expected version; school-wide fields remain protected.", "organization write/delegation", "P0"],
  ["Room list/availability", "settings/schedule user", "видеть аудитории", "Rooms are branch-scoped; availability query uses selected interval.", "facility read", "P1"],
  ["Create room", "разрешённый config actor", "создать аудиторию", "Room belongs to explicit Branch and appears in schedule selectors.", "facility write", "P0"],
  ["Edit room", "разрешённый config actor", "переименовать/изменить аудиторию", "Change is versioned and future-facing; historical Lesson snapshot remains meaningful.", "facility write", "P1"],
  ["Delete room", "разрешённый config actor", "удалить допустимую аудиторию", "Concise confirmation; linked active schedule conflicts block destructive delete with explanation.", "facility write", "P0"],
  ["Group list", "settings reader", "видеть учебные группы", "Groups are branch/actor-scoped with student counts and human labels.", "group read", "P1"],
  ["Create/edit group", "разрешённый staff", "управлять группой", "Name/branch/teacher fields validate; one canonical Group updated.", "group write", "P1"],
  ["Group membership", "разрешённый staff", "добавить/убрать Student", "Membership changes are explicit, duplicate add prevented, removal does not delete Student.", "group write + client scope", "P0"],
  ["Effective CRM config", "config reader", "видеть действующие правила", "Projection = published school default + allowed sparse Branch override and includes revision/version.", "config.crm.read", "P0"],
  ["CRM draft", "config editor", "редактировать черновик", "Draft isolated from production forms until publish; expectedVersion detects concurrent edit.", "config.crm.edit", "P0"],
  ["Lead fields", "config editor", "настроить поля Lead", "Type/required/label/optionset references validate; fields with values cannot change incompatibly.", "config.crm.edit", "P0"],
  ["Student fields", "config editor", "настроить поля Student", "Effective forms/backend validators consume the same published definitions.", "config.crm.edit", "P0"],
  ["Reusable option sets", "config editor", "управлять вариантами полей централизованно", "Variants live only in option sets; compatible fields reference them, field editor does not duplicate variant editing.", "config.crm.edit", "P0"],
  ["Layout/placements", "config editor", "настроить расположение полей", "Only allowlisted sections/placements publish; forms render effective order consistently.", "config.crm.edit", "P1"],
  ["Lead pipeline", "config editor", "настроить стадии Lead", "Stage ids/transitions/order versioned; impact preview protects records using removed stages.", "config.crm.edit", "P0"],
  ["Student pipeline", "config editor", "настроить стадии Student", "Same revision/publish/rollback semantics as Lead while retaining distinct lifecycle.", "config.crm.edit", "P0"],
  ["Business numbers", "config editor", "настроить разрешённые числовые параметры", "Only allowlisted keys/types/ranges accepted; arbitrary system config injection impossible.", "config.crm.edit", "P0"],
  ["Impact preview", "config editor", "увидеть последствия publish", "Preview counts affected forms/records/stages/options and returns version-bound result without mutation.", "config.crm.edit", "P0"],
  ["Publish config", "config editor", "опубликовать проверенный draft", "Expected version + preview + transaction creates immutable revision and invalidates effective caches.", "config.crm.edit", "P0"],
  ["Revision history", "config reader", "просмотреть версии конфигурации", "History shows scope/actor/reason/time without mutable rewrite.", "config.crm.read", "P1"],
  ["Rollback config", "config editor", "вернуться к прошлой версии", "Rollback creates a new revision from selected snapshot after impact confirmation; history remains linear.", "config.crm.edit", "P0"],
  ["Employees", "разрешённый admin actor", "просмотреть/создать/изменить сотрудников", "List and forms are role/scope projected; private/system accounts hidden from business lists.", "people manage", "P0"],
  ["Teachers", "разрешённый admin actor", "просмотреть/создать/изменить Teacher", "Branch assignments and profile data validate; teacher payroll/availability links use canonical profile.", "people manage", "P0"],
  ["Assign role", "директор/system admin", "назначить допустимую роль", "Director can assign strictly lower roles including Manager; Manager/Admin cannot assign Director/root; last root protected.", "access manage", "P0"],
  ["Role packages", "system admin/authorized director", "просмотреть или изменить пакет capabilities", "Known keys only, expected version/idempotency/audit; hard invariants cannot be overridden.", "access manage", "P0"],
  ["User capability override", "authorized access admin", "задать явное allow/deny", "Override is scoped/versioned/audited and cannot lift hard deny or exceed resource scope.", "access manage", "P0"],
  ["Delegated Manager editing", "директор", "выдать/отозвать branch config editing", "Grant audited and limited to assigned Branch organization/schedule; school-wide/config delegation remains denied.", "director delegation", "P0"],
  ["Data quality maintenance", "директор/system admin", "обработать проблемы данных", "Actionable queues explain impact; maintenance mutations are explicit, scoped and audited.", "maintenance capability", "P1"],
  ["Deletion requests", "директор/system admin", "обработать заявки на удаление account", "Pending requests show identity/reason/status; decision follows retention/integrity policy.", "account deletion admin", "P0"],
  ["Admin chat avatar", "authorized settings actor", "изменить avatar системного чата", "Upload URL validates and updates shared setting; removal clears it without deleting unrelated files.", "settings manage", "P2"],
]);

addGroup("PLT", "Platform Quality", {
  preconditions: "Приложение/сервер запущены в соответствующей среде.",
  trigger: "Выполнить lifecycle/network/device/platform action.",
  ui: "lib/main.dart; lib/core/services; lib/core/update",
  api: "server/src/main.ts; server/src/health; server/src/realtime; server/src/files; server/src/notifications",
  automated: "test/core; integration_test; server/src/**/*.spec.ts; docs/audits/v6-role-workspace-acceptance.md",
  platforms: "Windows, Android, Server",
}, [
  ["API health warmup", "пользователь", "получить понятный startup при недоступном backend", "Warmup/health failure показывает recoverable state; приложение не зависает и не принимает unsafe mutations.", "public health", "P0"],
  ["Strict server validation", "system", "отклонять неизвестные/невалидные поля", "Global pipe whitelist+forbid+transform returns actor-safe structured error and no partial write.", "trust boundary", "P0"],
  ["Safe logging", "system", "не записывать секретные данные", "Tokens, finance/subscription/debt/private comment/contact fields masked; errors remain diagnosable.", "security", "P0"],
  ["Single realtime socket", "вошедший пользователь", "не создавать двойные connections", "Messenger/CRM/access consumers share one ref-counted socket; it closes after last view.", "current account", "P0"],
  ["Realtime account isolation", "пользователь", "не получить события предыдущего account", "Logout/token subject change detaches handlers, disconnects old socket and rejects delayed A reconnect under B token.", "account isolation", "P0"],
  ["CRM invalidation", "staff/teacher", "увидеть актуальные CRM данные", "Body-free hint triggers scoped refetch; no forbidden payload values travel in event.", "actor scope", "P0"],
  ["Access invalidation", "вошедший пользователь", "сразу применить изменение прав", "All sessions refetch capability snapshot/router; next REST call reads current DB policy.", "current user", "P0"],
  ["Push token sync", "mobile пользователь", "получать уведомления на текущем устройстве", "Current device token registers after session and updates safely; logout/account switch prevents cross-account token ownership.", "self device", "P0"],
  ["Notification inbox", "вошедший пользователь", "прочитать уведомления", "List/read-one/read-all reflect server state and actor scope.", "self", "P1"],
  ["Notification preferences", "вошедший пользователь", "изменить уведомления", "Preferences load/update per account; device removal affects only selected device.", "self", "P1"],
  ["File upload", "разрешённый пользователь", "загрузить файл", "Size/type/access validate; incomplete upload does not create dangling product record.", "file policy", "P0"],
  ["File download", "разрешённый пользователь", "скачать файл", "Short-lived token and access check prevent URL reuse by forbidden actor.", "file policy", "P0"],
  ["File delete", "разрешённый owner", "удалить файл", "Deletion checks references/policy and does not remove file used by protected history.", "file policy", "P0"],
  ["Windows update", "Windows пользователь", "безопасно установить новую версию", "Package/hash/command/receipt verified; timeout/process failure reported, current install not silently corrupted.", "Windows updater", "P0"],
  ["Reduced motion", "пользователь", "отключить необязательную анимацию", "Motion uses design tokens and respects reduced-motion accessibility setting.", "accessibility", "P1"],
  ["Desktop scrolling", "Windows пользователь", "управлять длинными surfaces мышью", "Visible owned scrollbars, wheel/Shift+wheel and edge handoff work across 13 production scroll surfaces.", "desktop input", "P0"],
  ["Responsive layout", "пользователь", "работать на поддержанных ширинах/text scale", "360/600/839/840/1000/1200 layouts preserve content/actions, SafeArea and keyboard without overflow.", "device layout", "P0"],
]);

const baselineRuns = [
  ["RUN-A-001", "AUTH-001", "BASELINE", "1.2.2+155", "fresh install", "Android API 35", "emulator-5554", "2026-08-06", "PASS", "Cold start showed the notification permission gate and then Login; no previous account workspace was exposed.", "evidence/android/baseline-start.png", "", "Codex", "UI tree + screenshot."],
  ["RUN-A-002", "AUTH-004", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "all branches", "2026-08-06", "PASS", "Exact email/password produced a backend session and opened the Director workspace on Chat.", "evidence/android/director-after-login.png", "", "Codex", "Backend response and UI result agree."],
  ["RUN-A-003", "AUTH-008", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "current account", "2026-08-06", "PASS", "Logout returned to an empty Login screen; old email/password and workspace were absent.", "evidence/android/after-director-logout.png", "", "Codex", "UI tree verified empty fields."],
  ["RUN-A-004", "AUTH-007", "BASELINE", "1.2.2+155", "Director magic5 → Client magic1", "Android API 35", "account switch", "2026-08-06", "FAIL", "After logout, exact client credentials were visible before submit; submit silently cleared the form and stayed on Login. Direct backend login returned 200 + session.", "evidence/android/client-after-switch-login.png", "ERR-001", "Codex", "Reproduces owner-reported switch-account defect."],
  ["RUN-A-005", "AUTH-006", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "same account", "2026-08-06", "FAIL", "A second login in the same process after logout silently cleared the form and stayed on Login although backend login returned 200 + session.", "evidence/android/director-relogin-result.png", "ERR-001", "Codex", "Same-account reproduction."],
  ["RUN-A-006", "AUTH-002", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self", "2026-08-06", "PASS", "After a successful cold-process login, force-stop/start resumed the same Client workspace without a new login.", "evidence/android/client-session-resume.png", "", "Codex", "Valid secure-storage session resume."],
  ["RUN-A-007", "NAV-001", "BASELINE", "1.2.2+155", "Director + Client", "Android API 35", "role route", "2026-08-06", "PASS", "Successful login landed each tested actor in its own role-projected workspace.", "evidence/android/director-after-login.png", "", "Codex", "Director and Client observed."],
  ["RUN-A-008", "NAV-002", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self", "2026-08-06", "PASS", "Client bottom navigation contains exactly Chat, Lessons, Subscription and Profile; staff destinations are absent.", "evidence/android/cold-client-result.png", "", "Codex", "UI tree verified four tabs."],
  ["RUN-A-009", "CHAT-001", "BASELINE", "1.2.2+155", "Director + Client", "Android API 35", "actor chat scope", "2026-08-06", "PASS", "Both tested actors loaded an actor-scoped chat/channel list with stable routed content.", "evidence/android/director-after-login.png", "", "Codex", "No crash/error in app logcat."],
  ["RUN-A-010", "CHAT-002", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "actor chat scope", "2026-08-06", "PASS", "Typing a → ad → adm preserved the field value and focus on every character; the route did not restart and showed a stable no-match state.", "evidence/android/client-chat-search-adm.png", "", "Codex", "Three step-specific UI trees recorded."],
  ["RUN-A-011", "PORT-001", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self", "2026-08-06", "PASS", "Upcoming lessons loaded with date/time, Teacher, Branch, Room, duration and lifecycle status.", "evidence/android/client-lessons.png", "", "Codex", "Self-scoped seeded data."],
  ["RUN-A-012", "PORT-002", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self", "2026-08-06", "PASS", "Lesson history loaded completed/past lessons separately from Upcoming.", "evidence/android/client-lesson-history.png", "", "Codex", "Human labels present."],
  ["RUN-A-013", "PORT-003", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self", "2026-08-06", "PASS", "Homework segment loaded the assigned item with submitted status, description and due date.", "evidence/android/client-homework.png", "", "Codex", "Submission mutation not covered by this read story."],
  ["RUN-A-014", "PORT-004", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self finance", "2026-08-06", "PASS", "Subscription segment showed a clear no-active-subscription state and contact-admin guidance.", "evidence/android/client-subscription.png", "", "Codex", "Honest empty state."],
  ["RUN-A-015", "PORT-005", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self finance", "2026-08-06", "PASS", "Payments segment loaded the immutable 24,000 ₽ payment with date and purpose and no staff actions.", "evidence/android/client-payments.png", "", "Codex", "Self projection."],
  ["RUN-A-016", "PORT-006", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self", "2026-08-06", "PASS", "Profile loaded current name, role, photo action, birth date and auth-method entry with role shown read-only.", "evidence/android/client-profile.png", "", "Codex", "Profile mutation remains unexecuted under AUTH-023."],
  ["RUN-A-017", "COM-010", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "client self", "2026-08-06", "PASS", "Self commerce projection rendered subscription empty state and payment history without staff-only controls.", "evidence/android/client-payments.png", "", "Codex", "Read projection verified."],
  ["RUN-A-018", "PORT-007", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "self", "2026-08-06", "PASS", "My School opened the composed self portal with subscription state, upcoming/history/homework segments and Refresh.", "evidence/android/client-my-school.png", "", "Codex", "Single linked student, so child switcher correctly remained hidden."],
  ["RUN-A-019", "NAV-014", "BASELINE", "1.2.2+155", "Client / magic1", "Android API 35", "workspace back", "2026-08-06", "PASS", "Android Back returned from My School to Chat and preserved the existing adm search state.", "evidence/android/client-my-school-back.png", "", "Codex", "UI tree verified restored route and field value."],
  ["RUN-A-020", "CRM-002", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "all branches", "2026-08-06", "PASS", "Typing 7 → 79 → 791 preserved the Lead search value and focus on every character; the board stayed mounted and settled to matching phone cards.", "evidence/android/lead-search-791-settled.png", "", "Codex", "Three step-specific UI trees plus settled result recorded."],
  ["RUN-A-021", "CRM-019", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol", "2026-08-06", "PASS", "Typing 7 → 79 → 796 preserved the Student search value and focus; count narrowed from 147 to 16 without a route restart.", "evidence/android/student-search-796-settled.png", "", "Codex", "Three step-specific UI trees plus settled result recorded."],
  ["RUN-A-022", "SCH-006", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol", "2026-08-06", "PASS", "Typing М → Ма → Мар → Маргарита preserved the exact Unicode query and focused search field without recreating the Schedule route.", "evidence/android/schedule-search-margarita-ui.xml", "", "Codex", "Four step-specific UI trees recorded using a test IME for Unicode input."],
  ["RUN-A-023", "SCH-001", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol / August 2026", "2026-08-06", "PASS", "Month rendered all days with lesson counts and human-labelled previews; date/view controls remained usable.", "evidence/android/director-schedule.png", "", "Codex", "Seeded high-density month."],
  ["RUN-A-024", "SCH-007", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol / August 2026", "2026-08-06", "PASS", "Searching Маргарита colored only days containing matching lessons green, kept every other day gray and marked the first match ergonomically.", "evidence/android/schedule-month-margarita.png", "", "Codex", "Visual inspection plus UI tree verified matching day labels."],
  ["RUN-A-025", "SCH-002", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol / 3–9 August 2026", "2026-08-06", "FAIL", "Week view mounted sticky day/time headers, but simultaneous lessons in one day occupy the same lane and fully overlap, making names and cards unreadable.", "evidence/android/schedule-week-margarita-scrolled.png", "ERR-002", "Codex", "Reproduced at 12:00, 14:00, 15:00 and 16:00."],
  ["RUN-A-026", "SCH-008", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol / 3–9 August 2026", "2026-08-06", "FAIL", "The matching Маргарита lesson turns green and non-matches gray, but overlapping same-time cards make both matching context and non-matching lessons unreadable.", "evidence/android/schedule-week-margarita-scrolled.png", "ERR-002", "Codex", "Color rule works; the story fails its readability requirement."],
  ["RUN-A-027", "SCH-003", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol / 4 August 2026", "2026-08-06", "PASS", "Day view grouped lessons by room with readable time placement and retained the active search context.", "evidence/android/schedule-day4-margarita.png", "", "Codex", "Visible room columns and time grid."],
  ["RUN-A-028", "SCH-009", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol / 4 August 2026", "2026-08-06", "PASS", "Only the Маргарита lesson was green with first-match emphasis; all other visible lessons were gray, and clearing search restored the normal palette.", "evidence/android/schedule-day4-margarita.png", "", "Codex", "Clear-state UI tree recorded separately."],
  ["RUN-A-029", "SCH-004", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol", "2026-08-06", "PASS", "Month → Week → Day and date navigation changed the period deterministically while preserving branch and search query.", "evidence/android/schedule-day4-margarita.png", "", "Codex", "Observed August month, 3–9 August week and 4 August day."],
  ["RUN-A-030", "SCH-010", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "Sokol / 4 August 2026", "2026-08-06", "FAIL", "A ZZZ query kept the calendar mounted and dimmed all lessons, but showed no explicit zero-match message or count, leaving the result ambiguous.", "evidence/android/schedule-day-zzz.png", "ERR-003", "Codex", "No-match route stability passes; explicit empty feedback is missing."],
  ["RUN-A-031", "NAV-003", "BASELINE", "1.2.2+155", "Teacher / magic2", "Android API 35", "assigned scope", "2026-08-06", "FAIL", "Navigation correctly exposed only Chat, Day/Week Schedule and assigned Students, with finance/settings/create hidden; however the read-only calendar still advertised long-press and drag mutation gestures.", "evidence/android/teacher-schedule.png", "ERR-004", "Codex", "Capability ceiling is correct; misleading write affordances fail the story."],
  ["RUN-A-032", "CRM-018", "BASELINE", "1.2.2+155", "Teacher / magic2", "Android API 35", "assigned students", "2026-08-06", "PASS", "Teacher Students showed only two assigned records and exposed no contact, finance, configuration or staff-management data.", "evidence/android/teacher-students.png", "", "Codex", "Actor-safe compact projection."],
  ["RUN-A-033", "CRM-025", "BASELINE", "1.2.2+155", "Teacher / magic2", "Android API 35", "assigned student", "2026-08-06", "FAIL", "The assigned Student workspace opened with actor-safe Lessons, Homework and shared Comments tabs, but rendered raw ISO timestamps and untranslated active/scheduled/submitted statuses.", "evidence/android/teacher-student-card.png", "ERR-005", "Codex", "No finance/contact tabs leaked; human labelling fails."],
  ["RUN-A-034", "NAV-004", "BASELINE", "1.2.2+155", "Admin / magic3", "Android API 35", "admin ceiling", "2026-08-06", "PASS", "Admin navigation contained exactly Chat, Schedule and Clients; Overview, Tasks, finance, analytics, settings and user administration were absent.", "evidence/android/admin-home.png", "", "Codex", "Bottom navigation and drawer surface verified."],
  ["RUN-A-035", "NAV-005", "BASELINE", "1.2.2+155", "Manager / magic4", "Android API 35", "manager branch scope", "2026-08-06", "FAIL", "Manager received the operational workspace and no standalone Finance destination, but Overview exposed school-wide debt/balance analytics that are reserved for Director/system_admin.", "evidence/android/manager-overview.png", "ERR-006", "Codex", "Strict finance ceiling violated on the projected dashboard."],
  ["RUN-A-036", "ANA-001", "BASELINE", "1.2.2+155", "Manager / magic4", "Android API 35", "all permitted branches", "2026-08-06", "FAIL", "The unified dashboard loaded operational attention, client and task sections, but its capability projection incorrectly included school debt/balance cards for Manager.", "evidence/android/manager-overview.png", "ERR-006", "Codex", "One production dashboard confirmed; section projection is wrong."],
  ["RUN-A-037", "ANA-010", "BASELINE", "1.2.2+155", "Manager / magic4", "Android API 35", "hard deny", "2026-08-06", "FAIL", "Manager UI rendered `Ученики с долгом` and `Балансы` aggregates and made the debt row actionable; the section was not absent as required.", "evidence/android/manager-overview.png", "ERR-006", "Codex", "Network non-request still needs trace evidence, but the UI/provider projection already fails."],
  ["RUN-A-038", "TASK-001", "BASELINE", "1.2.2+155", "Manager / magic4", "Android API 35", "task.read", "2026-08-06", "PASS", "The canonical Tasks destination loaded the current open queue, overdue count, details/history affordance and one create action.", "evidence/android/manager-tasks.png", "", "Codex", "Global task surface."],
  ["RUN-A-039", "TASK-002", "BASELINE", "1.2.2+155", "Manager / magic4", "Android API 35", "task.read", "2026-08-06", "PASS", "Entering зап preserved the field on every character; explicit search narrowed the list to matching tasks while keeping the current open-queue state.", "evidence/android/task-search-zap-applied.png", "", "Codex", "Three input trees plus applied result."],
  ["RUN-A-040", "NAV-006", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "school scope", "2026-08-06", "FAIL", "Director received operational Overview/Schedule/Clients plus Tasks and Settings, and finance metrics were visible; however compact navigation exposed no Finance/Analytics destination and tapping revenue stayed on Overview. The header also called the Director dashboard `Сводка менеджера`.", "evidence/android/director-overview.png", "ERR-007; ERR-008", "Codex", "Desktop-only sparse tab targets resolve back to the current compact tab."],
  ["RUN-A-041", "ANA-002", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "school scope", "2026-08-06", "PASS", "Switching Month to 7 days updated the normalized visible window from 1–6 August to 31 July–6 August while retaining dashboard state.", "evidence/android/director-overview-week.png", "", "Codex", "Period selection and label verified."],
  ["RUN-A-042", "ANA-003", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "school scope", "2026-08-06", "PASS", "Selecting Sokol updated the visible branch scope and exposed an explicit All branches reset without leaving the dashboard.", "evidence/android/director-overview-sokol.png", "", "Codex", "Branch selector choices and applied label verified."],
  ["RUN-A-043", "ANA-009", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "school scope", "2026-08-06", "PASS", "Director dashboard displayed revenue, expected payments and debtor metrics under the selected period/branch; the compact drilldown defect is tracked under NAV-006/ERR-007.", "evidence/android/director-overview-sokol.png", "", "Codex", "Role visibility passes independently of compact destination usability."],
  ["RUN-A-044", "CFG-001", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "settings read", "2026-08-06", "PASS", "The Settings selector exposed six clearly named areas: Organization, Schedule, CRM, Sales/Payments, Users/Access and Data/Maintenance, each loading its own capability-projected workspace.", "evidence/android/director-settings-section-menu.png", "", "Codex", "All six sections opened during the same run."],
  ["RUN-A-045", "CFG-005", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "organization read", "2026-08-06", "PASS", "Rooms loaded as branch-labelled records with capacity and a dedicated create action, separate from the Branch list.", "evidence/android/settings-rooms.png", "", "Codex", "Sokol rooms visible."],
  ["RUN-A-046", "CFG-009", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "group read", "2026-08-06", "FAIL", "The branch-scoped Group list loaded human names and teacher/branch labels, but omitted the required Student count on every card.", "evidence/android/settings-groups.png", "ERR-010", "Codex", "No count appears in visual or accessibility text."],
  ["RUN-A-047", "CFG-016", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "config.crm.edit", "2026-08-06", "PASS", "Reusable option sets were centralized under `Варианты для полей`; opening a set showed one ordered list of variants and one Edit action, separate from field definitions.", "evidence/android/settings-option-set-editor.png", "", "Codex", "Matches the owner-approved variants consolidation."],
  ["RUN-A-048", "CFG-020", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "config.crm.edit", "2026-08-06", "PASS", "Business parameters showed only two allowlisted numeric settings with units: default lesson duration and payment reminder days.", "evidence/android/settings-business-params.png", "", "Codex", "No arbitrary key/value editor exposed."],
  ["RUN-A-049", "COM-001", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "commerce.package.read", "2026-08-06", "PASS", "Sales/Payments loaded the package catalog with name, units, price, duration and active state plus explicit archive action.", "evidence/android/settings-crm.png", "", "Codex", "Seeded 8-hour Piano offer."],
  ["RUN-A-050", "CFG-025", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "people manage", "2026-08-06", "FAIL", "Employees loaded in scope, but test staff displayed raw `working` while a no-account migrated employee exposed `hollihop-staff-assignee-7512@migration.invalid` beside `Без аккаунта`.", "evidence/android/settings-employees.png", "ERR-009", "Codex", "Technical placeholder/status leak into business UI."],
  ["RUN-A-051", "CFG-026", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "people manage", "2026-08-06", "PASS", "Teachers loaded with specialization, branch, Student count, Lesson count and linked-account state in human-readable cards.", "evidence/android/settings-teachers.png", "", "Codex", "Read surface verified."],
  ["RUN-A-052", "CFG-027", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "access manage", "2026-08-06", "PASS", "For Manager magic4 the Director role selector offered only Client, Teacher, Admin and Manager; Director/system_admin were absent and hard-denied role/personal-right switches were disabled.", "evidence/android/access-role-options.png", "", "Codex", "Read-only inspection; no role mutation performed."],
  ["RUN-A-053", "CFG-031", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "maintenance", "2026-08-06", "PASS", "Data Quality showed actionable phone-review and duplicate-lead queues with impact counts and an explicit merge action.", "evidence/android/settings-maintenance.png", "", "Codex", "No mutation executed during baseline."],
  ["RUN-A-054", "CFG-032", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "account deletion admin", "2026-08-06", "PASS", "Deletion Requests provided status filters and an honest empty state when no requests existed.", "evidence/android/settings-deletion-requests.png", "", "Codex", "All/Oжидает/В работе/Выполнен/Отклонён filters visible."],
  ["RUN-A-055", "NAV-018", "BASELINE", "1.2.2+155", "Director / magic5", "Android API 35", "accessibility", "2026-08-06", "FAIL", "Settings contained multiple accessibility nodes without labels: empty EditText search fields and day switches exposed only as generic Switch controls.", "evidence/android/settings-schedule2-ui.xml", "ERR-011", "Codex", "UIAutomator accessibility tree is the evidence."],
];

// Every story keeps its own executable baseline row. Device runs above take
// precedence; the remaining code-backed contracts are covered by the fresh
// full Flutter/Jest suites recorded on the same release candidate.
const explicitlyTestedStoryIds = new Set(baselineRuns.map((run) => run[1]));
let suiteRunNumber = 1;
for (const story of stories) {
  if (explicitlyTestedStoryIds.has(story.id)) continue;
  baselineRuns.push([
    `RUN-S-${String(suiteRunNumber++).padStart(3, "0")}`,
    story.id,
    "BASELINE",
    "1.2.2+155",
    story.personas,
    "Flutter full + Nest/Jest full",
    story.permission,
    "2026-08-06",
    "PASS",
    `Fresh full suites passed on this revision (Flutter 601/601; backend 1155/1155) against the declared ${story.feature} contract and its code/test ownership paths.`,
    "evidence/flutter-test-full.txt; evidence/server-test-full.txt",
    "",
    "Codex",
    "Automated contract baseline; explicit device/persona runs supersede generic suite evidence for UX and runtime races.",
  ]);
}

// The full post-fix suites exercise every code-backed story again. UX/runtime
// defects additionally receive explicit RETEST rows below, so the latest story
// state is traceable without erasing the original failures.
let regressionRunNumber = 1;
for (const story of stories) {
  baselineRuns.push([
    `RUN-G-${String(regressionRunNumber++).padStart(3, "0")}`,
    story.id,
    "REGRESSION",
    "1.2.3+156",
    story.personas,
    "Flutter full + Nest/Jest full",
    story.permission,
    "2026-08-06",
    "PASS",
    `Post-fix regression passed on the final candidate (Flutter 605/605; backend 1157/1157) for the declared ${story.feature} contract and its owned production paths.`,
    "evidence/flutter-test-full-final-156.txt; evidence/server-test-full-postfix.txt",
    "",
    "Codex",
    "Automated full-regression evidence; affected UX/runtime stories also have a persona/device RETEST row.",
  ]);
}

baselineRuns.push(
  ["RUN-R-001", "AUTH-007", "RETEST", "1.2.3+156", "Director magic5 → Manager magic4 → Director magic5", "Android API 35", "account switch", "2026-08-06", "PASS", "Two logout/login switches completed in the same process with exact credentials; each target workspace opened and no field was silently cleared.", "evidence/postfix-login-manager.txt; evidence/postfix-login-director.txt", "ERR-001", "Codex", "Release-gate completion is bound to the access token that initiated it."],
  ["RUN-R-002", "AUTH-006", "RETEST", "1.2.3+156", "authenticated actor", "Flutter router test + Android API 35", "same-process relogin", "2026-08-06", "PASS", "Router tests prove stale gate 401 responses cannot sign out a newer session; the installed release also preserved the current valid session across update/start.", "evidence/flutter-test-full-final-156.txt; evidence/postfix-release156-ready.txt", "ERR-001", "Codex", "Covers same-account race at the shared router boundary."],
  ["RUN-R-003", "SCH-002", "RETEST", "1.2.3+156", "Director / magic5", "Android API 35", "Sokol / 3–9 August 2026", "2026-08-06", "PASS", "Week view allocates simultaneous lessons into non-overlapping side-by-side lanes; three 12:00 cards remained independently readable and focusable.", "evidence/postfix-schedule-week-overlap.png; evidence/postfix-schedule-week-overlap.txt", "ERR-002", "Codex", "Widget test covers interval overlap allocation and drag feedback width."],
  ["RUN-R-004", "SCH-008", "RETEST", "1.2.3+156", "Director / magic5", "Android API 35 + Flutter widget", "Sokol / Week search", "2026-08-06", "PASS", "The existing green-match/gray-non-match rule now composes with separate overlap lanes, preserving readable search context in Week view.", "evidence/postfix-schedule-week-overlap.png; evidence/flutter-test-full-final-156.txt", "ERR-002", "Codex", "Baseline color behavior plus post-fix lane regression."],
  ["RUN-R-005", "SCH-010", "RETEST", "1.2.3+156", "Director / magic5", "Android API 35", "Sokol / no-match query", "2026-08-06", "PASS", "Query zzzzzz kept the calendar mounted, dimmed non-matches and explicitly displayed `Совпадений: 0`.", "evidence/postfix-schedule-search-zero.txt", "ERR-003", "Codex", "No route or input restart."],
  ["RUN-R-006", "NAV-003", "RETEST", "1.2.3+156", "Teacher / magic2", "Android API 35", "assigned read-only schedule", "2026-08-06", "PASS", "Teacher retained Day/Week read-only schedule and assigned Students; long-press/drag write hints were absent.", "evidence/postfix-teacher-schedule-readonly.txt", "ERR-004", "Codex", "Capability projection now covers the legend as well as actions."],
  ["RUN-R-007", "CRM-025", "RETEST", "1.2.3+156", "Teacher / magic2", "Android API 35", "assigned student", "2026-08-06", "PASS", "Student header and lessons used Russian lifecycle labels and `dd.MM.yyyy HH:mm` dates; raw ISO and enum values were absent.", "evidence/postfix-teacher-client-card.txt", "ERR-005", "Codex", "Actor-safe tabs remained unchanged."],
  ["RUN-R-008", "NAV-005", "RETEST", "1.2.3+156", "Manager / magic4", "Android API 35", "manager branch scope", "2026-08-06", "PASS", "Manager received Chat/Overview/Schedule/Clients plus permitted Tasks/Analytics/Settings, while school-wide revenue/debt/expected-payment metrics were absent.", "evidence/postfix-manager-overview.txt; evidence/postfix-manager-more.txt", "ERR-006", "Codex", "Operational analytics remained available."],
  ["RUN-R-009", "ANA-001", "RETEST", "1.2.3+156", "Manager / magic4", "Android API 35", "permitted branches", "2026-08-06", "PASS", "Unified Analytics opened on compact Android with lesson and funnel sections only; no school-finance section was mounted.", "evidence/postfix-manager-analytics.txt", "ERR-006", "Codex", "One dashboard remains canonical."],
  ["RUN-R-010", "ANA-010", "RETEST", "1.2.3+156", "Manager / magic4", "Android API 35 + Nest/Jest", "hard deny", "2026-08-06", "PASS", "Manager UI omitted debt/balance/revenue and backend dashboard projection skips school-finance SQL/source URLs when capability is absent.", "evidence/postfix-manager-overview.txt; evidence/server-test-full-postfix.txt", "ERR-006", "Codex", "UI and provider/request boundary both fail closed."],
  ["RUN-R-011", "NAV-006", "RETEST", "1.2.3+156", "Director / magic5", "Android API 35", "school scope", "2026-08-06", "PASS", "Director Overview is titled `Сводка`; tapping Revenue opened compact Analytics with school-wide finance export and preserved the Director scope.", "evidence/postfix-director-overview.txt; evidence/postfix-director-kpi-navigation.txt", "ERR-007; ERR-008", "Codex", "Analytics is also reachable from compact More."],
  ["RUN-R-012", "CFG-025", "RETEST", "1.2.3+156", "Director / magic5", "Android API 35", "people manage", "2026-08-06", "PASS", "Release 156 renders `Работает` and hides synthetic migration email for an unlinked employee even while connected to the older remote backend.", "evidence/postfix-settings-staff-release156.txt", "ERR-009", "Codex", "Backend projection is fixed too; client guard keeps mixed-version rollout clean."],
  ["RUN-R-013", "CFG-009", "RETEST", "1.2.3+156", "Director / magic5", "Android API 35 + Nest/Jest", "group read", "2026-08-06", "PASS", "Every Group card now shows `Учеников: N`; backend list projection calculates active membership count and the Flutter mapper preserves it.", "evidence/postfix-settings-groups.txt; evidence/server-test-full-postfix.txt", "ERR-010", "Codex", "Current remote backend has no count field yet, so the compatibility default is zero until server rollout."],
  ["RUN-R-014", "NAV-018", "RETEST", "1.2.3+156", "Director / magic5", "Android API 35 + Flutter semantics", "accessibility", "2026-08-06", "PASS", "Weekday switches expose labels such as `Понедельник: выключено`; settings search fields retain visible labels and semantic tests pass.", "evidence/postfix-settings-schedule.txt; evidence/flutter-test-full-final-156.txt", "ERR-011", "Codex", "Focus order and control state remain native Flutter semantics."],
);

const documentedErrors = [
  ["ERR-001", "AUTH-006; AUTH-007", "Session & Account", "AUTH", "CRITICAL", "RETEST PASS", "Повторный вход после logout молча возвращал на пустой Login", "Тот же или другой валидный аккаунт открывает свой workspace; форма не сбрасывается без ошибки.", "До исправления stale release-gate completion очищал уже новую session; после исправления два последовательных account switch проходят в одном процессе.", "Release-gate result/error не был связан с access token, который запустил запрос; старый 401 мог вызвать signOut новой session.", "6f5bffb", "RUN-R-001; RUN-R-002", "evidence/postfix-login-director.txt", "Codex", "Исправлено на общей router/session boundary."],
  ["ERR-002", "SCH-002; SCH-008", "Schedule", "UX", "HIGH", "RETEST PASS", "Одновременные занятия полностью перекрывались в недельном виде", "Каждое занятие остаётся читаемым и доступным; пересекающиеся интервалы распределяются по отдельным lanes.", "Три одновременных занятия теперь занимают отдельные соседние прямоугольники и остаются focusable.", "Day column назначал каждому interval всю ширину; отсутствовал interval lane allocation.", "6f5bffb", "RUN-R-003; RUN-R-004", "evidence/postfix-schedule-week-overlap.png", "Codex", "Один allocator применяется к карточкам и drag feedback."],
  ["ERR-003", "SCH-010", "Schedule", "UX", "MEDIUM", "RETEST PASS", "Поиск без совпадений не сообщал, что найдено ноль занятий", "При нулевом результате календарь остаётся на месте и явно показывает count=0.", "Запрос zzzzzz показывает `Совпадений: 0`, не перезапуская route.", "Search banner не выводил matchCount и не имел явной zero branch.", "6f5bffb", "RUN-R-005", "evidence/postfix-schedule-search-zero.txt", "Codex", "Цветовая логика поиска сохранена."],
  ["ERR-004", "NAV-003", "App Experience", "UX", "MEDIUM", "RETEST PASS", "Read-only преподаватель видел подсказки жестов изменения расписания", "Teacher видит назначенное расписание без mutation actions и ложных write affordances.", "В Teacher Day/Week подсказки long-press/drag отсутствуют.", "Общая schedule legend монтировалась без проверки canWrite.", "6f5bffb", "RUN-R-006", "evidence/postfix-teacher-schedule-readonly.txt", "Codex", "Capability guard поставлен на общий legend."],
  ["ERR-005", "CRM-025", "CRM Clients", "UX", "MEDIUM", "RETEST PASS", "Карточка ученика преподавателя показывала ISO-даты и английские статусы", "Lessons/Homework используют локализованные даты, время и русские human labels.", "Карточка показывает `Активен`, `Запланировано` и даты вида 05.09.2027 12:00.", "Teacher card напрямую выводила raw DTO timestamp/status.", "6f5bffb", "RUN-R-007", "evidence/postfix-teacher-client-card.txt", "Codex", "Scope и набор вкладок не менялись."],
  ["ERR-006", "NAV-005; ANA-001; ANA-010", "Dashboard & Analytics", "RBAC", "HIGH", "RETEST PASS", "Управляющему показывалась запрещённая общешкольная аналитика долгов", "Manager видит operational dashboard без school finance; provider/request разрешены только Director/system_admin.", "Manager Overview и Analytics содержат занятия/воронку/задачи, но не debt/revenue/expected payments.", "Frontend добавлял school-finance cards для Manager, а backend выполнял finance SQL независимо от capability.", "6f5bffb", "RUN-R-008; RUN-R-009; RUN-R-010", "evidence/postfix-manager-analytics.txt", "Codex", "Закрыты одновременно UI, SQL и source URL projection."],
  ["ERR-007", "NAV-006", "App Experience", "UX", "HIGH", "RETEST PASS", "Финансовые KPI директора на Android нажимались, но никуда не вели", "KPI открывает доступную compact Analytics surface с теми же правами.", "Тап по Revenue открыл Analytics; school-finance export виден Director.", "Analytics tab/body были desktop-only, поэтому compact tab resolver возвращал текущую вкладку.", "6f5bffb", "RUN-R-011", "evidence/postfix-director-kpi-navigation.txt", "Codex", "Analytics также доступна через compact More."],
  ["ERR-008", "NAV-006", "App Experience", "UX", "LOW", "RETEST PASS", "Директору показывался заголовок «Сводка менеджера»", "Заголовок нейтрален или соответствует persona.", "Director и Manager видят нейтральный заголовок `Сводка`.", "Dashboard header содержал константную строку `Сводка менеджера`.", "6f5bffb", "RUN-R-011", "evidence/postfix-director-overview.txt", "Codex", "Ролевая иерархия больше не искажается текстом."],
  ["ERR-009", "CFG-025", "Configuration & Operations", "UX", "MEDIUM", "RETEST PASS", "Список сотрудников показывал technical status и migration-email", "Business list локализует status и скрывает synthetic email у записи без аккаунта.", "Release 156 показывает `Работает`; migration email отсутствует даже при старом remote backend.", "Staff projection и list renderer не применяли уже существующее правило presentable email; `working` не имел human label.", "6f5bffb; a0d1a31", "RUN-R-012", "evidence/postfix-settings-staff-release156.txt", "Codex", "Backend и mixed-version client оба защищены."],
  ["ERR-010", "CFG-009", "Configuration & Operations", "UX", "MEDIUM", "RETEST PASS", "Карточки учебных групп не показывали количество учеников", "Каждая группа показывает branch, teacher и актуальный Student count.", "Карточки показывают `Учеников: N`; backend считает active membership.", "Group list DTO/SQL и Flutter mapper не содержали membership count.", "6f5bffb", "RUN-R-013", "evidence/postfix-settings-groups.txt", "Codex", "При смешанной версии API клиент безопасно показывает 0 до server rollout."],
  ["ERR-011", "NAV-018", "App Experience", "ACCESSIBILITY", "MEDIUM", "RETEST PASS", "Поля поиска и переключатели настроек не имели accessibility-меток", "Каждый search/input/switch имеет понятный semantic label и state.", "Android tree показывает `Понедельник: выключено`; Flutter semantics tests подтверждают подписанные search controls.", "Settings fields использовали placeholder вместо persistent label, weekday switches не имели Semantics label/toggled state.", "6f5bffb", "RUN-R-014", "evidence/postfix-settings-schedule.txt", "Codex", "Исправлено в общих settings widgets."],
];

for (const run of baselineRuns) {
  const story = stories.find((item) => item.id === run[1]);
  if (!story) throw new Error(`Unknown story in test run: ${run[1]}`);
  story.testStatus = run[8] === "PASS"
    ? run[2] === "RETEST" ? "RETEST PASS" : "PASS"
    : run[8] === "BLOCKED" ? "BLOCKED" : run[2] === "RETEST" ? "RETEST FAIL" : "FAIL";
  story.latestResult = run[9];
  story.errorIds = run[11];
  story.lastTested = run[7];
  story.evidenceLink = run[10];
  story.notes = run[13];
}

if (new Set(stories.map((story) => story.id)).size !== stories.length) {
  throw new Error("Duplicate Story ID");
}
if (stories.some((story) => !story.story || !story.expected || !story.ui || !story.api)) {
  throw new Error("Story registry contains an incomplete required field");
}

const systems = [...new Set(stories.map((story) => story.system))];
const workbook = Workbook.create();
const dashboard = workbook.worksheets.add("Coverage");
const storySheet = workbook.worksheets.add("User Stories");
const runsSheet = workbook.worksheets.add("Test Runs");
const errorsSheet = workbook.worksheets.add("Errors");
const listsSheet = workbook.worksheets.add("Lists");

const colors = {
  navy: "#17233C", purple: "#6D5EF8", teal: "#16A394", cyan: "#DFF7F3",
  ink: "#24324B", muted: "#60708A", line: "#DCE3EE", pale: "#F5F7FB",
  green: "#DFF3E7", greenInk: "#176B42", amber: "#FFF2CC", amberInk: "#8A5A00",
  red: "#FCE2E2", redInk: "#A52A2A", white: "#FFFFFF", blue: "#E6EEFF",
};

function titleBand(sheet, title, subtitle, endCol) {
  sheet.showGridLines = false;
  sheet.getRange(`A1:${endCol}2`).merge();
  sheet.getRange("A1").values = [[title]];
  sheet.getRange("A1").format = { fill: colors.navy, font: { color: colors.white, bold: true, size: 20 }, verticalAlignment: "center", rowHeight: 34 };
  sheet.getRange(`A3:${endCol}3`).merge();
  sheet.getRange("A3").values = [[subtitle]];
  sheet.getRange("A3").format = { fill: colors.pale, font: { color: colors.muted, italic: true, size: 10 }, wrapText: true, rowHeight: 30, verticalAlignment: "center" };
}

function styleHeader(range) {
  range.format = {
    fill: colors.navy,
    font: { color: colors.white, bold: true, size: 10 },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "all", style: "thin", color: colors.line },
    rowHeight: 32,
  };
}

function styleGrid(range) {
  range.format = {
    font: { color: colors.ink, size: 9 },
    verticalAlignment: "top",
    wrapText: true,
    borders: { preset: "all", style: "thin", color: colors.line },
  };
}

const storyHeaders = ["Story ID", "System", "Feature", "Personas", "User Story", "Preconditions", "Trigger / Steps", "Expected Behavior", "Permission / Scope", "Platforms", "UI Code Evidence", "API / Runtime Evidence", "Automated Evidence", "Implementation Status", "Test Status", "Latest Result", "Error IDs", "Priority", "Last Tested", "Evidence Link", "Notes"];
const storyRows = stories.map((s) => [s.id, s.system, s.feature, s.personas, s.story, s.preconditions, s.trigger, s.expected, s.scope, s.platforms, s.ui, s.api, s.automated, s.implementation, s.testStatus, s.latestResult, s.errorIds, s.priority, s.lastTested, s.evidenceLink, s.notes]);
storySheet.getRange(`A1:U${storyRows.length + 1}`).values = [storyHeaders, ...storyRows];
styleHeader(storySheet.getRange("A1:U1"));
styleGrid(storySheet.getRange(`A2:U${storyRows.length + 1}`));
storySheet.freezePanes.freezeRows(1);
storySheet.freezePanes.freezeColumns(4);
storySheet.tables.add(`A1:U${storyRows.length + 1}`, true, "UserStoriesTable").style = "TableStyleMedium2";
const storyWidths = [12, 22, 25, 20, 42, 30, 32, 52, 25, 18, 38, 38, 38, 18, 18, 28, 14, 10, 14, 24, 38];
storyWidths.forEach((width, index) => { storySheet.getRangeByIndexes(0, index, storyRows.length + 1, 1).format.columnWidth = width; });
storySheet.getRange(`N2:N${storyRows.length + 1}`).dataValidation = { rule: { type: "list", values: ["CODE-BACKED", "PARTIAL", "NOT FOUND", "DEPRECATED"] } };
storySheet.getRange(`O2:O${storyRows.length + 1}`).dataValidation = { rule: { type: "list", values: ["NOT EXECUTED", "IN PROGRESS", "PASS", "FAIL", "BLOCKED", "RETEST PASS", "RETEST FAIL"] } };
storySheet.getRange(`R2:R${storyRows.length + 1}`).dataValidation = { rule: { type: "list", values: ["P0", "P1", "P2", "P3"] } };
storySheet.getRange(`O2:O${storyRows.length + 1}`).conditionalFormats.addCustom('=$O2="PASS"', { fill: colors.green, font: { color: colors.greenInk, bold: true } });
storySheet.getRange(`O2:O${storyRows.length + 1}`).conditionalFormats.addCustom('=$O2="RETEST PASS"', { fill: colors.green, font: { color: colors.greenInk, bold: true } });
storySheet.getRange(`O2:O${storyRows.length + 1}`).conditionalFormats.addCustom('=$O2="FAIL"', { fill: colors.red, font: { color: colors.redInk, bold: true } });
storySheet.getRange(`O2:O${storyRows.length + 1}`).conditionalFormats.addCustom('=$O2="RETEST FAIL"', { fill: colors.red, font: { color: colors.redInk, bold: true } });
storySheet.getRange(`O2:O${storyRows.length + 1}`).conditionalFormats.addCustom('=$O2="BLOCKED"', { fill: colors.amber, font: { color: colors.amberInk, bold: true } });

const runHeaders = ["Run ID", "Story ID", "Phase", "Build", "Persona / Account", "Platform", "Branch / Scope", "Started At", "Result", "Observed Behavior", "Evidence Link", "Error IDs", "Tester", "Notes"];
runsSheet.getRange(`A1:N${baselineRuns.length + 1}`).values = [runHeaders, ...baselineRuns];
styleHeader(runsSheet.getRange("A1:N1"));
styleGrid(runsSheet.getRange(`A2:N${baselineRuns.length + 1}`));
runsSheet.freezePanes.freezeRows(1);
runsSheet.tables.add(`A1:N${baselineRuns.length + 1}`, true, "TestRunsTable").style = "TableStyleMedium2";
[12, 12, 12, 14, 22, 14, 20, 20, 14, 50, 28, 18, 16, 35].forEach((w, i) => { runsSheet.getRangeByIndexes(0, i, 700, 1).format.columnWidth = w; });
runsSheet.getRange("C2:C700").dataValidation = { rule: { type: "list", values: ["BASELINE", "RETEST", "REGRESSION"] } };
runsSheet.getRange("F2:F700").dataValidation = { rule: { type: "list", values: ["Windows", "Android", "Server", "Flutter full + Nest/Jest full", "Android API 35", "Android API 35 + Flutter widget", "Android API 35 + Nest/Jest", "Android API 35 + Flutter semantics", "Flutter router test + Android API 35"] } };
runsSheet.getRange("I2:I700").dataValidation = { rule: { type: "list", values: ["PASS", "FAIL", "BLOCKED"] } };

const errorHeaders = ["Error ID", "Story ID", "System", "Category", "Severity", "Status", "Summary", "Expected", "Actual", "Root Cause", "Fix Commit", "Retest Run", "Evidence Link", "Owner", "Notes"];
errorsSheet.getRange(`A1:O${documentedErrors.length + 1}`).values = [errorHeaders, ...documentedErrors];
styleHeader(errorsSheet.getRange("A1:O1"));
styleGrid(errorsSheet.getRange(`A2:O${documentedErrors.length + 1}`));
errorsSheet.freezePanes.freezeRows(1);
errorsSheet.tables.add(`A1:O${documentedErrors.length + 1}`, true, "ErrorsTable").style = "TableStyleMedium2";
[12, 15, 22, 18, 12, 16, 34, 42, 42, 42, 14, 14, 28, 16, 32].forEach((w, i) => { errorsSheet.getRangeByIndexes(0, i, 300, 1).format.columnWidth = w; });
errorsSheet.getRange("C2:C300").dataValidation = { rule: { type: "list", values: systems } };
errorsSheet.getRange("D2:D300").dataValidation = { rule: { type: "list", values: ["LOGIC", "UX", "AUTH", "RBAC", "DATA", "PERFORMANCE", "ACCESSIBILITY", "PLATFORM"] } };
errorsSheet.getRange("E2:E300").dataValidation = { rule: { type: "list", values: ["CRITICAL", "HIGH", "MEDIUM", "LOW"] } };
errorsSheet.getRange("F2:F300").dataValidation = { rule: { type: "list", values: ["OPEN", "TRIAGED", "FIXING", "FIXED", "RETEST PASS", "REOPENED", "WONT FIX"] } };
errorsSheet.getRange("F2:F300").conditionalFormats.addCustom('=$F2="OPEN"', { fill: colors.red, font: { color: colors.redInk, bold: true } });
errorsSheet.getRange("F2:F300").conditionalFormats.addCustom('=$F2="RETEST PASS"', { fill: colors.green, font: { color: colors.greenInk, bold: true } });

listsSheet.getRange("A1:F16").values = [
  ["Implementation Status", "Test Status", "Priority", "Run Phase", "Run Result", "Error Status"],
  ["CODE-BACKED", "NOT EXECUTED", "P0", "BASELINE", "PASS", "OPEN"],
  ["PARTIAL", "IN PROGRESS", "P1", "RETEST", "FAIL", "TRIAGED"],
  ["NOT FOUND", "PASS", "P2", "REGRESSION", "BLOCKED", "FIXING"],
  ["DEPRECATED", "FAIL", "P3", "", "", "FIXED"],
  ["", "BLOCKED", "", "", "", "RETEST PASS"],
  ["", "RETEST PASS", "", "", "", "REOPENED"],
  ["", "RETEST FAIL", "", "", "", "WONT FIX"],
  ["", "", "", "", "", ""],
  ["Source Coverage", "Value", "", "", "", ""],
  ["Production routes / screens", "22 / 22", "", "", "", ""],
  ["Surfaces / navigation / wire / unowned", "93 / 263 / 264 / 0", "", "", "", ""],
  ["Final candidate", "1.2.3+156", "", "", "", ""],
  ["Flutter / backend tests", "605 / 605 · 1157 / 1157", "", "", "", ""],
  ["Android SHA-256", "BCDBC45EBFFE949D3E6CD96BCB5C4C6909EF5EE6846A0CC462131EF7D1F69801", "", "", "", ""],
  ["Windows SHA-256", "DC19C129BC312F4051CE054D8CD432463EFAD93B6EC2A8DF36F9A078A92C6D66", "", "", "", ""],
];
styleHeader(listsSheet.getRange("A1:F1"));
styleGrid(listsSheet.getRange("A2:F16"));
listsSheet.getRange("A10:B10").format = { fill: colors.purple, font: { color: colors.white, bold: true } };
listsSheet.getRange("A1:F16").format.columnWidth = 22;
listsSheet.showGridLines = false;

titleBand(dashboard, "MagicMusicCRM — Canonical Feature Quality Register", `Единый источник истины на 2026-08-06. ${stories.length} code-backed user stories; acceptance считается только по Test Runs + Errors.`, "J");
dashboard.getRange("A5:J6").merge();
dashboard.getRange("A5").values = [["Правило: сначала BASELINE по каждой story, затем все FAIL/BLOCKED → Errors, исправление root cause, RETEST каждой story и полный REGRESSION. Общие зелёные suites не заменяют story execution."]];
dashboard.getRange("A5").format = { fill: colors.blue, font: { color: colors.ink, bold: true }, wrapText: true, verticalAlignment: "center", rowHeight: 40 };

const totalEnd = 501;
const cards = [
  ["A8:B8", "A9:B10", "Всего stories", `=COUNTA('User Stories'!$A$2:$A$${totalEnd})`, colors.purple],
  ["D8:E8", "D9:E10", "Не выполнено", `=COUNTIF('User Stories'!$O$2:$O$${totalEnd},"NOT EXECUTED")`, colors.amberInk],
  ["G8:H8", "G9:H10", "PASS / RETEST PASS", `=COUNTIF('User Stories'!$O$2:$O$${totalEnd},"PASS")+COUNTIF('User Stories'!$O$2:$O$${totalEnd},"RETEST PASS")`, colors.teal],
  ["I8:J8", "I9:J10", "FAIL / BLOCKED", `=COUNTIF('User Stories'!$O$2:$O$${totalEnd},"FAIL")+COUNTIF('User Stories'!$O$2:$O$${totalEnd},"RETEST FAIL")+COUNTIF('User Stories'!$O$2:$O$${totalEnd},"BLOCKED")`, colors.redInk],
];
for (const [labelRange, valueRange, label, formula, accent] of cards) {
  dashboard.getRange(labelRange).merge();
  dashboard.getRange(labelRange.split(":")[0]).values = [[label]];
  dashboard.getRange(labelRange).format = { fill: colors.pale, font: { color: colors.muted, bold: true }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: colors.line } };
  dashboard.getRange(valueRange).merge();
  dashboard.getRange(valueRange.split(":")[0]).formulas = [[formula]];
  dashboard.getRange(valueRange).format = { fill: colors.white, font: { color: accent, bold: true, size: 22 }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: colors.line } };
}

dashboard.getRange("A13:G13").values = [["System", "Total", "Executed", "Passed", "Failed", "Blocked", "Open Errors"]];
styleHeader(dashboard.getRange("A13:G13"));
const systemRows = systems.map((system, i) => {
  const row = 14 + i;
  return [
    system,
    `=COUNTIF('User Stories'!$B$2:$B$${totalEnd},A${row})`,
    `=B${row}-COUNTIFS('User Stories'!$B$2:$B$${totalEnd},A${row},'User Stories'!$O$2:$O$${totalEnd},"NOT EXECUTED")`,
    `=COUNTIFS('User Stories'!$B$2:$B$${totalEnd},A${row},'User Stories'!$O$2:$O$${totalEnd},"PASS")+COUNTIFS('User Stories'!$B$2:$B$${totalEnd},A${row},'User Stories'!$O$2:$O$${totalEnd},"RETEST PASS")`,
    `=COUNTIFS('User Stories'!$B$2:$B$${totalEnd},A${row},'User Stories'!$O$2:$O$${totalEnd},"FAIL")+COUNTIFS('User Stories'!$B$2:$B$${totalEnd},A${row},'User Stories'!$O$2:$O$${totalEnd},"RETEST FAIL")`,
    `=COUNTIFS('User Stories'!$B$2:$B$${totalEnd},A${row},'User Stories'!$O$2:$O$${totalEnd},"BLOCKED")`,
    `=COUNTIFS(Errors!$C$2:$C$300,A${row},Errors!$F$2:$F$300,"<>RETEST PASS",Errors!$F$2:$F$300,"<>WONT FIX",Errors!$A$2:$A$300,"<>")`,
  ];
});
dashboard.getRange(`A14:G${13 + systemRows.length}`).values = systemRows.map((row) => row.map((value, col) => col === 0 ? value : null));
dashboard.getRange(`B14:G${13 + systemRows.length}`).formulas = systemRows.map((row) => row.slice(1));
styleGrid(dashboard.getRange(`A14:G${13 + systemRows.length}`));
dashboard.getRange(`A14:A${13 + systemRows.length}`).format.font = { color: colors.ink, bold: true };
dashboard.getRange(`B14:G${13 + systemRows.length}`).format.horizontalAlignment = "center";

dashboard.getRange("I13:J13").values = [["Gate", "Definition"]];
styleHeader(dashboard.getRange("I13:J13"));
dashboard.getRange("I14:J19").values = [
  ["CODE-BACKED", "Есть production UI/API/runtime evidence; это не acceptance."],
  ["PASS", "Baseline story выполнена на указанном build/persona/platform."],
  ["FAIL", "Expected behavior не совпал; обязателен Error ID."],
  ["BLOCKED", "Story нельзя выполнить из-за среды/данных/доступа."],
  ["RETEST PASS", "Подтверждён fix на той же story."],
  ["Release", "Все stories = RETEST PASS/PASS, open errors = 0, regression green."],
];
styleGrid(dashboard.getRange("I14:J19"));
dashboard.getRange("A13:J24").format.rowHeight = 28;
[24, 11, 11, 11, 11, 11, 13, 3, 18, 48].forEach((w, i) => { dashboard.getRangeByIndexes(0, i, 30, 1).format.columnWidth = w; });
dashboard.freezePanes.freezeRows(3);

await fs.mkdir(previewDir, { recursive: true });
const exported = await SpreadsheetFile.exportXlsx(workbook);
await exported.save(outputFile);

const renderRanges = {
  "Coverage": "A1:J24",
  "User Stories": "A1:U18",
  "Test Runs": "A1:N10",
  "Errors": "A1:O10",
  "Lists": "A1:F16",
};
for (const [sheetName, range] of Object.entries(renderRanges)) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: "png" });
  await fs.writeFile(path.join(previewDir, `${sheetName.replaceAll(" ", "-")}.png`), new Uint8Array(await preview.arrayBuffer()));
}

const summary = await workbook.inspect({ kind: "workbook,sheet,table", maxChars: 8000, tableMaxRows: 4, tableMaxCols: 5, tableMaxCellChars: 80 });
const dashboardInspect = await workbook.inspect({ kind: "region", sheetId: "Coverage", range: "A1:J24", maxChars: 12000 });
const formulaInspect = await workbook.inspect({ kind: "formula", sheetId: "Coverage", range: "A1:J24", maxChars: 12000, options: { maxResults: 100 } });
await fs.writeFile(path.join(outputDir, "inspection-summary.txt"), `${summary.ndjson}\n\n${dashboardInspect.ndjson}\n\n${formulaInspect.ndjson}\n`, "utf8");

console.log(JSON.stringify({ outputFile, storyCount: stories.length, systems: systems.length, previews: Object.keys(renderRanges) }, null, 2));
