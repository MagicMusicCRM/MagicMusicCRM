part of 'client_card.dart';

extension _ClientCardTabsA on _ClientCardState {
  /// В чёрном ли списке клиент — по любой из половин карточки. Сервер отдаёт
  /// флаг на каждой (см. blacklist.ts); достаточно одной, чтобы это был бан.
  bool get _isBlacklisted =>
      _student?['blacklisted'] == true || _leadData['blacklisted'] == true;

  String? get _blacklistReason {
    final fromStudent = _student?['blacklist_reason']?.toString();
    if (fromStudent != null && fromStudent.trim().isNotEmpty) {
      return fromStudent;
    }
    final fromLead = _leadData['blacklist_reason']?.toString();
    if (fromLead != null && fromLead.trim().isNotEmpty) return fromLead;
    return null;
  }

  /// Красная плашка над карточкой забаненного клиента.
  ///
  /// ✔ Решение владельца 17.07: «карточка клиента помечается красным цветом
  /// предупреждения». Плашкой, а не одной лишь подкраской заголовка: то, что
  /// человеку закрыты чаты, должно быть видно раньше, чем сотрудник начнёт
  /// гадать, почему клиент молчит.
  Widget _buildBlacklistBanner(ColorScheme cs) {
    final reason = _blacklistReason;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        0,
        AppSpace.xl,
        AppSpace.md,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_rounded, size: 18, color: AppTheme.danger),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Клиент в чёрном списке',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason ?? 'Причина не указана',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  'Писать в чаты школы и администрации он не может.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, StatusRecord curStatus) {
    final banned = _isBlacklisted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.md,
        AppSpace.md,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: banned
                  ? AppTheme.danger.withValues(alpha: 0.12)
                  : AppColor.goldSoft,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(
                color: banned
                    ? AppTheme.danger.withValues(alpha: 0.55)
                    : AppColor.goldLine,
              ),
            ),
            child: Icon(
              banned ? Icons.block_rounded : Icons.person_outline_rounded,
              size: 22,
              color: banned ? AppTheme.danger : AppColor.gold,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_leadData['name'] ?? ''} ${_leadData['last_name'] ?? ''}'
                      .trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: curStatus.$3,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            'Клиент · Лид · ${curStatus.$2}',
                            ?_ageLabel(),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: widget.routed ? 'Назад' : 'Закрыть форму',
            onPressed: _handleClose,
            icon: Icon(
              widget.routed ? Icons.arrow_back_rounded : Icons.close_rounded,
            ),
            iconSize: 20,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(
    ColorScheme cs,
    List<(IconData, String, String)> tabs, {
    required int selectedIndex,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      child: MagicDesktopScrollbar(
        axis: Axis.horizontal,
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.sm),
                _buildTabChip(cs, i, tabs, selectedIndex: selectedIndex),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabChip(
    ColorScheme cs,
    int index,
    List<(IconData, String, String)> tabs, {
    required int selectedIndex,
  }) {
    final selected = selectedIndex == index;
    final (icon, label, section) = tabs[index];
    return Material(
      color: selected ? AppColor.goldSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: () {
          _emitState(() => _selectedSection = section);
          widget.onSectionChanged?.call(section);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? AppColor.goldLine : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColor.gold : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColor.gold : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.lg,
      ),
      // Wrap so the action buttons reflow onto a second line on narrow
      // (mobile) dialog widths instead of overflowing on the right.
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ClientArchiveButton(
              entityType: 'lead',
              entityId: _leadId,
              allowed: clientRoleCanArchive(
                ref.read(releaseGateStatusProvider).asData?.value.role ?? '',
              ),
              onArchived: () => _closeCard(true),
            ),
            // Product rule: a trial, its homework and feedback all belong to
            // the lead. Conversion happens only when a paid package is chosen,
            // so there is no standalone «Создать ученика» mutation here.
            if (!_isConverted && !_hasLinkedStudent)
              OutlinedButton.icon(
                onPressed: _saving || _converting
                    ? null
                    : _showIssueSubscriptionSheet,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                icon: _converting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.card_membership_rounded, size: 18),
                label: const Text('Выдать абонемент'),
              ),
            // «Прикрепить к ученику» (§1 спеки). Рядом с выдачей абонемента,
            // потому что это тот же выбор: клиент уже заведён или ещё нет.
            // Раньше связать можно было только пару, которую нашёл автоподбор
            // дублей — если он молчал, привязать было нельзя вовсе.
            if (!_isConverted && !_hasLinkedStudent)
              OutlinedButton.icon(
                onPressed: _saving || _converting ? null : _linkExistingStudent,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Прикрепить к ученику'),
              ),
            // #6: вместо записи на пробное из карточки — переход в расписание
            // (на ближайшее занятие клиента, иначе на сегодня).
            OutlinedButton.icon(
              onPressed: _saving || _converting ? null : _openScheduleFromCard,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                side: BorderSide(color: cs.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text('Открыть в расписании'),
            ),
            TextButton(
              onPressed: _saving || _converting ? null : _handleClose,
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              child: Text(widget.routed ? 'Назад' : 'Отмена'),
            ),
            FilledButton(
              onPressed: _saving || _converting ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.gold,
                foregroundColor: AppColor.onGold,
                disabledBackgroundColor: AppColor.gold.withValues(alpha: 0.42),
                disabledForegroundColor: AppColor.onGold.withValues(alpha: 0.7),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColor.onGold,
                      ),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab: Клиент ───────────────────────────────────────────────────────────
  Widget _buildClientInfoTab(ColorScheme cs, StatusRecord curStatus) {
    if (_isStudent) {
      return _studentGuard(cs, () => _buildClientInfoContent(cs, curStatus));
    }
    return _buildClientInfoContent(cs, curStatus);
  }

  Widget _buildClientInfoContent(ColorScheme cs, StatusRecord curStatus) {
    final duplicateCandidates = _duplicateCandidates
        .where(_isCurrentLeadDuplicateCandidate)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Клиент'),
          if (_mode.hasLeadHalf) _buildStatusPicker(cs, curStatus),
          if (_mode.hasStudentHalf) _buildStudentStatusPicker(cs),
          _buildClientTextField(
            cs,
            'Имя',
            _clientFirstName,
            (value) => _updateClientCore('firstName', value),
          ),
          _buildClientTextField(
            cs,
            'Фамилия',
            _clientLastName,
            (value) => _updateClientCore('lastName', value),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RuPhoneField(
              // Epoch key, not value key — see _buildClientTextField.
              key: ValueKey('client-phone-$_editorEpoch'),
              initialCanonical: _clientPhone,
              onCanonicalChanged: (c) {
                _updateClientCore('phone', c.isEmpty ? null : c);
              },
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          _buildClientTextField(
            cs,
            'Электронная почта',
            _clientEmail,
            (value) => _updateClientCore('email', value),
            keyboard: TextInputType.emailAddress,
          ),
          if (!_loadingMetadata) _buildBranchDropdown(cs, 'Основной филиал'),

          const SizedBox(height: AppSpace.lg),
          _sectionTitle('Параметры клиента'),
          if (_loadingMetadata)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(color: AppColor.gold),
              ),
            )
          else ...[
            // #7: «Ответственный» — пикер по справочнику сотрудников. A lead
            // writes canonical assignedTo; a student keeps compatible custom_data.
            _buildResponsiblePicker(cs, _isStudent ? 'students' : 'leads'),
            // Возраст: поле ввода, пока нет даты рождения, иначе — посчитанное
            // сервером значение только на просмотр.
            _buildAgeCustomField(cs, _isStudent ? 'students' : 'leads'),
            // KVA-234: мультидисциплины чипами. Контактные лица переехали на
            // вкладку «Семья» (#14) — здесь они дублировали её.
            _buildDisciplinesChips(cs, _isStudent ? 'students' : 'leads'),
            // Чёрный список — у обеих половин карточки, а не только у ученика:
            // аккаунт клиента цепляется к любой из них.
            _buildBlacklistToggle(cs),
          ],

          if (_mode.hasStudentHalf) ...[
            if (_balance != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Финансы', [
                _InfoRow(
                  icon: Icons.summarize_outlined,
                  label: 'Всего оплачено',
                  value: '${_balance!.totalPaidRaw} ₽',
                ),
                _InfoRow(
                  icon: Icons.history_edu_outlined,
                  label: 'Списано за уроки',
                  value: '${_balance!.totalCostRaw} ₽',
                ),
                _InfoRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Баланс',
                  value: '${_balance!.balanceRaw} ₽',
                ),
              ]),
            ],
            if (_studentId.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              StudentScheduleSection(
                studentId: _studentId,
                lessons: _lessons.map((l) => l.raw).toList(),
                onChanged: _fetchStudentData,
              ),
            ],
            if (_balance != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildLedgerSection(cs),
            ],
            const SizedBox(height: AppSpace.lg),
            _studentGroupsInfoCard(groups: _groups),
          ],

          // Дата обращения ученика (✔ решение владельца 16.07: поле живёт на
          // стороне students). У импортированных 3105 учеников она уже лежала
          // в custom_data.addressDate — просто её никто не показывал.
          if (_mode.hasStudentHalf &&
              !_mode.hasLeadHalf &&
              _student != null) ...[
            if (_appealAtLabel(_student!) != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Обращение', [
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Дата обращения',
                  value: _appealAtLabel(_student!)!,
                  hint: _appealAtSourceLabel(_student!),
                ),
                // #9: «Дата визита» из бывшей секции «Дополнительно» — теперь
                // строкой в «Обращении», рядом с датой обращения.
                if (_visitDateLabel() != null)
                  _InfoRow(
                    icon: Icons.event_available_outlined,
                    label: 'Дата визита',
                    value: _visitDateLabel()!,
                  ),
              ]),
            ],
          ],

          if (_mode.hasLeadHalf) ...[
            if (_leadCreatedAtLabel() != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Обращение', [
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Дата обращения',
                  value: _leadCreatedAtLabel()!,
                  hint: _appealAtSourceLabel(_leadData),
                ),
                if (_visitDateLabel() != null)
                  _InfoRow(
                    icon: Icons.event_available_outlined,
                    label: 'Дата визита',
                    value: _visitDateLabel()!,
                  ),
              ]),
            ],
          ],

          const SizedBox(height: AppSpace.lg),
          ClientAppUserPanel(
            entityType: _mode.hasStudentHalf ? 'student' : 'lead',
            entityId: _mode.hasStudentHalf ? _studentId : _leadId,
          ),

          // Агрегат «Связи и активность» — это активность ЛИДА (пробные,
          // похожие лиды). У ученика без лид-половины лид-карточка не грузится
          // вовсе (_loadingCard остался бы true), и секция крутила бы спиннер
          // вечно — поэтому она только при наличии лид-половины.
          if (_mode.hasLeadHalf) ...[
            const SizedBox(height: AppSpace.lg),
            _sectionTitle('Связи и активность'),
            _buildAggregateCard(cs, includeTasks: false),
          ],

          if (_mode.hasLeadHalf &&
              (_loadingDuplicates || duplicateCandidates.isNotEmpty)) ...[
            const SizedBox(height: AppSpace.md),
            _sectionTitle('Кандидаты на связь'),
            _duplicateCandidatesSection(
              cs,
              candidates: duplicateCandidates,
              loading: _loadingDuplicates,
              pendingId: _duplicateDecisionId,
              onAttach: _attachDuplicateCandidate,
            ),
          ],
        ],
      ),
    );
  }

  // ── «Дополнительно» — HolliHop-поля без своей строки/пикера ───────────────
  // Reads from the student half first, then the lead half, so a converted
  // client shows whichever half carries the value.
  String? _hhField(String key) {
    for (final data in [
      if (_mode.hasStudentHalf) _student?['custom_data'],
      if (_mode.hasLeadHalf) _leadData['custom_data'],
    ]) {
      if (data is Map) {
        final s = _stringifyCustom(data[key]);
        if (s != null) return s;
      }
    }
    return null;
  }

  String? _stringifyCustom(Object? v) {
    if (v == null) return null;
    if (v is String) return v.trim().isEmpty ? null : v.trim();
    if (v is List) {
      final parts = v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return parts.isEmpty ? null : parts.join(', ');
    }
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  String? _responsibleLabel() {
    final name = _hhField('responsibleName');
    if (name != null) return name;
    // Fallback: first assignee's FullName from either half.
    for (final data in [
      if (_mode.hasStudentHalf) _student?['custom_data'],
      if (_mode.hasLeadHalf) _leadData['custom_data'],
    ]) {
      if (data is Map) {
        final a = data['assignees'];
        if (a is List && a.isNotEmpty && a.first is Map) {
          final fn = (a.first as Map)['FullName']?.toString().trim();
          if (fn != null && fn.isNotEmpty) return fn;
        }
      }
    }
    return null;
  }

  String? _visitDateLabel() {
    final raw = _hhField('visitDate') ?? _hhField('visitDateTime');
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw);
    return dt != null ? DateFormat('d MMM yyyy', 'ru').format(dt) : raw;
  }

  // Секция «Дополнительно» распущена (#9): «Ответственный» стал пикером (#7),
  // статус HolliHop — подписью у пикеров статуса, «Тип обращения» читается
  // алиасом addressType в общей форме, «Дата визита» — строкой в «Обращении»,
  // «Контактные лица» — на вкладке «Семья» (#14). «Тип лида» и UTM удалены.

  // ── Tab: Задачи ──────────────────────────────────────────────────────────
  Widget _buildTasksTab(ColorScheme cs) {
    if (_loadingCard) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
        child: Center(child: CircularProgressIndicator(color: AppColor.gold)),
      );
    }
    final card = _leadCard;
    final tasks = card == null
        ? const <Map<String, dynamic>>[]
        : _list(card['tasks']);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Задачи')),
              _buildAddTaskButton(cs),
            ],
          ),
          if (card == null)
            _emptyHint(cs, 'Карточка активности временно недоступна')
          else if (tasks.isEmpty)
            _emptyHint(cs, 'Открытых задач нет')
          else
            // #12: задача раскрывается по тапу — полный текст, автор,
            // исполнитель, срок.
            ...tasks.map((row) => _TaskTile(task: row)),
        ],
      ),
    );
  }

  Widget _buildAddTaskButton(ColorScheme cs) {
    return TextButton.icon(
      onPressed: _addingTask ? null : _openAddTaskSheet,
      style: TextButton.styleFrom(
        foregroundColor: AppColor.gold,
        backgroundColor: AppColor.goldSoft,
        disabledForegroundColor: AppColor.gold.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          side: const BorderSide(color: AppColor.goldLine),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      icon: _addingTask
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_rounded, size: 16),
      label: const Text('Добавить'),
    );
  }

  Future<void> _openAddTaskSheet() async {
    // Сотрудники для поля «Исполнитель»; сбой загрузки не блокирует задачу.
    var staff = const <Map<String, dynamic>>[];
    try {
      staff = List<Map<String, dynamic>>.from(
        await ref.read(magicCrmServiceProvider).listStaff(limit: 100),
      );
    } catch (_) {}
    if (!mounted) return;

    final input = await showAddTaskSheet(
      context,
      isStudent: _isStudent,
      staff: staff,
    );
    if (input == null) return;
    final title = input.title;
    final dueAt = input.due?.toUtc().toIso8601String();
    final assignedTo = input.assignedTo;
    if (title.isEmpty) {
      if (mounted) {
        MagicToast.show(
          context,
          'Укажите название задачи',
          type: MagicToastType.danger,
        );
      }
      return;
    }

    // New tasks target the primary half: the student side for a converted
    // client, otherwise the open entity.
    final targetType = _isConverted ? 'student' : widget.entityType;
    final targetId = _isConverted ? _studentId : _entityId;
    if (targetId.isEmpty) return;
    _emitState(() => _addingTask = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTask(
            entityType: targetType,
            entityId: targetId,
            title: title,
            dueAt: dueAt,
            assignedTo: assignedTo,
          );
      _dirty = true;
      if (_mode.hasStudentHalf) {
        await _fetchStudentData();
      }
      if (_mode.hasLeadHalf) {
        await _fetchCard();
      }
      if (mounted) {
        MagicToast.show(
          context,
          'Задача добавлена',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка добавления',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _addingTask = false);
    }
  }

  /// Opens the month containing the nearest upcoming lesson and keeps the
  /// schedule scoped to this client. With no future lesson it opens this month.
  void _openScheduleFromCard() {
    final now = DateTime.now();
    DateTime? bestDt;
    for (final l in _lessons) {
      final dt = DateTime.tryParse(l.scheduledAt ?? '');
      final id = l.id;
      if (dt == null || id == null || id.isEmpty || dt.isBefore(now)) continue;
      if (bestDt == null || dt.isBefore(bestDt)) {
        bestDt = dt;
      }
    }
    final clientType = _isStudent && _studentId.isNotEmpty ? 'student' : 'lead';
    final clientId = clientType == 'student' ? _studentId : _leadId;
    if (clientId.isEmpty) return;
    final date = bestDt ?? now;
    final name = [
      _leadData['first_name'],
      _leadData['last_name'],
    ].whereType<Object>().map((value) => value.toString()).join(' ').trim();
    ref
        .read(scheduleNavigationProvider.notifier)
        .focusClientMonth(
          date,
          clientType: clientType,
          clientId: clientId,
          clientName: name.isEmpty ? null : name,
        );
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(
          CrmNavigationRequest.schedule(
            date: date,
            clientType: clientType,
            clientId: clientId,
          ),
        );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_dirty ? true : null);
    }
    context.go('/admin');
  }
}
