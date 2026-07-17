part of 'client_card.dart';

extension _ClientCardTabsA on _ClientCardState {
  /// В чёрном ли списке клиент — по любой из половин карточки. Сервер отдаёт
  /// флаг на каждой (см. blacklist.ts); достаточно одной, чтобы это был бан.
  bool get _isBlacklisted =>
      _student?['blacklisted'] == true || _leadData['blacklisted'] == true;

  String? get _blacklistReason {
    final fromStudent = _student?['blacklist_reason']?.toString();
    if (fromStudent != null && fromStudent.trim().isNotEmpty) return fromStudent;
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
      margin: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.md),
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
            onPressed: _handleClose,
            icon: const Icon(Icons.close_rounded),
            iconSize: 20,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpace.sm),
              _buildTabChip(cs, i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(ColorScheme cs, int index) {
    final selected = _tabIndex == index;
    final (icon, label) = _tabs[index];
    return Material(
      color: selected ? AppColor.goldSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: () => _emitState(() => _tabIndex = index),
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
            // Hide «Создать ученика» once a linked student exists (the card is
            // — or is about to become — converted): the conversion already
            // happened. `_isConverted` covers the resolved case; the
            // linked_students check covers the brief window before resolution
            // flips the mode.
            if (!_isConverted && !_hasLinkedStudent)
              OutlinedButton.icon(
                onPressed: _saving || _converting ? null : _convertToStudent,
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
                    : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Создать ученика'),
              ),
            // «Прикрепить к ученику» (§1 спеки). Рядом с «Создать ученика»,
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
            TextButton(
              onPressed: _saving || _converting ? null : _handleClose,
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              child: const Text('Отмена'),
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
            ..._buildCustomFieldControls(
              cs,
              _isStudent ? 'students' : 'leads',
              includeKeys: _ClientCardState._commonClientCustomFieldKeys,
              excludedKeys: _ClientCardState._customKeysWithDedicatedEditor,
            ),
            // Возраст: поле ввода, пока нет даты рождения, иначе — посчитанное
            // сервером значение только на просмотр.
            _buildAgeCustomField(cs, _isStudent ? 'students' : 'leads'),
            // KVA-234: мультидисциплины чипами + список контактных лиц.
            _buildDisciplinesChips(cs, _isStudent ? 'students' : 'leads'),
            _buildContactPersonsEditor(cs, _isStudent ? 'students' : 'leads'),
            // Чёрный список — у обеих половин карточки, а не только у ученика:
            // аккаунт клиента цепляется к любой из них.
            _buildBlacklistToggle(cs),
          ],

          if (_mode.hasStudentHalf) ...[
            const SizedBox(height: AppSpace.lg),
            _sectionTitle('Поля ученика'),
            if (_loadingMetadata)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(color: AppColor.gold),
                ),
              )
            else
              ..._buildCustomFieldControls(
                cs,
                'students',
                includeKeys: _ClientCardState._studentOnlyCustomFieldKeys,
              ),
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
            if (_subscriptions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Абонементы', [
                for (final s in _subscriptions.take(5))
                  _InfoRow(
                    icon: s.isActive
                        ? Icons.confirmation_number_outlined
                        : Icons.history_toggle_off_rounded,
                    label: (s.packageName?.trim().isNotEmpty ?? false)
                        ? s.packageName!
                        : 'Абонемент',
                    value: [
                      _subscriptionRemainder(s),
                      // «Курс» — the whole subscription, next to what is left
                      // of it, as on the reference card.
                      ?_subscriptionCourse(s),
                      // «Оплачено» — приход личного счёта за этот абонемент.
                      ?_subscriptionPaid(s),
                    ].join('\n'),
                    // «Переплата»/«Долг» — разница между приходом и стоимостью.
                    // Красным, потому что это то, на что надо посмотреть.
                    hint: _subscriptionOverpayment(s)?.label,
                    hintColor: _subscriptionOverpayment(s)?.isDebt == true
                        ? AppTheme.danger
                        : AppTheme.success,
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
          if (_mode.hasStudentHalf && !_mode.hasLeadHalf && _student != null) ...[
            if (_appealAtLabel(_student!) != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Обращение', [
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Дата обращения',
                  value: _appealAtLabel(_student!)!,
                  hint: _appealAtSourceLabel(_student!),
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
              ]),
            ],
            const SizedBox(height: AppSpace.lg),
            _sectionTitle('Заметки'),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: _inputDecoration(
                cs,
                hint: 'Общие примечания по клиенту...',
              ),
            ),
          ],

          // Данные из HolliHop, которым нет отдельной строки/пикера, но которые
          // залиты в custom_data (ответственный, статус HH, рекл. источник,
          // тип/дата обращения, контакты родителей, UTM, тип лида). Секция сама
          // прячется, если ни одно поле не заполнено.
          _buildExtraInfoCard(cs),

          const SizedBox(height: AppSpace.lg),
          ClientAppUserPanel(
            entityType: _mode.hasStudentHalf ? 'student' : 'lead',
            entityId: _mode.hasStudentHalf ? _studentId : _leadId,
          ),

          const SizedBox(height: AppSpace.lg),
          _sectionTitle('Связи и активность'),
          _buildAggregateCard(cs, includeTasks: false),

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

  String? _utmLabel() {
    final parts = [
      _hhField('utmSource'),
      _hhField('utmMedium'),
      _hhField('utmCampaign'),
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' / ');
  }

  Widget _buildExtraInfoCard(ColorScheme cs) {
    final rows = <Widget>[];
    void add(IconData icon, String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      rows.add(_InfoRow(icon: icon, label: label, value: value));
    }

    add(Icons.person_pin_outlined, 'Ответственный', _responsibleLabel());
    add(Icons.flag_outlined, 'Статус (HolliHop)', _hhField('statusName'));
    add(Icons.campaign_outlined, 'Рекламный источник', _hhField('adSource'));
    add(Icons.call_outlined, 'Тип обращения', _hhField('addressType'));
    add(Icons.event_available_outlined, 'Дата визита', _visitDateLabel());
    add(Icons.family_restroom_outlined, 'Контактные лица', _hhField('contacts'));
    // Тип лида / UTM — только для лид-стороны (у ученика их нет).
    if (_mode.hasLeadHalf) {
      add(Icons.sell_outlined, 'Тип лида', _hhField('leadType'));
      add(Icons.link_outlined, 'UTM', _utmLabel());
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: _buildInfoCard('Дополнительно', rows),
    );
  }

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
            ...tasks.map(
              (row) => _entityTile(
                cs,
                title: row['title']?.toString() ?? 'Задача',
                subtitle: _formatStatus(row['status']),
                leading: Icons.task_alt_rounded,
              ),
            ),
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

  /// «Записать на пробный урок» прямо из карточки лида — тот же диалог, что в
  /// меню канбан-доски (leads_widget._scheduleTrial).
  Future<void> _scheduleTrialFromCard() async {
    await bookTrialLesson(
      context,
      ref,
      leadId: _leadId,
      leadName: _leadData['name']?.toString() ?? '',
      feedback: (message, {detail, ok = false}) => MagicToast.show(
        context,
        message,
        detail: detail,
        type: ok ? MagicToastType.success : MagicToastType.danger,
      ),
      onBooked: () async {
        _dirty = true;
        await _fetchCard();
      },
    );
  }
}
