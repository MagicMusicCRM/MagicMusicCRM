part of 'client_card.dart';

extension _ClientCardDesktopDashboard on _ClientCardState {
  Widget _buildDesktopIdentitySidebar(
    ColorScheme cs, {
    required bool canReadSchedule,
    required bool canWriteSchedule,
  }) {
    final snapshot = widget.capabilitySnapshot;
    return SizedBox(
      width: 272,
      child: Theme(
        data: clientCardControlTheme(Theme.of(context)).copyWith(
          textTheme: Theme.of(context).textTheme.copyWith(
            bodyLarge: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontSize: 14),
          ),
        ),
        child: ListView(
          key: const Key('client-desktop-actions-and-contacts'),
          padding: const EdgeInsets.all(12),
          children: [
            const _ClientSidebarHeading('Действия'),
            if (_isStudent && _canWriteClient)
              _desktopAction(
                'client-add-to-group',
                Icons.group_add_outlined,
                'Добавить в группу',
                _addingToGroup ? null : _addClientToGroup,
              ),
            if (canWriteSchedule)
              _desktopAction(
                'client-book-trial',
                Icons.event_available_outlined,
                'Записать на пробное занятие',
                _bookClientTrial,
              ),
            if (canReadSchedule)
              _desktopAction(
                'client-open-schedule',
                Icons.calendar_month_outlined,
                'Открыть расписание',
                _openScheduleFromCard,
              ),
            if (_canWriteClient &&
                (snapshot?.allows('commerce.client_finance.write') ??
                    crmHasManagerAccess(_currentActorRole() ?? '')))
              _desktopAction(
                'client-sell-subscription',
                Icons.confirmation_number_outlined,
                'Продать абонемент',
                _converting ? null : _showIssueSubscriptionSheet,
              ),
            const SizedBox(height: 14),
            const _ClientSidebarHeading('Контакты'),
            _buildClientContactFields(cs),
            _buildContactPersonsEditor(cs, _isStudent ? 'students' : 'leads'),
            if (_isStudent && _groups.isNotEmpty) ...[
              const SizedBox(height: 8),
              _studentGroupsInfoCard(groups: _groups),
            ],
          ],
        ),
      ),
    );
  }

  Widget _desktopAction(
    String key,
    IconData icon,
    String label,
    VoidCallback? onPressed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: OutlinedButton.icon(
      key: Key(key),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        foregroundColor: AppColor.text,
      ),
      icon: Icon(icon, size: 18, color: AppColor.gold),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    ),
  );

  Widget _buildClientContactFields(ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: RuPhoneField(
          key: ValueKey('client-phone-$_editorEpoch'),
          initialCanonical: _clientPhone,
          enabled: _canWriteClient,
          decoration: _inputDecoration(cs, label: 'Телефон', isDense: true),
          onCanonicalChanged: (value) =>
              _updateClientCore('phone', value.isEmpty ? null : value),
        ),
      ),
      _buildClientTextField(
        cs,
        'Электронная почта',
        _clientEmail,
        (value) => _updateClientCore('email', value),
        keyboard: TextInputType.emailAddress,
        errorText: _clientEmailWasEdited ? _clientEmailValidationError : null,
      ),
    ],
  );

  Widget _buildClientNoteEditor({bool compact = false}) => Theme(
    data: clientCardControlTheme(Theme.of(context), compact: compact),
    child: ClientInternalNoteCard(
      compact: compact,
      loading: _internalContextLoading,
      error: _internalContextError,
      note: _internalNote,
      onSave: _saveInternalNote,
      onReload: _reloadInternalNote,
      onRetry: _fetchInternalContext,
      onPendingChanged: (pending) {
        if (!mounted || pending == _internalNotePending) return;
        _emitState(() => _internalNotePending = pending);
      },
      onFlushChanged: (flush) => _flushInternalNote = flush,
      initialDraft: _workspaceInternalNoteDraft,
      onDraftChanged: (draft) {
        _workspaceInternalNoteDraft = draft;
        _internalNoteIsPending = draft != null;
        _syncWorkspaceFormDirty();
      },
    ),
  );

  Set<String> get _desktopPrimaryKeys => {
    ..._ClientCardState._primaryBusinessCustomFieldKeys,
    for (final field in _customFieldSchema)
      if (field.entity == (_isStudent ? 'students' : 'leads') && field.required)
        field.key,
  }..removeAll(_ClientCardState._customKeysWithDedicatedEditor);

  Widget _buildDesktopClientFields(ColorScheme cs, StatusRecord currentStatus) {
    final entity = _isStudent ? 'students' : 'leads';
    final fields = <(Widget, int)>[
      if (_mode.hasLeadHalf) (_buildStatusPicker(cs, currentStatus), 1),
      if (_mode.hasStudentHalf)
        (_buildStudentStatusPicker(cs, compact: true), 1),
      if (!_loadingMetadata) ...[
        (_buildBranchDropdown(cs, 'Основной филиал', compact: true), 1),
        (_buildSourceDropdown(cs, compact: true), 1),
        (_buildResponsiblePicker(cs, entity), 1),
        if (_customFieldSchema.any((f) => f.entity == entity && f.key == 'age'))
          (_buildAgeCustomField(cs, entity), 1),
        (_buildDisciplinesChips(cs, entity), 2),
        for (final field in _customFieldSchema)
          if (field.entity == entity &&
              _desktopPrimaryKeys.contains(field.key) &&
              !field.isSystem &&
              !_isSystemOnlyCustomField(field.key) &&
              (field.placements.contains('edit') ||
                  field.placements.contains('card')))
            (
              KeyedSubtree(
                key: ValueKey('custom-field-layout-${field.key}'),
                child: _buildCustomFieldControl(cs, field, compact: true),
              ),
              field.type == 'textarea' ||
                      field.type == 'checkbox_group' ||
                      field.type == 'multi_select'
                  ? 2
                  : 1,
            ),
      ],
    ];
    return Theme(
      data: clientCardControlTheme(Theme.of(context), compact: true).copyWith(
        textTheme: Theme.of(context).textTheme.copyWith(
          bodyLarge: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontSize: 14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadingMetadata) const LinearProgressIndicator(),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 860
                    ? 4
                    : constraints.maxWidth >= 600
                    ? 3
                    : 2;
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: width * field.$2 + 12 * (field.$2 - 1),
                        child: field.$1,
                      ),
                  ],
                );
              },
            ),
            _buildCustomFieldsExpansion(
              cs,
              excludedKeys: _desktopPrimaryKeys,
              compact: true,
            ),
            if (_appealAtLabel(_isStudent ? _student! : _leadData)
                case final date?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Дата обращения: $date'
                  '${_visitDateLabel() == null ? '' : ' · Дата визита: ${_visitDateLabel()}'}',
                  style: const TextStyle(fontSize: 12, color: AppColor.text2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopClientAdministration(ColorScheme cs) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBlacklistToggle(cs),
        ClientAppUserPanel(
          entityType: _isStudent ? 'student' : 'lead',
          entityId: _isStudent ? _studentId : _leadId,
        ),
        if (_mode.hasLeadHalf) ...[
          _buildAggregateCard(cs, includeTasks: false),
          if (_loadingDuplicates ||
              _duplicateCandidates.any(_isCurrentLeadDuplicateCandidate))
            _duplicateCandidatesSection(
              cs,
              candidates: _duplicateCandidates
                  .where(_isCurrentLeadDuplicateCandidate)
                  .toList(),
              loading: _loadingDuplicates,
              pendingId: _duplicateDecisionId,
              onAttach: _attachDuplicateCandidate,
            ),
        ],
      ],
    ),
  );

  Future<void> _bookClientTrial() async {
    final access = ClientCardAccessPolicy.project(
      actorRole: _currentActorRole() ?? '',
      capabilitySnapshot: widget.capabilitySnapshot,
      hasStudentHalf: _isStudent,
    );
    if (!access.canWriteSchedule) return;
    final saved = await CreateLessonDialog.show(
      context,
      clientType: _isStudent ? 'student' : 'lead',
      clientId: _isStudent ? _studentId : _leadId,
      clientName: _clientPresentationLabel,
      leadId: _isStudent ? null : _leadId,
      leadName: _isStudent ? null : _clientPresentationLabel,
      initialBranchId: _clientBranchId,
      initialIsTrial: true,
    );
    if (saved == true && mounted) await _refreshClientLessonData();
  }

  Future<void> _addClientToGroup() async {
    if (!_isStudent || !_canWriteClient || _addingToGroup) return;
    _emitState(() => _addingToGroup = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final groups = await crm.listGroups(
        branchId: _clientBranchId,
        limit: 100,
      );
      if (!mounted) return;
      final existingIds = {
        for (final group in _groups) group['id']?.toString(),
      };
      final available = groups
          .where((g) => !existingIds.contains(g['id']?.toString()))
          .toList();
      SearchableSelectItem? selected;
      await SearchableSelect.show(
        context: context,
        title: 'Добавить в группу',
        hintText: 'Название группы…',
        isNullable: false,
        items: [
          for (final group in available)
            SearchableSelectItem(
              id: group['id'].toString(),
              label: group['name']?.toString() ?? 'Группа',
            ),
        ],
        onSearch: (query) async {
          final matches = await crm.listGroups(
            branchId: _clientBranchId,
            search: query,
          );
          return [
            for (final group in matches)
              if (!existingIds.contains(group['id']?.toString()))
                SearchableSelectItem(
                  id: group['id'].toString(),
                  label: group['name']?.toString() ?? 'Группа',
                ),
          ];
        },
        onSelected: (item) => selected = item,
      );
      if (!mounted || selected == null || !_canWriteClient) return;
      await crm.addGroupStudent(groupId: selected!.id, studentId: _studentId);
      await _fetchStudentData(preserveVisibleContent: true);
      ref.invalidate(studentBoardProvider);
      if (mounted) {
        MagicToast.show(
          context,
          'Ученик добавлен в группу',
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось добавить в группу',
          detail: userErrorMessage(error),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _addingToGroup = false);
    }
  }
}

class _ClientSidebarHeading extends StatelessWidget {
  const _ClientSidebarHeading(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  );
}
