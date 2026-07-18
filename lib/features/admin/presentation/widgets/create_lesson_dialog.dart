import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_conflicts_api.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:intl/intl.dart';

/// Итог предсейв-проверки занятости (контракт 1): продолжать, продолжать с
/// `force: true` (админ подтвердил «Всё равно назначить») или отменить.
enum _ConflictDecision { proceed, force, cancel }

class CreateLessonDialog extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  final String? initialRoomId;
  final String? initialBranchId;
  final int? initialDurationMinutes;
  // When provided, the dialog edits this existing lesson instead of creating a
  // new one (pre-filled fields, "Сохранить" updates via PATCH).
  final Map<String, dynamic>? lesson;

  /// Пробное занятие по лиду (✔ решение владельца 17.07: «это просто готовый
  /// пресет под создание нового занятия, поэтому можно не дублировать
  /// функционал»). Когда задан — занятие вешается на лида, а не на ученика или
  /// группу, и пикеры «Группа»/«Ученик» уступают место строке с именем лида.
  final String? leadId;
  final String? leadName;

  /// Предустановка «это пробное». ✔ Владелец 17.07: индивидуальный пробный —
  /// это обычное занятие с пометкой «пробное»; списание с личного счёта админ
  /// или менеджер назначает сам.
  final bool initialIsTrial;

  const CreateLessonDialog({
    super.key,
    this.initialDate,
    this.initialRoomId,
    this.initialBranchId,
    this.initialDurationMinutes,
    this.lesson,
    this.leadId,
    this.leadName,
    this.initialIsTrial = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    DateTime? initialDate,
    String? initialRoomId,
    String? initialBranchId,
    int? initialDurationMinutes,
    Map<String, dynamic>? lesson,
    String? leadId,
    String? leadName,
    bool initialIsTrial = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => CreateLessonDialog(
        initialDate: initialDate,
        initialRoomId: initialRoomId,
        initialBranchId: initialBranchId,
        initialDurationMinutes: initialDurationMinutes,
        lesson: lesson,
        leadId: leadId,
        leadName: leadName,
        initialIsTrial: initialIsTrial,
      ),
    );
  }

  @override
  ConsumerState<CreateLessonDialog> createState() => _CreateLessonDialogState();
}

class _CreateLessonDialogState extends ConsumerState<CreateLessonDialog> {
  bool _loading = false;
  bool _saving = false;

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];

  String? _selectedTeacherId;
  String? _selectedGroupId;
  String? _selectedStudentId;
  // Лид, выбранный прямо в диалоге (из расписания, а не через пресет карточки).
  // Лид приходит только на пробное, поэтому выбор лида форсит _isTrial.
  String? _selectedLeadId;
  String? _selectedLeadName;
  List<Map<String, dynamic>> _leads = [];
  bool _leadsLoaded = false;
  String? _selectedBranchId;
  String? _selectedRoomId;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _durationMinutes = 60;
  // Поурочная ставка педагога (₽/астр.ч.): null — по умолчанию (ставка группы/
  // педагога), 0 — «входит в оклад», иначе фикс за это занятие.
  num? _teacherRate;

  /// «Это пробное занятие». Влияет только на пометку `is_trial`: списание с
  /// личного счёта за пробное админ/менеджер назначает руками (✔ владелец
  /// 17.07), автоматики здесь нет и не задумано.
  bool _isTrial = false;

  bool get _isEdit => widget.lesson != null;

  /// Занятие вешается на лида (пресет пробного), а не на ученика/группу.
  bool get _isLeadLesson => widget.leadId != null;

  /// Редактируется существующее занятие лида: перевесить его здесь не на кого,
  /// показываем лида строкой только для чтения (сервер сохраняет привязку).
  bool get _isEditingLeadLesson => _isEdit && widget.lesson?['lead_id'] != null;

  /// Кому разрешена кнопка «Всё равно назначить» при конфликте (admin+).
  bool get _canForceConflicts {
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    return kScheduleForceRoles.contains(role);
  }

  @override
  void initState() {
    super.initState();
    // Прогреваем статус роли: к моменту показа диалога конфликтов
    // releaseGateStatusProvider уже должен быть разрешён, иначе admin+ не
    // увидит кнопку «Всё равно назначить» при первом же конфликте.
    ref.read(releaseGateStatusProvider);
    _isTrial = widget.initialIsTrial;
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
      // У пресета пробного дата — «завтра», но время из неё брать нельзя:
      // получилось бы «завтра в момент, когда открыли диалог». Прежнее окно
      // пробного предлагало 10:00 — оставляем его.
      _selectedTime = widget.initialIsTrial
          ? const TimeOfDay(hour: 10, minute: 0)
          : TimeOfDay.fromDateTime(widget.initialDate!);
    }
    if (widget.initialRoomId != null) {
      _selectedRoomId = widget.initialRoomId;
    }
    if (widget.initialBranchId != null) {
      _selectedBranchId = widget.initialBranchId;
      _loadRooms(widget.initialBranchId!);
    }
    if (widget.initialDurationMinutes != null &&
        widget.initialDurationMinutes! > 0) {
      _durationMinutes = widget.initialDurationMinutes!;
    }
    // Pre-fill from the lesson being edited.
    final lesson = widget.lesson;
    if (lesson != null) {
      _selectedTeacherId = lesson['teacher_id']?.toString();
      _selectedGroupId = lesson['group_id']?.toString();
      _selectedStudentId = lesson['student_id']?.toString();
      _selectedBranchId = lesson['branch_id']?.toString() ?? _selectedBranchId;
      _selectedRoomId = lesson['room_id']?.toString() ?? _selectedRoomId;
      final raw = lesson['scheduled_at']?.toString();
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (parsed != null) {
        // Stored as UTC; show in Moscow time (UTC+3) to match the schedule.
        final local = parsed.toUtc().add(const Duration(hours: 3));
        _selectedDate = DateTime(local.year, local.month, local.day);
        _selectedTime = TimeOfDay(hour: local.hour, minute: local.minute);
      }
      if (_selectedBranchId != null) _loadRooms(_selectedBranchId!);
      _isTrial = lesson['is_trial'] == true;
      final rawRate = lesson['teacher_rate'];
      if (rawRate is num) {
        _teacherRate = rawRate;
      } else if (rawRate != null) {
        _teacherRate = num.tryParse(rawRate.toString());
      }
    }
    _loadData();
  }

  MagicCrmService get _crm => ref.read(magicCrmServiceProvider);

  String get _dialogTitle {
    if (_isEdit) return 'Редактировать занятие';
    if (_isLeadLesson) return 'Пробное занятие';
    return 'Новое занятие';
  }

  String get _savedMessage {
    if (_isEdit) return 'Занятие обновлено';
    if (_isLeadLesson) return 'Пробное занятие назначено';
    return 'Занятие создано';
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _crm.listTeachers(limit: 100),
        _crm.listGroups(limit: 100),
        _crm.listStudents(limit: 100),
        _crm.listBranches(limit: 100),
      ]);

      setState(() {
        _teachers = results[0];
        _groups = results[1];
        _students = results[2];
        _branches = results[3];
        _loading = false;
      });
      final branchId =
          _selectedBranchId ?? _branches.firstOrNull?['id']?.toString();
      if (branchId != null) {
        if (mounted) setState(() => _selectedBranchId ??= branchId);
        await _loadRooms(branchId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки данных: $e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadRooms(String branchId) async {
    try {
      final rooms = await _crm.listRooms(branchId: branchId, limit: 100);
      setState(() {
        _rooms = rooms;
        if (_selectedRoomId != null &&
            !_rooms.any((room) => room['id'].toString() == _selectedRoomId)) {
          _selectedRoomId = null;
        }
      });
    } catch (e) {
      debugPrint('Error loading rooms: $e');
    }
  }

  Future<void> _save() async {
    // Занятие всегда чьё-то: группы, ученика или — у пробного — лида (пресет
    // из карточки, выбор в диалоге или уже привязанный при редактировании).
    final hasSubject =
        _isLeadLesson ||
        _isEditingLeadLesson ||
        _selectedGroupId != null ||
        _selectedStudentId != null ||
        _selectedLeadId != null;
    if (_selectedTeacherId == null ||
        !hasSubject ||
        _selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните обязательные поля')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // We want to save this as a timestamp with the correct offset (+03:00)
      // or convert to UTC. Given the user wants UTC+3, let's treat selected time as Moscow time.
      // If we use DateTime.toIso8601String() on a local time, it's missing the offset.
      // Let's create a UTC time that represents the same instant.
      final moscowTime = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour - 3, // Subtract 3 to get UTC
        _selectedTime.minute,
      );

      final scheduledAt = moscowTime.toIso8601String();

      // Контракт 1: предсейв-проверка «занят ли педагог/аудитория». При
      // конфликте — блок со списком (кто/когда/где); «Всё равно назначить»
      // доступно только admin+ и уходит на сервер с force: true.
      final decision = await _checkConflictsBeforeSave(
        slotStartUtc: moscowTime,
      );
      if (decision == _ConflictDecision.cancel) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      final payload = _lessonPayload(scheduledAt);
      final api = ref.read(magicApiClientProvider);
      final lessonId = widget.lesson?['id']?.toString();
      try {
        await _sendSave(
          api,
          lessonId,
          payload,
          force: decision == _ConflictDecision.force,
        );
      } on MagicApiException catch (e) {
        // Контракт 2: гонка между проверкой и записью — сервер всё равно
        // ответил 409 со списком конфликтов. Показываем тот же диалог и по
        // подтверждению повторяем один раз с force: true.
        final conflicts = scheduleConflictsFrom409(e);
        if (conflicts == null) rethrow;
        if (!mounted) return;
        final retry = await _showConflictDialog(conflicts: conflicts);
        if (retry != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        await _sendSave(api, lessonId, payload, force: true);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_savedMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendSave(
    MagicApiClient api,
    String? lessonId,
    Map<String, dynamic> payload, {
    required bool force,
  }) async {
    if (_isEdit) {
      await api.updateLessonRaw(lessonId!, payload, force: force);
    } else {
      await api.createLessonRaw(payload, force: force);
    }
  }

  /// Тело POST/PATCH /crm/lessons — то же, что раньше собирал
  /// MagicCrmService.createLesson/updateLesson, но в одном месте, чтобы
  /// force-повтор после 409 гарантированно слал ровно тот же запрос.
  Map<String, dynamic> _lessonPayload(String scheduledAt) {
    final leadId = widget.leadId ?? _selectedLeadId;
    final leadName = widget.leadName ?? _selectedLeadName;
    final notes = leadId != null
        ? 'Пробное занятие по лиду: ${leadName ?? ''}'.trim()
        : null;
    return {
      'scheduledAt': scheduledAt,
      'durationMinutes': _durationMinutes,
      'isTrial': _isTrial,
      if (_selectedTeacherId != null) 'teacherId': _selectedTeacherId,
      if (_selectedGroupId != null) 'groupId': _selectedGroupId,
      if (_selectedStudentId != null) 'studentId': _selectedStudentId,
      if (_selectedBranchId != null) 'branchId': _selectedBranchId,
      if (_selectedRoomId != null) 'roomId': _selectedRoomId,
      if (_teacherRate != null) 'teacherRate': _teacherRate,
      if (!_isEdit) 'status': 'scheduled',
      // Лид привязывается только при создании; при редактировании сервер
      // сохраняет существующую привязку (coalesce).
      if (!_isEdit && leadId != null) 'leadId': leadId,
      if (!_isEdit && notes != null && notes.isNotEmpty) 'notes': notes,
    };
  }

  // Контракт 1: спрашиваем /crm/schedule/conflicts, занят ли выбранный педагог
  // и/или аудитория в этом окне. Любая ошибка чтения (в т.ч. 404 до ребилда
  // сервера) трактуется как «проверить нельзя — не блокируем»: предпроверка не
  // должна останавливать создание занятий при недоступном бекенде.
  Future<_ConflictDecision> _checkConflictsBeforeSave({
    required DateTime slotStartUtc,
  }) async {
    final teacherId = _selectedTeacherId;
    final roomId = _selectedRoomId;
    final hasTeacher = teacherId != null && teacherId.isNotEmpty;
    final hasRoom = roomId != null && roomId.isNotEmpty;
    // Ни педагога, ни аудитории — конфликтовать нечему.
    if (!hasTeacher && !hasRoom) return _ConflictDecision.proceed;

    final editedLessonId = _isEdit ? widget.lesson!['id']?.toString() : null;
    ScheduleConflictCheck check;
    try {
      check = await ref
          .read(magicApiClientProvider)
          .checkScheduleConflicts(
            teacherId: hasTeacher ? teacherId : null,
            roomId: hasRoom ? roomId : null,
            startsAt: slotStartUtc.toIso8601String(),
            endsAt: slotStartUtc
                .add(Duration(minutes: _durationMinutes))
                .toIso8601String(),
            excludeLessonId: editedLessonId,
          );
    } catch (e) {
      debugPrint('Schedule conflicts pre-check failed: $e');
      return _ConflictDecision.proceed; // soft-fail open.
    }

    if (!check.hasConflicts) return _ConflictDecision.proceed;
    if (!mounted) return _ConflictDecision.cancel;

    final confirmed = await _showConflictDialog(
      conflicts: check.conflicts,
      teacherBusy: check.teacherBusy,
      roomBusy: check.roomBusy,
    );
    return confirmed == true
        ? _ConflictDecision.force
        : _ConflictDecision.cancel;
  }

  /// Диалог конфликтов: кто/когда/где уже стоит в слоте. «Всё равно назначить»
  /// строится ТОЛЬКО для admin+ (контракт 2) — остальным остаётся «Отмена».
  Future<bool?> _showConflictDialog({
    required List<ScheduleConflictInfo> conflicts,
    bool? teacherBusy,
    bool? roomBusy,
  }) {
    final headers = <String>[
      if (teacherBusy == true) 'Преподаватель занят в это время',
      if (roomBusy == true) 'Аудитория занята в это время',
    ];
    if (headers.isEmpty) headers.add('В выбранное время слот уже занят');
    final canForce = _canForceConflicts;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        icon: const Icon(Icons.warning_amber_rounded, color: AppColor.danger),
        title: const Text('Время занято'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final header in headers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    header,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (conflicts.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final conflict in conflicts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColor.dangerSoft,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: const Color(0x52E53935)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: AppColor.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              conflict.label(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              Text(
                canForce
                    ? 'Назначить занятие всё равно?'
                    : 'Выберите другое время или аудиторию.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          if (canForce)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.gold,
                foregroundColor: AppColor.onGold,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Всё равно назначить'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryGold),
            SizedBox(height: 16),
            Text('Загрузка данных...'),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Text(_dialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Пробное по лиду: «кто» уже известен и менять его здесь нечем —
            // диалог открыт из карточки именно этого лида. При редактировании
            // занятия лида привязку тоже не перевешивают — строка read-only.
            if (_isLeadLesson || _isEditingLeadLesson) ...[
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Лид'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _presetLeadName ?? 'Без имени',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _leadBadge(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Teacher Selection
            _buildSelectionField(
              label: 'Преподаватель *',
              value: _getTeacherName(_selectedTeacherId),
              onTap: () {
                final items = _teachers.map((t) {
                  final name = _getTeacherNameFromData(t);
                  return SearchableSelectItem(
                    id: t['id'].toString(),
                    label: name,
                  );
                }).toList();

                SearchableSelect.show(
                  context: context,
                  title: 'Выберите преподавателя',
                  hintText: 'Поиск по имени...',
                  items: items,
                  selectedId: _selectedTeacherId,
                  isNullable: false,
                  onSelected: (item) =>
                      setState(() => _selectedTeacherId = item?.id),
                );
              },
            ),
            const SizedBox(height: 16),

            // У пробного по лиду занятие уже привязано к нему — группы и
            // ученика у него нет.
            if (!_isLeadLesson && !_isEditingLeadLesson) ...[
              // Group Selection
              SearchablePickerField(
                label: 'Группа',
                placeholder: 'Индивидуально',
                selectedId: _selectedGroupId,
                items: [
                  for (final g in _groups)
                    SearchableSelectItem(
                      id: g['id'].toString(),
                      label: g['name']?.toString() ?? 'Без названия',
                    ),
                ],
                onSelected: (item) => setState(() {
                  _selectedGroupId = item?.id;
                  // A group lesson has no single student (and no lead).
                  if (item != null) {
                    _selectedStudentId = null;
                    _clearSelectedLead();
                  }
                }),
              ),

              if (_selectedGroupId == null) ...[
                const SizedBox(height: 16),
                // Student Selection
                _buildSelectionField(
                  label: 'Ученик *',
                  value: _getStudentName(_selectedStudentId),
                  onTap: () {
                    final items = _students.map((s) {
                      final name = _getStudentNameFromData(s);
                      return SearchableSelectItem(
                        id: s['id'].toString(),
                        label: name,
                        data: s,
                      );
                    }).toList();

                    SearchableSelect.show(
                      context: context,
                      title: 'Выберите ученика',
                      hintText: 'Поиск по ФИО...',
                      // [_students] is only the pre-loaded first page (100 of
                      // ~1000). Filtering it locally made every student past
                      // that page unfindable, however exactly the name was
                      // typed — so a real query goes to the server instead.
                      items: items,
                      onSearch: (query) async {
                        final response = await _crm.searchStudents(
                          q: query,
                          limit: 50,
                        );
                        final rows = response['items'];
                        if (rows is! List) {
                          return const <SearchableSelectItem>[];
                        }
                        return [
                          for (final row
                              in rows.whereType<Map<String, dynamic>>())
                            SearchableSelectItem(
                              id: row['id'].toString(),
                              label: _getStudentNameFromData(row),
                              data: row,
                            ),
                        ];
                      },
                      selectedId: _selectedStudentId,
                      isNullable: false,
                      onSelected: (item) => setState(() {
                        _selectedStudentId = item?.id;
                        // Ученик и лид взаимоисключающи: занятие либо
                        // ученика, либо пробное лида.
                        if (item != null) _clearSelectedLead();
                        // A student found by the server search is not in the
                        // pre-loaded page, and _getStudentName only reads that
                        // page — without this the field would keep saying «Не
                        // выбран» for the student just picked.
                        final row = item?.data;
                        if (row != null &&
                            !_students.any(
                              (s) => s['id'].toString() == item!.id,
                            )) {
                          _students = [..._students, row];
                        }
                      }),
                    );
                  },
                ),
                // #6: лид доступен и из расписания, а не только через пресет
                // карточки. Выбор лида = пробное занятие (галочка форсится).
                if (!_isEdit) ...[
                  const SizedBox(height: 16),
                  _buildSelectionField(
                    label: 'Лид (на пробное)',
                    value: _selectedLeadName ?? 'Не выбран',
                    badge: _selectedLeadId != null ? _leadBadge() : null,
                    onTap: _pickLead,
                  ),
                ],
              ],
              const SizedBox(height: 16),
            ],

            // Branch & Room
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBranchId,
                    isExpanded: true,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    decoration: const InputDecoration(labelText: 'Филиал *'),
                    items: _branches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b['id'].toString(),
                            child: Text(b['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedBranchId = val;
                        _selectedRoomId = null;
                        _rooms = [];
                      });
                      if (val != null) _loadRooms(val);
                    },
                  ),
                ),
                if (_selectedBranchId != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: SearchablePickerField(
                      label: 'Аудитория',
                      placeholder: _rooms.isEmpty
                          ? 'Нет доступных'
                          : 'Выберите аудиторию',
                      enabled: _rooms.isNotEmpty,
                      selectedId: _selectedRoomId,
                      items: [
                        for (final r in _rooms)
                          SearchableSelectItem(
                            id: r['id'].toString(),
                            label: r['name']?.toString() ?? '—',
                          ),
                      ],
                      onSelected: (item) =>
                          setState(() => _selectedRoomId = item?.id),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 30),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _selectedDate = d);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                      DateFormat('dd.MM.yyyy', 'ru').format(_selectedDate),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                        builder: (BuildContext context, Widget? child) {
                          return MediaQuery(
                            data: MediaQuery.of(
                              context,
                            ).copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          );
                        },
                      );
                      if (t != null) setState(() => _selectedTime = t);
                    },
                    icon: const Icon(Icons.access_time_rounded, size: 18),
                    label: Text(_selectedTime.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ✔ Решение владельца 17.07: «индивидуальный пробный» — это не
            // отдельный тип занятия, а пометка «пробное» на обычном занятии.
            // Списание с личного счёта за него админ/менеджер назначает сам:
            // автоматики здесь нет, и она не задумана.
            SwitchListTile(
              value: _isTrial,
              activeThumbColor: AppTheme.primaryGold,
              contentPadding: EdgeInsets.zero,
              title: const Text('Пробное занятие'),
              subtitle: Text(
                _isTrial
                    ? 'Списание с личного счёта назначается вручную'
                    : 'Обычное занятие',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              // У пресета пробного галочку не снимают: диалог открыт кнопкой
              // «На пробный», и снятая пометка сделала бы её ложью. То же при
              // выбранном в диалоге лиде — лид приходит только на пробное.
              onChanged: (_isLeadLesson || _selectedLeadId != null)
                  ? null
                  : (value) => setState(() => _isTrial = value),
            ),
            const SizedBox(height: 8),
            // #6: поурочная ставка педагога (по умолчанию — ставка группы/
            // педагога, «Входит в оклад» = 0 для пробных).
            TeacherRateSelector(
              label: 'Ставка за занятие (₽/астр.ч.)',
              allowInherit: true,
              initialRate: _teacherRate,
              onChanged: (v) => setState(() => _teacherRate = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Отмена',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }

  // ── Лид в диалоге ─────────────────────────────────────────────────────────

  /// Имя лида для read-only строки: пресет карточки или редактируемое занятие
  /// (lead_name приходит с бекенда вместе с уроком).
  String? get _presetLeadName {
    final name = widget.leadName ?? widget.lesson?['lead_name']?.toString();
    final trimmed = name?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void _clearSelectedLead() {
    _selectedLeadId = null;
    _selectedLeadName = null;
  }

  /// Визуальная пометка «лид» — чтобы пробное по лиду не читалось как занятие
  /// ученика.
  Widget _leadBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColor.gold.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColor.gold.withAlpha(120)),
      ),
      child: const Text(
        'лид',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColor.gold,
        ),
      ),
    );
  }

  String _leadLabelFromData(Map<String, dynamic> lead) {
    final name = '${lead['first_name'] ?? ''} ${lead['last_name'] ?? ''}'
        .trim();
    final phone = lead['phone']?.toString().trim() ?? '';
    if (name.isEmpty && phone.isEmpty) return 'Без имени';
    if (name.isEmpty) return phone;
    return phone.isEmpty ? name : '$name · $phone';
  }

  String _leadNameFromData(Map<String, dynamic> lead) {
    final name = '${lead['first_name'] ?? ''} ${lead['last_name'] ?? ''}'
        .trim();
    if (name.isNotEmpty) return name;
    final phone = lead['phone']?.toString().trim() ?? '';
    return phone.isEmpty ? 'Без имени' : phone;
  }

  Future<void> _pickLead() async {
    // Первая страница подгружается лениво — лид в диалоге нужен нечасто.
    if (!_leadsLoaded) {
      try {
        final leads = await _crm.listLeads(limit: 100);
        if (!mounted) return;
        setState(() {
          _leads = leads;
          _leadsLoaded = true;
        });
      } catch (e) {
        debugPrint('Error loading leads: $e');
      }
    }
    if (!mounted) return;

    SearchableSelect.show(
      context: context,
      title: 'Выберите лида',
      hintText: 'Поиск по имени или телефону...',
      items: [
        for (final lead in _leads)
          SearchableSelectItem(
            id: lead['id'].toString(),
            label: _leadLabelFromData(lead),
            data: lead,
          ),
      ],
      // Предзагружена только первая страница — настоящий поиск идёт на сервер
      // (тот же серверный q, что и у канбана лидов).
      onSearch: (query) async {
        final rows = await _crm.listLeads(q: query, limit: 50);
        return [
          for (final row in rows)
            SearchableSelectItem(
              id: row['id'].toString(),
              label: _leadLabelFromData(row),
              data: row,
            ),
        ];
      },
      selectedId: _selectedLeadId,
      onSelected: (item) => setState(() {
        if (item == null) {
          _clearSelectedLead();
          return;
        }
        _selectedLeadId = item.id;
        final row = item.data;
        _selectedLeadName = row is Map<String, dynamic>
            ? _leadNameFromData(row)
            : item.label;
        // Лид приходит только на пробное: ученик снимается, пометка форсится.
        _selectedStudentId = null;
        _isTrial = true;
      }),
    );
  }

  String _getTeacherName(String? id) {
    if (id == null) return 'Не выбран';
    final t = _teachers.firstWhere(
      (element) => element['id'].toString() == id,
      orElse: () => {},
    );
    if (t.isEmpty) return 'Не выбран';
    return _getTeacherNameFromData(t);
  }

  String _getTeacherNameFromData(Map<String, dynamic> t) {
    final fn = t['first_name']?.toString() ?? '';
    final ln = t['last_name']?.toString() ?? '';
    final p = t['profiles'] as Map<String, dynamic>?;

    var name = '$fn $ln'.trim();
    if (name.isEmpty && p != null) {
      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }

  String _getStudentName(String? id) {
    if (id == null) return 'Не выбран';
    final s = _students.firstWhere(
      (element) => element['id'].toString() == id,
      orElse: () => {},
    );
    if (s.isEmpty) return 'Не выбран';
    return _getStudentNameFromData(s);
  }

  String _getStudentNameFromData(Map<String, dynamic> s) {
    final fn = s['first_name']?.toString() ?? '';
    final ln = s['last_name']?.toString() ?? '';
    final p = s['profiles'] as Map<String, dynamic>?;

    var name = '$fn $ln'.trim();
    if (name.isEmpty && p != null) {
      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }

  Widget _buildSelectionField({
    required String label,
    required String value,
    required VoidCallback onTap,
    Widget? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: value == 'Не выбран'
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ),
                ?badge,
                Icon(
                  Icons.arrow_drop_down,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
