part of 'client_card.dart';

extension _ClientCardWorkspaceSections on _ClientCardState {
  Widget _buildDesktopWorkspaceCanvas(
    ColorScheme cs,
    StatusRecord currentStatus,
    List<(IconData, String, String)> tabs, {
    required bool canReadClientFinance,
    required bool canReadSchedule,
    required bool canWriteSchedule,
    required bool canReadTasks,
  }) {
    return ColoredBox(
      color: cs.surfaceContainerLowest,
      child: MagicDesktopScrollbar(
        axis: Axis.vertical,
        controller: _desktopScrollController,
        builder: (context, controller) => SingleChildScrollView(
          key: const Key('client-desktop-canvas'),
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.xl,
            AppSpace.xl + AppSpace.sm,
            AppSpace.xxl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDesktopSectionJumps(cs, tabs),
                    const SizedBox(height: AppSpace.lg),
                    _buildDesktopCardLayout(
                      cs,
                      currentStatus,
                      tabs,
                      wide: constraints.maxWidth >= 1120,
                      canReadClientFinance: canReadClientFinance,
                      canReadSchedule: canReadSchedule,
                      canWriteSchedule: canWriteSchedule,
                      canReadTasks: canReadTasks,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSectionJumps(
    ColorScheme cs,
    List<(IconData, String, String)> tabs,
  ) {
    return Semantics(
      container: true,
      label: 'Быстрый переход по карточке клиента',
      child: Container(
        key: const Key('client-desktop-section-jumps'),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final tab in tabs)
              Semantics(
                button: true,
                selected: _selectedSection == tab.$3,
                child: OutlinedButton.icon(
                  key: Key('client-section-jump-${tab.$3}'),
                  onPressed: () => _selectSection(tab.$3),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _selectedSection == tab.$3
                        ? AppColor.goldSoft
                        : null,
                  ),
                  icon: Icon(tab.$1, size: 16),
                  label: Text('→ ${tab.$2}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopCardLayout(
    ColorScheme cs,
    StatusRecord currentStatus,
    List<(IconData, String, String)> tabs, {
    required bool wide,
    required bool canReadClientFinance,
    required bool canReadSchedule,
    required bool canWriteSchedule,
    required bool canReadTasks,
  }) {
    final bySection = {for (final tab in tabs) tab.$3: tab};
    Widget card((IconData, String, String) tab) => _desktopSectionCard(
      cs,
      key: _desktopSectionKeys[tab.$3]!,
      section: tab.$3,
      icon: tab.$1,
      title: tab.$2,
      child: _buildDesktopWorkspaceSection(
        cs,
        currentStatus,
        tab.$3,
        canReadClientFinance: canReadClientFinance,
        canReadSchedule: canReadSchedule,
        canWriteSchedule: canWriteSchedule,
        canReadTasks: canReadTasks,
      ),
    );

    if (!wide) {
      return Column(
        children: [
          for (var index = 0; index < tabs.length; index++) ...[
            card(tabs[index]),
            if (index < tabs.length - 1) const SizedBox(height: AppSpace.lg),
          ],
        ],
      );
    }

    final blocks = <Widget>[];
    void add(Widget child) {
      if (blocks.isNotEmpty) blocks.add(const SizedBox(height: AppSpace.lg));
      blocks.add(child);
    }

    final overview = bySection['overview'];
    final contacts = bySection['contacts'];
    if (overview != null && contacts != null) {
      add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: card(overview)),
            const SizedBox(width: AppSpace.lg),
            Expanded(child: card(contacts)),
          ],
        ),
      );
    } else if (overview != null) {
      add(card(overview));
    }

    final lessons = bySection['lessons'];
    if (lessons != null) add(card(lessons));

    final subscriptions = bySection['subscriptions'];
    final progress = bySection['progress'];
    if (wide && subscriptions != null && progress != null) {
      add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: card(subscriptions)),
            const SizedBox(width: AppSpace.lg),
            Expanded(child: card(progress)),
          ],
        ),
      );
    } else {
      if (subscriptions != null) add(card(subscriptions));
      if (progress != null) add(card(progress));
    }

    final payments = bySection['payments'];
    if (payments != null) add(card(payments));

    for (final section in const ['history_tasks', 'documents']) {
      final tab = bySection[section];
      if (tab != null) add(card(tab));
    }
    return Column(children: blocks);
  }

  Widget _buildDesktopWorkspaceSection(
    ColorScheme cs,
    StatusRecord currentStatus,
    String section, {
    required bool canReadClientFinance,
    required bool canReadSchedule,
    required bool canWriteSchedule,
    required bool canReadTasks,
  }) {
    return switch (section) {
      'overview' => _buildClientInfoTab(cs, currentStatus, embedded: true),
      'lessons' when _isStudent => _buildLessonsTab(
        cs,
        canReadSchedule: canReadSchedule,
        canWriteSchedule: canWriteSchedule,
        embedded: true,
      ),
      'lessons' => _buildLeadLessonsTab(
        cs,
        canReadSchedule: canReadSchedule,
        canWriteSchedule: canWriteSchedule,
        embedded: true,
      ),
      'payments' when _isStudent && canReadClientFinance => _buildPaymentsTab(
        cs,
        embedded: true,
      ),
      'subscriptions' => _buildSubscriptionsTab(cs, embedded: true),
      'progress' when _isStudent => _buildProgressTab(cs, embedded: true),
      'progress' => _buildLeadProgressTab(cs, embedded: true),
      'history_tasks' => _buildDesktopHistoryAndTasks(
        cs,
        canReadTasks: canReadTasks,
      ),
      'contacts' => _buildFamilyTab(cs, embedded: true),
      'documents' => const Padding(
        padding: EdgeInsets.all(AppSpace.xl),
        child: MagicPageState(
          kind: MagicPageStateKind.empty,
          title: 'Документов пока нет',
          message: 'Поддерживаемые документы появятся в этом разделе.',
        ),
      ),
      _ => _buildClientInfoTab(cs, currentStatus, embedded: true),
    };
  }

  Widget _desktopSectionCard(
    ColorScheme cs, {
    required Key key,
    required String section,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _selectSection(section),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.xl,
                vertical: AppSpace.md,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 19, color: AppColor.gold),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          child,
        ],
      ),
    );
  }

  Widget _buildDesktopHistoryAndTasks(
    ColorScheme cs, {
    required bool canReadTasks,
  }) {
    final sections = _isStudent
        ? <(String, IconData, Widget)>[
            if (canReadTasks)
              (
                'Задачи',
                Icons.task_alt_rounded,
                SizedBox(height: 520, child: _buildStudentTasksTab(cs)),
              ),
            (
              'Комментарии',
              Icons.comment_outlined,
              _buildCommentsTab(cs, embedded: true),
            ),
            (
              'История',
              Icons.history_rounded,
              _buildStudentHistoryTab(cs, embedded: true),
            ),
          ]
        : <(String, IconData, Widget)>[
            if (canReadTasks)
              (
                'Задачи',
                Icons.task_alt_rounded,
                SizedBox(height: 520, child: _buildTasksTab(cs)),
              ),
            (
              'Комментарии',
              Icons.comment_outlined,
              _buildCommentsTab(cs, embedded: true),
            ),
            (
              'История',
              Icons.history_rounded,
              _buildHistoryTab(cs, embedded: true),
            ),
          ];
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.md,
                      AppSpace.lg,
                      AppSpace.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sections[index].$2,
                          size: 17,
                          color: AppColor.gold,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          sections[index].$1,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  sections[index].$3,
                ],
              ),
            ),
            if (index < sections.length - 1)
              const SizedBox(height: AppSpace.md),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkspaceSection(
    ColorScheme cs,
    StatusRecord currentStatus,
    String section, {
    required bool canReadClientFinance,
    required bool canReadSchedule,
    required bool canWriteSchedule,
    required bool canReadTasks,
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
      'subscriptions' => _buildSubscriptionsTab(cs),
      'progress' when _isStudent => _buildProgressTab(cs),
      'progress' => _buildLeadProgressTab(cs),
      'history_tasks' => _buildHistoryAndTasksTab(
        cs,
        canReadTasks: canReadTasks,
      ),
      'contacts' => _buildFamilyTab(cs),
      'documents' => const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Документов пока нет',
        message: 'Поддерживаемые документы появятся в этом разделе.',
      ),
      _ => _buildClientInfoTab(cs, currentStatus),
    };
  }

  Widget _buildLeadLessonsTab(
    ColorScheme cs, {
    required bool canReadSchedule,
    required bool canWriteSchedule,
    bool embedded = false,
  }) {
    return ListView(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(AppSpace.xl),
      children: [
        if (canReadSchedule) ...[
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
        ],
        if (!canReadSchedule)
          const MagicPageState(
            kind: MagicPageStateKind.forbidden,
            title: 'Календарь недоступен',
            message: 'У вашей роли нет доступа к расписанию.',
          )
        else if (embedded)
          _buildDesktopCalendarExpansion(
            clientType: 'lead',
            clientId: _leadId,
            canWriteSchedule: canWriteSchedule,
          )
        else
          SizedBox(
            height: 760,
            child: ScheduleWidget(
              title: 'Календарь занятий',
              clientType: 'lead',
              clientId: _leadId,
              clientName: [
                _clientFirstName,
                _clientLastName,
              ].whereType<String>().join(' '),
              initialBranchId: _clientBranchId,
              canWrite: canWriteSchedule,
              active: _selectedSection == 'lessons',
              initialViewState: widget.initialViewState,
              onViewStateChanged: widget.onViewStateChanged,
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopCalendarExpansion({
    required String clientType,
    required String clientId,
    required bool canWriteSchedule,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('client-calendar-expansion'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ExpansionTile(
        initiallyExpanded: _desktopCalendarExpanded,
        maintainState: false,
        onExpansionChanged: (expanded) {
          _emitState(() => _desktopCalendarExpanded = expanded);
        },
        leading: const Icon(Icons.calendar_month_rounded, color: AppColor.gold),
        title: const Text(
          'Календарь занятий',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Месяц, неделя и день по этому клиенту'),
        children: _desktopCalendarExpanded
            ? [
                Divider(height: 1, color: cs.outlineVariant),
                SizedBox(
                  key: const Key('client-calendar-widget'),
                  height: 760,
                  child: ScheduleWidget(
                    title: 'Календарь занятий',
                    clientType: clientType,
                    clientId: clientId,
                    clientName: [
                      _clientFirstName,
                      _clientLastName,
                    ].whereType<String>().join(' '),
                    initialBranchId: _clientBranchId,
                    canWrite: canWriteSchedule,
                    active: true,
                    initialViewState: widget.initialViewState,
                    onViewStateChanged: widget.onViewStateChanged,
                  ),
                ),
              ]
            : const [],
      ),
    );
  }

  Widget _buildHistoryAndTasksTab(
    ColorScheme cs, {
    required bool canReadTasks,
  }) {
    final tabs = _isStudent
        ? <(String, Widget)>[
            if (canReadTasks) ('Задачи', _buildStudentTasksTab(cs)),
            ('Комментарии', _buildCommentsTab(cs)),
            ('История', _buildStudentHistoryTab(cs)),
          ]
        : <(String, Widget)>[
            if (canReadTasks) ('Задачи', _buildTasksTab(cs)),
            ('Комментарии', _buildCommentsTab(cs)),
            ('История', _buildHistoryTab(cs)),
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

  Widget _buildSubscriptionsTab(ColorScheme cs, {bool embedded = false}) {
    if (!_isStudent) {
      return ListView(
        shrinkWrap: embedded,
        physics: embedded ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('subscription-add'),
              onPressed: _converting ? null : _showIssueSubscriptionSheet,
              icon: _converting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.card_membership_rounded),
              label: const Text('Выдать абонемент'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
            child: MagicPageState(
              kind: MagicPageStateKind.empty,
              title: 'Абонемент ещё не выдан',
              message:
                  'Выдача оплаченного абонемента переведёт лида в ученики.',
            ),
          ),
        ],
      );
    }
    return _studentGuard(cs, () {
      final focusedId = widget.initialViewState?.filters['subscriptionId']
          ?.toString();
      if (focusedId != null &&
          !_subscriptions.any((subscription) => subscription.id == focusedId)) {
        return const MagicPageState(
          kind: MagicPageStateKind.empty,
          title: 'Связанная запись недоступна',
        );
      }
      return ListView(
        controller: embedded ? null : _subscriptionScrollController,
        shrinkWrap: embedded,
        physics: embedded ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('subscription-add'),
              onPressed: _showIssueSubscriptionSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить абонемент'),
            ),
          ),
          if (_subscriptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: MagicPageState(
                kind: MagicPageStateKind.empty,
                title: 'Абонементов пока нет',
              ),
            )
          else
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
                  highlighted:
                      subscription.id ==
                      widget.initialViewState?.filters['subscriptionId']
                          ?.toString(),
                  onOpen: subscription.id?.isNotEmpty == true
                      ? (sourceContext, target) => _openLinkedRecord(
                          sourceContext,
                          EntityLink.typed(
                            entityType: EntityLinkType.subscription,
                            entityId: subscription.id!,
                            presentation: EntityPresentationReference(
                              primary:
                                  (subscription.packageName
                                          ?.trim()
                                          .isNotEmpty ??
                                      false)
                                  ? subscription.packageName!
                                  : 'Абонемент',
                              context: _subscriptionRemainder(subscription),
                            ),
                            optionalFocus: EntityLinkFocus(
                              focus: 'subscription',
                              filter: {
                                'studentId': _studentId,
                                'section': 'subscriptions',
                                'subscriptionId': subscription.id!,
                              },
                            ),
                          ),
                          target,
                        )
                      : null,
                  trailing:
                      subscription.isActive &&
                          (subscription.id?.isNotEmpty ?? false)
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key(
                                'subscription-replace-${subscription.id}',
                              ),
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
                              key: Key(
                                'subscription-cancel-${subscription.id}',
                              ),
                              tooltip: 'Отменить абонемент',
                              onPressed:
                                  _replacingSubscription ||
                                      _cancellingSubscription
                                  ? null
                                  : () => _showCancelSubscriptionFlow(
                                      subscription,
                                    ),
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

  Widget _buildCustomFieldsExpansion(ColorScheme cs) {
    return Container(
      key: const Key('client-custom-fields-expansion'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ExpansionTile(
        initiallyExpanded: _customFieldsExpanded,
        maintainState: false,
        onExpansionChanged: (expanded) {
          _emitState(() => _customFieldsExpanded = expanded);
        },
        leading: const Icon(Icons.tune_rounded, color: AppColor.gold),
        title: const Text(
          'Дополнительные поля',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Пользовательские данные клиента и ученика'),
        children: _customFieldsExpanded
            ? [
                Divider(height: 1, color: cs.outlineVariant),
                if (_loadingMetadata)
                  const Padding(
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: LinearProgressIndicator(color: AppColor.gold),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._buildCustomFieldControls(
                          cs,
                          _isStudent ? 'students' : 'leads',
                          excludedKeys: _ClientCardState
                              ._customKeysWithDedicatedEditor
                              .union(
                                _ClientCardState
                                    ._primaryBusinessCustomFieldKeys,
                              ),
                        ),
                      ],
                    ),
                  ),
              ]
            : const [],
      ),
    );
  }
}
