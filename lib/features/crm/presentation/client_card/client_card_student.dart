part of 'client_card.dart';

extension _ClientCardStudent on _ClientCardState {
  // Wraps any student tab body with the shared loading / error / not-found
  // states so per-tab isolation reuses one place.
  Widget _studentGuard(ColorScheme cs, Widget Function() child) {
    if (_loadingStudent) {
      return const Center(
        child: CircularProgressIndicator(color: AppColor.gold),
      );
    }
    if (_studentError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColor.danger,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Ошибка: $_studentError',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: AppSpace.md),
              TextButton(
                onPressed: _fetchStudentData,
                style: TextButton.styleFrom(foregroundColor: AppColor.gold),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    if (_student == null) {
      return Center(
        child: Text(
          'Ученик не найден',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return child();
  }

  // Read-only «Исходный лид» card for the converted Инфо tab: source, request
  // ── Student tab: Задачи ──────────────────────────────────────────────────
  Widget _buildStudentTasksTab(ColorScheme cs) {
    return _studentGuard(cs, () {
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
            if (_mergedTasks.isEmpty)
              _emptyHint(cs, 'Открытых задач нет')
            else
              ..._mergedTasks.map(
                (row) => _entityTile(
                  cs,
                  title: row['title']?.toString() ?? 'Задача',
                  subtitle: _formatStatus(row['status']),
                  leading: Icons.task_alt_rounded,
                  origin: _isConverted ? row['_origin']?.toString() : null,
                ),
              ),
          ],
        ),
      );
    });
  }

  // ── Student tab: Занятия (flat list; Phase 5 adds past/upcoming) ──────────
  Widget _buildLessonsTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      if (_lessons.isEmpty) {
        return Center(
          child: Text(
            'Занятий не найдено',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      }

      // Split into «Предстоящие» (scheduled_at >= now, ascending) and
      // «Прошедшие» (scheduled_at < now, descending). Lessons without a parsable
      // time fold into «Прошедшие» so they are never silently dropped.
      final now = DateTime.now();
      final upcoming = <Lesson>[];
      final past = <Lesson>[];
      for (final l in _lessons) {
        final dt = DateTime.tryParse(l.scheduledAt ?? '');
        if (dt != null && !dt.isBefore(now)) {
          upcoming.add(l);
        } else {
          past.add(l);
        }
      }
      int byTime(Lesson a, Lesson b) {
        final ad = DateTime.tryParse(a.scheduledAt ?? '');
        final bd = DateTime.tryParse(b.scheduledAt ?? '');
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      }

      upcoming.sort(byTime); // ascending (soonest first)
      past.sort((a, b) => byTime(b, a)); // descending (most recent first)

      return ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          if (upcoming.isNotEmpty) ...[
            _sectionTitle('Предстоящие'),
            ...upcoming.map(
              (l) => _lessonRow(cs, l, onOpenSchedule: _openScheduleForLesson),
            ),
          ],
          if (upcoming.isNotEmpty && past.isNotEmpty)
            const SizedBox(height: AppSpace.md),
          if (past.isNotEmpty) ...[
            _sectionTitle('Прошедшие'),
            ...past.map(
              (l) => _lessonRow(cs, l, onOpenSchedule: _openScheduleForLesson),
            ),
          ],
        ],
      );
    });
  }

  /// One tappable lesson row. Tapping focuses the dashboard schedule on the
  /// lesson's day with the lesson highlighted, then closes the card.
  /// Focus the dashboard schedule on [scheduledAt] with [lessonId] highlighted,
  /// then close this card and route to the admin dashboard schedule tab.
  ///
  /// Mirrors [ClientAppUserPanel._openChat]: set the cross-screen navigation
  /// target, pop this card (the dialog / sheet), then navigate to the host
  /// screen. The schedule lives on canonical CRM tab 2 (Расписание) inside the
  /// admin dashboard, so we also request that tab via [crmNavigationRequestProvider].
  void _openScheduleForLesson(DateTime scheduledAt, String lessonId) {
    ref.read(scheduleNavigationProvider.notifier).focus(scheduledAt, lessonId);
    // Select the schedule destination (tab 2) once the dashboard renders.
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(const CrmNavigationRequest(tabIndex: 2));
    // Close the card (dialog on desktop / bottom sheet on mobile).
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_dirty ? true : null);
    }
    // Route to the admin dashboard which hosts the schedule.
    context.go('/admin');
  }

  // ── Student tab: Оплаты ──────────────────────────────────────────────────
  Widget _buildPaymentsTab(ColorScheme cs) {
    return _studentGuard(cs, () => _paymentsView(cs, payments: _payments));
  }

  // ── Student tab: История ─────────────────────────────────────────────────
  // For a converted client this folds lead status history into the student
  // timeline (merged, de-duped by id, origin-badged). A plain student keeps the
  // Phase 2 view (its own tasks + comments).
  Widget _buildStudentHistoryTab(ColorScheme cs) {
    if (_isConverted) {
      return _studentGuard(
        cs,
        () => _mergedHistoryView(
          cs,
          loading: _loadingHistory,
          items: _mergedHistory,
        ),
      );
    }
    return _studentGuard(
      cs,
      () => _studentTimelineView(
        cs,
        tasks: _studentTasks,
        comments: _studentComments,
      ),
    );
  }

  // ── Student tab: Прогресс (домашние задания от педагога) ──────────────────
  // Заказчик: ДЗ, назначенное педагогом, фиксируется в разделе «Прогресс»
  // карточки клиента. Тянем список домашек ученика (app.lesson_homeworks).
  Widget _buildProgressTab(ColorScheme cs) {
    return _studentGuard(
      cs,
      () => _HomeworkProgressList(
        studentId: _studentId,
        refreshKey: _homeworkRefreshKey,
      ),
    );
  }

  // ── Student action bar (overflow menu hosts the v7 student actions) ───────
  Widget _buildStudentActionBar(ColorScheme cs) {
    final busy = _loadingStudent || _student == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.lg,
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Действия',
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            onSelected: (value) {
              switch (value) {
                case 'subscription':
                  _showIssueSubscriptionSheet();
                case 'homework':
                  _showAssignHomeworkSheet();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'subscription',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.card_membership_rounded,
                    color: AppColor.gold,
                  ),
                  title: Text('Выдать абонемент'),
                ),
              ),
              PopupMenuItem(
                value: 'homework',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.assignment_rounded, color: AppColor.gold),
                  title: Text('Задать ДЗ'),
                ),
              ),
            ],
            child: OutlinedButton.icon(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                disabledForegroundColor: cs.onSurface,
                side: BorderSide(color: cs.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text('Действия'),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _saving || _converting ? null : _handleClose,
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            child: const Text('Отмена'),
          ),
          const SizedBox(width: AppSpace.sm),
          FilledButton(
            onPressed: busy || _saving || _converting ? null : _save,
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
    );
  }

  /// Flat gold button used inside the v7 «Задать ДЗ» sheet (ported helper).
  Future<void> _showIssueSubscriptionSheet() async {
    final crm = ref.read(magicCrmServiceProvider);
    List<Map<String, dynamic>> packages;
    try {
      packages = await crm.listSubscriptionPackages(limit: 100);
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось загрузить абонементы',
        detail: '$e',
        type: MagicToastType.danger,
      );
      return;
    }
    if (!mounted) return;

    if (packages.isEmpty) {
      MagicToast.show(
        context,
        'Нет доступных абонементов',
        type: MagicToastType.info,
      );
      return;
    }

    final selected = await showIssueSubscriptionSheet(
      context,
      packages: packages,
    );

    if (selected == null || !mounted) return;

    final packageId = selected['id']?.toString();
    if (packageId == null || packageId.isEmpty) return;

    try {
      await crm.issueSubscription(_entityId, packageId);
      if (!mounted) return;
      _dirty = true;
      MagicToast.show(
        context,
        'Абонемент выдан',
        detail: selected['name']?.toString(),
        type: MagicToastType.success,
      );
      _fetchStudentData();
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось выдать абонемент',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  Future<void> _showAssignHomeworkSheet() async {
    final crm = ref.read(magicCrmServiceProvider);

    List<Map<String, dynamic>> homeworks = const [];
    try {
      homeworks = await crm.listHomeworks(studentId: _entityId, limit: 5);
    } catch (_) {
      // Listing is best-effort; the assign form still works without it.
    }
    if (!mounted) return;

    final input = await showAssignHomeworkSheet(
      context,
      recentHomeworks: homeworks,
    );
    if (input == null || !mounted) return;

    try {
      await crm.createHomework(
        studentId: _entityId,
        title: input.title,
        description: input.description,
        dueAt: input.dueAt?.toIso8601String(),
      );
      if (!mounted) return;
      _dirty = true;
      // Refresh the «Прогресс» tab so the just-assigned homework shows up.
      _emitState(() => _homeworkRefreshKey++);
      MagicToast.show(
        context,
        'ДЗ создано',
        detail: input.title,
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось создать ДЗ',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  /// Shared card container used by the student Инфо/Документы tabs (ported from
  /// student_detail_screen._buildInfoCard).
  InputDecoration _inputDecoration(
    ColorScheme cs, {
    String? label,
    String? hint,
    String? helperText,
    bool isDense = false,
    Widget? suffixIcon,
  }) => clientCardInputDecoration(
    cs,
    label: label,
    hint: hint,
    helperText: helperText,
    isDense: isDense,
    suffixIcon: suffixIcon,
  );

  Widget _buildStatusPicker(ColorScheme cs, StatusRecord current) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: DropdownButtonFormField<String>(
        initialValue: _leadData['status'],
        isExpanded: true,
        decoration: _inputDecoration(cs, label: 'Статус', isDense: true),
        items: _statuses.map((s) {
          return DropdownMenuItem(
            value: s.$1,
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: s.$3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(s.$2),
              ],
            ),
          );
        }).toList(),
        onChanged: (v) {
          if (v != null) {
            _emitState(() {
              _leadData['status'] = v;
              _edited = true;
            });
          }
        },
      ),
    );
  }

  Widget _buildStudentStatusPicker(ColorScheme cs) {
    final current = _student?['status']?.toString() ?? '';
    final options = [
      if (current.isNotEmpty &&
          !_ClientCardState._studentStatusOptions.contains(current))
        current,
      ..._ClientCardState._studentStatusOptions,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: DropdownButtonFormField<String>(
        initialValue: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: _inputDecoration(
          cs,
          label: 'Статус ученика',
          isDense: true,
        ),
        items: options
            .map(
              (status) => DropdownMenuItem(value: status, child: Text(status)),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          _emitState(() {
            _student?['status'] = value;
            _edited = true;
          });
        },
      ),
    );
  }
}
