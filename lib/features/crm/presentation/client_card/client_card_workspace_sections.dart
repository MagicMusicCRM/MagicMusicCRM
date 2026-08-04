part of 'client_card.dart';

extension _ClientCardWorkspaceSections on _ClientCardState {
  Widget _buildWorkspaceSection(
    ColorScheme cs,
    StatusRecord currentStatus,
    String section, {
    required bool canReadClientFinance,
    required bool canReadSchedule,
    required bool canWriteSchedule,
  }) {
    return switch (section) {
      'overview' => _buildClientInfoTab(cs, currentStatus),
      'lessons' when _isStudent => _buildLessonsTab(
        cs,
        canReadSchedule: canReadSchedule,
        canWriteSchedule: canWriteSchedule,
      ),
      'lessons' => _buildLeadLessonsTab(
        cs,
        canReadSchedule: canReadSchedule,
        canWriteSchedule: canWriteSchedule,
      ),
      'payments' when _isStudent && canReadClientFinance => _buildPaymentsTab(
        cs,
      ),
      'subscriptions' when _isStudent => _buildSubscriptionsTab(cs),
      'history_tasks' => _buildHistoryAndTasksTab(cs),
      'contacts' => _buildFamilyTab(cs),
      'documents' => const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Документов пока нет',
        message: 'Поддерживаемые документы появятся в этом разделе.',
      ),
      'custom_fields' => _buildCustomFieldsTab(cs),
      _ => _buildClientInfoTab(cs, currentStatus),
    };
  }

  Widget _buildLeadLessonsTab(
    ColorScheme cs, {
    required bool canReadSchedule,
    required bool canWriteSchedule,
  }) {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.xl),
      children: [
        StudentScheduleSection(
          clientType: 'lead',
          clientId: _leadId,
          lessons: const [],
          branches: _branches,
          defaultBranchId: _clientBranchId,
          legacyPreference: _customDataForEntity(
            'leads',
          )['preferredSchedule']?.toString(),
          canWrite: canWriteSchedule,
          onChanged: () {},
        ),
        const SizedBox(height: AppSpace.lg),
        ClientScheduleCalendar(
          clientType: 'lead',
          clientId: _leadId,
          clientName: [
            _clientFirstName,
            _clientLastName,
          ].whereType<String>().join(' '),
          branches: _branches,
          defaultBranchId: _clientBranchId,
          canRead: canReadSchedule,
          active: _selectedSection == 'lessons',
          initialViewState: widget.initialViewState,
          onViewStateChanged: widget.onViewStateChanged,
        ),
      ],
    );
  }

  Widget _buildHistoryAndTasksTab(ColorScheme cs) {
    final tabs = _isStudent
        ? <(String, Widget)>[
            ('Задачи', _buildStudentTasksTab(cs)),
            ('Комментарии', _buildCommentsTab(cs)),
            ('История', _buildStudentHistoryTab(cs)),
            ('Прогресс', _buildProgressTab(cs)),
          ]
        : <(String, Widget)>[
            ('Задачи', _buildTasksTab(cs)),
            ('Комментарии', _buildCommentsTab(cs)),
            ('История', _buildHistoryTab(cs)),
            ('Прогресс', _buildLeadProgressTab(cs)),
          ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
          Expanded(
            child: TabBarView(children: [for (final tab in tabs) tab.$2]),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionsTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      if (_subscriptions.isEmpty) {
        return const MagicPageState(
          kind: MagicPageStateKind.empty,
          title: 'Абонементов пока нет',
        );
      }
      return ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          _sectionTitle('Абонементы'),
          _buildInfoCard('Выданные абонементы', [
            for (final subscription in _subscriptions)
              _InfoRow(
                icon: subscription.isActive
                    ? Icons.confirmation_number_outlined
                    : Icons.history_toggle_off_rounded,
                label: (subscription.packageName?.trim().isNotEmpty ?? false)
                    ? subscription.packageName!
                    : 'Абонемент',
                value: [
                  _subscriptionRemainder(subscription),
                  ?_subscriptionCourse(subscription),
                  ?_subscriptionPaid(subscription),
                ].join('\n'),
                hint: _subscriptionOverpayment(subscription)?.label,
                hintColor:
                    _subscriptionOverpayment(subscription)?.isDebt == true
                    ? AppTheme.danger
                    : AppTheme.success,
                trailing:
                    subscription.isActive &&
                        (subscription.id?.isNotEmpty ?? false)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('subscription-replace-${subscription.id}'),
                            tooltip: 'Заменить абонемент',
                            onPressed:
                                _replacingSubscription ||
                                    _cancellingSubscription
                                ? null
                                : () => _showReplaceSubscriptionFlow(
                                    subscription,
                                  ),
                            icon: const Icon(
                              Icons.swap_horiz_rounded,
                              color: AppColor.gold,
                            ),
                          ),
                          IconButton(
                            key: Key('subscription-cancel-${subscription.id}'),
                            tooltip: 'Отменить абонемент',
                            onPressed:
                                _replacingSubscription ||
                                    _cancellingSubscription
                                ? null
                                : () =>
                                      _showCancelSubscriptionFlow(subscription),
                            icon: const Icon(
                              Icons.cancel_outlined,
                              color: AppColor.danger,
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
          ]),
        ],
      );
    });
  }

  Widget _buildCustomFieldsTab(ColorScheme cs) {
    if (_loadingMetadata) return const MagicPageState.loading();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Дополнительные поля'),
          ..._buildCustomFieldControls(
            cs,
            _isStudent ? 'students' : 'leads',
            includeKeys: _ClientCardState._commonClientCustomFieldKeys,
            excludedKeys: _ClientCardState._customKeysWithDedicatedEditor,
          ),
          if (_isStudent) ...[
            const SizedBox(height: AppSpace.lg),
            _sectionTitle('Поля ученика'),
            ..._buildCustomFieldControls(
              cs,
              'students',
              includeKeys: _ClientCardState._studentOnlyCustomFieldKeys,
            ),
          ],
        ],
      ),
    );
  }
}
