part of 'create_lesson_dialog.dart';

extension _CreateLessonDialogView on _CreateLessonDialogState {
  Widget _scheduleConflictInspector() {
    final analysis = _scheduleAnalysis;
    final cs = Theme.of(context).colorScheme;
    if (analysis == null && _scheduleAnalysisError == null) {
      return const SizedBox.shrink();
    }
    final valid = analysis?.valid == true;
    return Container(
      key: const ValueKey('lesson-conflict-inspector'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: valid
            ? AppColor.success.withValues(alpha: 0.10)
            : AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: (valid ? AppColor.success : AppColor.danger).withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            valid ? 'Конфликтов нет' : 'Найдены конфликты',
            style: TextStyle(
              color: valid ? AppColor.success : cs.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_scheduleAnalysisError != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(_scheduleAnalysisError!),
          ],
          for (final violation in analysis?.violations ?? const [])
            _violationCard(
              title: violation.title,
              resource: violation.resourceLabel,
              lessonIds: violation.conflictingLessonIds,
            ),
          if ((analysis?.suggestions ?? const []).isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            const Text(
              'Подходящие варианты',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpace.sm),
            for (final suggestion in analysis!.suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: OutlinedButton(
                  key: ValueKey('lesson-suggestion-${suggestion.rank}'),
                  onPressed: _analyzingSchedule
                      ? null
                      : () => _applyScheduleSuggestion(suggestion),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_scheduleSuggestionLabel(suggestion)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _violationCard({
    required String title,
    required String resource,
    required List<String> lessonIds,
    BuildContext? dialogContext,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.danger.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(resource, style: const TextStyle(fontSize: 12)),
          if (lessonIds.isNotEmpty)
            Wrap(
              spacing: 4,
              children: [
                for (final (index, lessonId) in lessonIds.indexed)
                  EntityLinkText(
                    key: ValueKey('conflict-lesson-$lessonId'),
                    onPressed: () {
                      ref
                          .read(scheduleNavigationProvider.notifier)
                          .focus(_selectedDate, lessonId);
                      if (dialogContext != null) Navigator.pop(dialogContext);
                      Navigator.pop(context);
                    },
                    text: 'Открыть занятие ${index + 1}',
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLessonDialogView(BuildContext context) {
    if (_loading) {
      const loading = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryGold),
            SizedBox(height: 16),
            Text('Загрузка данных...'),
          ],
        ),
      );
      return widget.pageMode
          ? Scaffold(
              appBar: AppBar(title: Text(_dialogTitle)),
              body: const SafeArea(top: false, child: loading),
            )
          : const AlertDialog(content: loading);
    }

    final width = MediaQuery.sizeOf(context).width;
    final dialog = AlertDialog(
      insetPadding: widget.pageMode ? EdgeInsets.zero : null,
      shape: widget.pageMode
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      title: Row(
        children: [
          if (widget.pageMode) ...[
            const AppBackButton(),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(child: Text(_dialogTitle)),
        ],
      ),
      contentPadding: widget.pageMode
          ? const EdgeInsets.fromLTRB(16, 12, 16, 0)
          : null,
      content: SizedBox(
        width: widget.pageMode
            ? double.maxFinite
            : width > 760
            ? 680
            : width - 80,
        height: widget.pageMode ? double.maxFinite : null,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isGroupEdit)
                InputDecorator(
                  key: const ValueKey('lesson-group-field'),
                  decoration: const InputDecoration(
                    labelText: 'Группа *',
                    enabled: false,
                    helperText:
                        'Группа и замороженный состав сохраняются при переносе',
                  ),
                  child: Text(_groupName),
                )
              else
                SearchablePickerField(
                  key: const ValueKey('lesson-client-field'),
                  label: 'Клиент *',
                  placeholder: 'Не выбран',
                  hintText: 'Введите имя или ФИО клиента',
                  selectedId: _clientKey,
                  selectedLabel: _selectedClient == null
                      ? null
                      : '${_selectedClient!['label']} · ${_clientType == 'lead' ? 'Lead' : 'Student'}',
                  items: [for (final row in _clients) _clientItem(row)],
                  onSearch: (query) async {
                    final rows = await _crm.searchClientRefs(
                      q: query,
                      limit: 50,
                    );
                    return [for (final row in rows) _clientItem(row)];
                  },
                  isNullable: false,
                  enabled:
                      !_snapshotLocked &&
                      widget.leadId == null &&
                      widget.clientId == null,
                  onSelected: (item) {
                    final row = item?.data;
                    if (row == null) return;
                    _selectClient(row);
                  },
                ),
              const SizedBox(height: 16),
              _responsivePair(
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: ValueKey('lesson-branch-field:$_selectedBranchId'),
                  initialValue: _selectedBranchId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Филиал *'),
                  items: [
                    for (final branch in _branches)
                      DropdownMenuItem(
                        value: branch['id'].toString(),
                        child: Text(branch['name']?.toString() ?? 'Не указано'),
                      ),
                  ],
                  onChanged: (value) {
                    _updateFormState(() {
                      _selectedBranchId = value;
                      if (!_eligibleTeachers.any(
                        (teacher) =>
                            teacher['id']?.toString() == _selectedTeacherId,
                      )) {
                        _selectedTeacherId = null;
                      }
                      _selectedRoomId = null;
                      _rooms = [];
                      _decisionCatalog = null;
                      _settlementTypeKey = null;
                      _compensationRuleKey = null;
                    });
                    if (value != null) {
                      _loadRooms(value);
                      _loadDecisionCatalog(value);
                    }
                  },
                ),
                SearchablePickerField(
                  key: const ValueKey('lesson-room-field'),
                  label: 'Аудитория *',
                  placeholder: _eligibleRooms.isEmpty
                      ? 'Нет аудиторий в филиале'
                      : 'Выберите аудиторию',
                  enabled: _eligibleRooms.isNotEmpty,
                  selectedId: _selectedRoomId,
                  items: [
                    for (final room in _eligibleRooms)
                      SearchableSelectItem(
                        id: room['id'].toString(),
                        label: room['name']?.toString() ?? 'Не указано',
                        subtitle: 'Аудитория выбранного филиала',
                      ),
                  ],
                  onSelected: (item) =>
                      _updateFormState(() => _selectedRoomId = item?.id),
                ),
              ),
              const SizedBox(height: 16),
              SearchablePickerField(
                key: const ValueKey('lesson-teacher-field'),
                label: 'Преподаватель *',
                placeholder: 'Выберите преподавателя',
                hintText: 'Введите имя или ФИО преподавателя',
                selectedId: _selectedTeacherId,
                selectedLabel: _selectedTeacherId == null
                    ? null
                    : _getTeacherName(_selectedTeacherId),
                items: [
                  for (final teacher in _eligibleTeachers)
                    SearchableSelectItem(
                      id: teacher['id'].toString(),
                      label: _getTeacherNameFromData(teacher),
                      subtitle: 'Назначен в выбранный филиал',
                    ),
                ],
                isNullable: false,
                enabled: _eligibleTeachers.isNotEmpty,
                onSelected: (item) =>
                    _updateFormState(() => _selectedTeacherId = item?.id),
              ),
              if (_selectedBranchId != null && _eligibleTeachers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'В выбранный филиал не назначен ни один активный преподаватель.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_selectedBranchId != null) ...[
                const SizedBox(height: 8),
                Text(
                  key: const ValueKey('lesson-replacement-availability-hint'),
                  'Занятость проверим перед сохранением.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _responsivePair(_dateButton(), _timeButton()),
              const SizedBox(height: 16),
              KeyedSubtree(
                key: ValueKey('lesson-duration-selection-$_durationMinutes'),
                child: DropdownButtonFormField<int>(
                  menuMaxHeight: 256,
                  key: const ValueKey('lesson-duration-field'),
                  initialValue: _durationMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Длительность *',
                  ),
                  items: [
                    for (final minutes in _durationOptions)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text('$minutes мин'),
                      ),
                  ],
                  onChanged: (value) =>
                      _updateFormState(() => _durationMinutes = value ?? 60),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                key: const ValueKey('lesson-run-schedule-analyzer'),
                onPressed: _analyzingSchedule ? null : _analyzeCurrentSchedule,
                icon: _analyzingSchedule
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.rule_rounded),
                label: Text(
                  _analyzingSchedule
                      ? 'Проверяем расписание…'
                      : 'Проверить конфликты и варианты',
                ),
              ),
              if (!_saving &&
                  (_scheduleAnalysis != null ||
                      _scheduleAnalysisError != null)) ...[
                const SizedBox(height: AppSpace.md),
                _scheduleConflictInspector(),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('lesson-trial-toggle'),
                value: _isTrial,
                activeThumbColor: AppTheme.primaryGold,
                contentPadding: EdgeInsets.zero,
                title: const Text('Пробное занятие'),
                subtitle: Text(
                  _snapshotLocked
                      ? 'Маркер зафиксирован при создании'
                      : 'Не зависит от типа клиента и способа списания',
                ),
                onChanged: _snapshotLocked
                    ? null
                    : (value) => _updateFormState(() => _isTrial = value),
              ),
              const Divider(height: 28),
              Text(
                'Результат и расчёты',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (_snapshotLocked)
                InputDecorator(
                  key: const ValueKey('lesson-completion-type-field'),
                  decoration: const InputDecoration(
                    labelText: 'Автозавершение *',
                    enabled: false,
                    helperText: 'Результат зафиксирован при создании',
                  ),
                  child: Text(
                    _completionType == 'standard.success'
                        ? 'Успешно завершить'
                        : _completionType,
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const ValueKey('lesson-completion-type-field'),
                  initialValue: _completionType,
                  decoration: const InputDecoration(
                    labelText: 'Автозавершение *',
                    helperText:
                        'Результат формируется сервером после окончания',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'standard.success',
                      child: Text('Успешно завершить'),
                    ),
                  ],
                  onChanged: (value) => _updateFormState(
                    () => _completionType = value ?? 'standard.success',
                  ),
                ),
              const SizedBox(height: 16),
              _responsivePair(
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const ValueKey('lesson-settlement-type-field'),
                  initialValue: _settlementTypeKey,
                  decoration: const InputDecoration(
                    labelText: 'Тип списания *',
                    helperText: 'Выбирается до назначения занятия',
                  ),
                  items: [
                    for (final item
                        in _decisionCatalog?.settlementTypes ?? const [])
                      DropdownMenuItem(
                        value: item.key,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: _snapshotLocked
                      ? null
                      : (value) => _updateFormState(() {
                          _settlementTypeKey = value;
                          _applyFundingDefault();
                        }),
                ),
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const ValueKey('lesson-compensation-rule-field'),
                  initialValue: _compensationRuleKey,
                  decoration: const InputDecoration(
                    labelText: 'Правило оплаты преподавателю *',
                    helperText:
                        'Значение можно задать отдельно для этого занятия',
                  ),
                  items: [
                    for (final item
                        in _decisionCatalog?.compensationRules ?? const [])
                      DropdownMenuItem(
                        value: item.key,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: _saving ? null : _selectCompensationRule,
                ),
              ),
              if (_selectedCompensationRule case final rule?
                  when rule.mode == 'percent' ||
                      rule.mode == 'fixed' ||
                      rule.mode == 'hourly') ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('lesson-compensation-value-field'),
                  controller: _compensationValueController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,. ]')),
                  ],
                  decoration: InputDecoration(
                    labelText: rule.mode == 'percent'
                        ? 'Процент от стандартной ставки, % *'
                        : rule.mode == 'hourly'
                        ? 'Почасовая ставка, ₽ *'
                        : 'Фиксированная сумма за занятие, ₽ *',
                    helperText: 'Действует только для этого занятия',
                  ),
                  onChanged: (_) => _updateFormState(() {}),
                ),
                if (!_isEdit && _compensationNeedsReason) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey(
                      'lesson-compensation-override-reason-field',
                    ),
                    controller: _plannedSettlementReasonController,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Причина индивидуального значения *',
                      helperText: 'Причина сохранится в истории расчёта',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const ValueKey('lesson-charge-type-field'),
                initialValue: _clientChargeType,
                decoration: const InputDecoration(
                  labelText: 'Источник средств *',
                  helperText: 'Сумму и долю определяет выбранный тип списания',
                ),
                items: [
                  if (_clientType == 'student' &&
                      (_subscriptions.isNotEmpty ||
                          _clientChargeType == 'subscription'))
                    const DropdownMenuItem(
                      value: 'subscription',
                      child: Text('С абонемента'),
                    ),
                  const DropdownMenuItem(
                    value: 'personal_account',
                    child: Text('С личного счёта'),
                  ),
                  if (_selectedSettlementIsNoCharge ||
                      (_snapshotLocked && _clientChargeType == 'none'))
                    const DropdownMenuItem(
                      value: 'none',
                      child: Text('Без списания'),
                    ),
                ],
                onChanged: _snapshotLocked
                    ? null
                    : (value) => _updateFormState(() {
                        _clientChargeType = value ?? 'none';
                        if (_clientChargeType == 'subscription') {
                          _selectedSubscriptionId ??= _subscriptions
                              .firstOrNull?['id']
                              ?.toString();
                        }
                      }),
              ),
              if (_clientChargeType == 'subscription') ...[
                const SizedBox(height: 16),
                SearchablePickerField(
                  label: 'Абонемент *',
                  placeholder: _subscriptions.isEmpty
                      ? 'Нет активных абонементов'
                      : 'Выберите абонемент',
                  enabled: !_snapshotLocked && _subscriptions.isNotEmpty,
                  selectedId: _selectedSubscriptionId,
                  items: [
                    for (final subscription in _subscriptions)
                      SearchableSelectItem(
                        id: subscription['id'].toString(),
                        label: _subscriptionLabel(subscription),
                      ),
                  ],
                  onSelected: (item) => _updateFormState(
                    () => _selectedSubscriptionId = item?.id,
                  ),
                ),
              ],
              if (!_snapshotLocked) ...[
                const SizedBox(height: 16),
                _buildSnapshotPreview(),
              ],
              if (_snapshotLocked) ...[
                const SizedBox(height: 10),
                Text(
                  'Клиент и списание уже зафиксированы. Остальные данные '
                  'можно изменить после подтверждения.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_validationMessage case final message?) ...[
                const SizedBox(height: AppSpace.md),
                Container(
                  key: const ValueKey('lesson-form-validation-error'),
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColor.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(
                      color: AppColor.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Перейти к расчёту' : 'Создать'),
        ),
      ],
    );
    return widget.pageMode ? SafeArea(child: dialog) : dialog;
  }

  Widget _buildSnapshotPreview() {
    final cs = Theme.of(context).colorScheme;
    final clientLabel = _selectedSettlementType?.label ?? 'Не выбран';
    final compensationLabel = _selectedCompensationRule?.label ?? 'Не выбрано';
    return Container(
      key: const ValueKey('lesson-snapshot-preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.gold.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Расчёты перед созданием',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Проверьте расчёты. При переносе они не изменятся.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.md),
          _snapshotPreviewRow(
            key: const ValueKey('lesson-snapshot-trial'),
            label: 'Тип занятия',
            value: _isTrial ? 'Пробное' : 'Обычное',
          ),
          _snapshotPreviewRow(
            key: const ValueKey('lesson-snapshot-client-charge'),
            label: 'Списание клиента',
            value: '$clientLabel · $_clientSnapshotValue',
          ),
          _snapshotPreviewRow(
            key: const ValueKey('lesson-snapshot-teacher-compensation'),
            label: 'Оплата преподавателю',
            value: '$compensationLabel · $_teacherSnapshotValue',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _snapshotPreviewRow({
    required Key key,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: key,
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _responsivePair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _dateButton() {
    return OutlinedButton.icon(
      key: const ValueKey('lesson-date-field'),
      onPressed: () async {
        final now = DateTime.now();
        final rollingLowerBound = DateTime(now.year, now.month, now.day - 30);
        final selectedDateIsOlder = _selectedDate.isBefore(rollingLowerBound);
        final allowOlderEditDate = _isEdit && selectedDateIsOlder;
        final date = await showDatePicker(
          context: context,
          initialDate: selectedDateIsOlder && !_isEdit
              ? rollingLowerBound
              : _selectedDate,
          firstDate: allowOlderEditDate ? _selectedDate : rollingLowerBound,
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) _updateFormState(() => _selectedDate = date);
      },
      icon: const Icon(Icons.calendar_today_rounded, size: 18),
      label: Text(DateFormat('dd.MM.yyyy', 'ru').format(_selectedDate)),
    );
  }

  Widget _timeButton() {
    return OutlinedButton.icon(
      key: const ValueKey('lesson-time-field'),
      onPressed: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: _selectedTime,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (time != null) _updateFormState(() => _selectedTime = time);
      },
      icon: const Icon(Icons.access_time_rounded, size: 18),
      label: Text(_selectedTime.format(context)),
    );
  }
}
