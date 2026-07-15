part of 'client_card.dart';

extension _ClientCardTabsA on _ClientCardState {
  Widget _buildHeader(ColorScheme cs, StatusRecord curStatus) {
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
              color: AppColor.goldSoft,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(color: AppColor.goldLine),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              size: 22,
              color: AppColor.gold,
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
              key: ValueKey('client-phone-${_clientPhone ?? ''}'),
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
            // KVA-234: мультидисциплины чипами + список контактных лиц.
            _buildDisciplinesChips(cs, _isStudent ? 'students' : 'leads'),
            _buildContactPersonsEditor(cs, _isStudent ? 'students' : 'leads'),
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
                  value: '${_balance!['total_paid']} ₽',
                ),
                _InfoRow(
                  icon: Icons.history_edu_outlined,
                  label: 'Списано за уроки',
                  value: '${_balance!['total_cost']} ₽',
                ),
                _InfoRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Баланс',
                  value: '${_balance!['balance']} ₽',
                ),
              ]),
            ],
            if (_subscriptions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Абонементы', [
                for (final s in _subscriptions.take(5))
                  _InfoRow(
                    icon: s['status'] == 'active'
                        ? Icons.confirmation_number_outlined
                        : Icons.history_toggle_off_rounded,
                    label:
                        (s['package_name']?.toString().trim().isNotEmpty ??
                            false)
                        ? s['package_name'].toString()
                        : 'Абонемент',
                    value: _subscriptionRemainder(s),
                  ),
              ]),
            ],
            if (_studentId.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              StudentScheduleSection(
                studentId: _studentId,
                lessons: _lessons,
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

          if (_mode.hasLeadHalf) ...[
            if (_leadCreatedAtLabel() != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Обращение', [
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Дата обращения',
                  value: _leadCreatedAtLabel()!,
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
