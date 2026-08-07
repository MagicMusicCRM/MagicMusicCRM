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
      return SharedTasksV4Panel(
        embedded: true,
        linkedEntity: EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: _studentId,
          variant: 'student',
          presentation: EntityPresentationReference(
            primary: _clientPresentationLabel,
          ),
        ),
        scrollController: _taskScrollController,
        canWrite:
            widget.capabilitySnapshot?.allows('workflow.task.write') == true,
      );
    });
  }

  // ── Student tab: Занятия ─────────────────────────────────────────────────
  Widget _buildLessonsTab(
    ColorScheme cs, {
    required bool canReadSchedule,
    required bool canWriteSchedule,
    bool embedded = false,
  }) {
    return _studentGuard(cs, () {
      return ListView(
        shrinkWrap: embedded,
        physics: embedded ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          if (_commerceStudent != null) ...[
            _lessonBalanceSummary(
              _commerceStudent!.lessonBalance,
              onSubscriptions: () => _selectSection('subscriptions'),
              onPayments: () => _selectSection('payments'),
            ),
            const SizedBox(height: AppSpace.xl),
          ],
          if (canReadSchedule) ...[
            StudentScheduleSection(
              clientType: 'student',
              clientId: _studentId,
              lessons: _lessons.map((lesson) => lesson.raw).toList(),
              branches: _branches,
              defaultBranchId: _clientBranchId,
              legacyPreference: _customDataForEntity(
                'students',
              )['preferredSchedule']?.toString(),
              subscriptions: [
                for (final subscription in _subscriptions)
                  if (subscription.isActive && subscription.id != null)
                    {
                      'id': subscription.id,
                      'label':
                          subscription.packageName ??
                          subscription.type ??
                          'Абонемент',
                    },
              ],
              canWrite: canWriteSchedule,
              onChanged: _fetchStudentData,
              onOpenLesson: _openClientTrayLesson,
            ),
            const SizedBox(height: AppSpace.xl),
          ],
          if (!canReadSchedule)
            const MagicPageState(
              kind: MagicPageStateKind.forbidden,
              title: 'Календарь недоступен',
              message: 'У вашей роли нет доступа к расписанию.',
            )
          else if (embedded)
            _buildDesktopCalendarExpansion(
              clientType: 'student',
              clientId: _studentId,
              canWriteSchedule: canWriteSchedule,
            )
          else
            SizedBox(
              height: 760,
              child: ScheduleWidget(
                title: 'Календарь занятий',
                clientType: 'student',
                clientId: _studentId,
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
    });
  }

  Future<void> _openClientTrayLesson(Map<String, dynamic> lesson) async {
    final changed = await CreateLessonDialog.show(context, lesson: lesson);
    if (changed == true && mounted) await _fetchStudentData();
  }

  // ── Student tab: Оплаты ──────────────────────────────────────────────────
  Widget _buildPaymentsTab(ColorScheme cs, {bool embedded = false}) {
    return _studentGuard(
      cs,
      () => _paymentsView(
        cs,
        commerce: _commerceStudent,
        fallbackPayments: _payments,
        creating: _creatingPayment,
        adjustingPayment: _adjustingPayment,
        branchId: _clientBranchId,
        branchName: _nonEmpty(_student?['branch_name']) ?? 'Филиал не указан',
        onCreate: () => _emitState(() => _creatingPayment = true),
        onCancel: () => _emitState(() => _creatingPayment = false),
        onSubmit: _recordClientPayment,
        onAdjust: (payment) => _emitState(() => _adjustingPayment = payment),
        onTransition: _showPaymentTransitionFlow,
        onReverse: _showPaymentReversalFlow,
        onCancelAdjustment: () => _emitState(() => _adjustingPayment = null),
        onSubmitAdjustment: _recordPaymentAdjustment,
        scrollController: _paymentScrollController,
        embedded: embedded,
        highlightedPaymentId: widget.initialViewState?.filters['paymentId']
            ?.toString(),
        onOpenPayment: (sourceContext, paymentId, presentation, target) =>
            _openLinkedRecord(
              sourceContext,
              EntityLink.typed(
                entityType: EntityLinkType.payment,
                entityId: paymentId,
                presentation: presentation,
                optionalFocus: EntityLinkFocus(
                  focus: 'payment',
                  filter: {
                    'studentId': _studentId,
                    'section': 'payments',
                    'paymentId': paymentId,
                  },
                ),
              ),
              target,
            ),
      ),
    );
  }

  Future<void> _recordClientPayment(ClientPaymentSubmission submission) async {
    await ref
        .read(magicCrmServiceProvider)
        .createClientPaymentRecord(
          _studentId,
          input: submission.input,
          identity: submission.identity,
        );
    if (!mounted) return;
    _emitState(() => _creatingPayment = false);
    _refreshLedger();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Оплата добавлена в финансовую историю')),
    );
  }

  Future<void> _recordPaymentAdjustment(
    ClientPaymentAdjustmentSubmission submission,
  ) async {
    await ref
        .read(magicCrmServiceProvider)
        .recordPaymentAdjustment(
          _studentId,
          input: submission.input,
          identity: submission.identity,
        );
    if (!mounted) return;
    _emitState(() => _adjustingPayment = null);
    _refreshLedger();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Исправление добавлено отдельной операцией'),
      ),
    );
  }

  Future<void> _showPaymentTransitionFlow(
    CommerceMovement payment,
    ClientPaymentStatus targetStatus,
  ) async {
    final changed = await showClientPaymentTransitionSheet(
      context,
      payment: payment,
      targetStatus: targetStatus,
      branchId: _clientBranchId,
      onSubmit: (submission) => ref
          .read(magicCrmServiceProvider)
          .transitionClientPaymentRecord(
            _studentId,
            paymentRecordId: payment.id,
            input: submission.input,
            identity: submission.identity,
          ),
    );
    if (changed != true || !mounted) return;
    MagicToast.show(
      context,
      'Статус оплаты изменён',
      detail: clientPaymentStatusLabel(targetStatus.apiValue),
      type: MagicToastType.success,
    );
    _refreshLedger();
  }

  Future<void> _showPaymentReversalFlow(CommerceMovement payment) async {
    final version = payment.paymentRecordVersion;
    if (version == null) return;
    final crm = ref.read(magicCrmServiceProvider);
    try {
      final preview = await crm.previewClientPaymentReversal(
        _studentId,
        paymentRecordId: payment.id,
        expectedVersion: version,
      );
      if (!mounted) return;
      final changed = await showClientPaymentReversalSheet(
        context,
        preview: preview,
        onSubmit: (submission) => crm.reverseClientPayment(
          _studentId,
          paymentRecordId: payment.id,
          preview: preview,
          reason: submission.reason,
          identity: submission.identity,
        ),
      );
      if (changed != true || !mounted) return;
      MagicToast.show(
        context,
        'Оплата удалена из обычного учёта',
        detail: 'Причина сохранена в технической истории',
        type: MagicToastType.success,
      );
      _refreshLedger();
    } catch (error) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось подготовить удаление оплаты',
        detail: '$error',
        type: MagicToastType.danger,
      );
    }
  }

  // ── Student tab: История ─────────────────────────────────────────────────
  // For a converted client this folds lead status history into the student
  // timeline (merged, de-duped by id, origin-badged). A plain student keeps the
  // Phase 2 view (its own tasks + comments).
  Widget _buildStudentHistoryTab(ColorScheme cs, {bool embedded = false}) {
    if (_isConverted) {
      return _studentGuard(
        cs,
        () => _mergedHistoryView(
          cs,
          loading: _loadingHistory,
          items: _mergedHistory,
          embedded: embedded,
        ),
      );
    }
    return _studentGuard(
      cs,
      () => _studentTimelineView(
        cs,
        tasks: _studentTasks,
        comments: _studentComments,
        embedded: embedded,
      ),
    );
  }

  // ── Student tab: Прогресс (домашние задания от педагога) ──────────────────
  // Заказчик: ДЗ, назначенное педагогом, фиксируется в разделе «Прогресс»
  // карточки клиента. Тянем список домашек ученика (app.lesson_homeworks).
  Widget _buildProgressTab(ColorScheme cs, {bool embedded = false}) {
    return _studentGuard(
      cs,
      () => Column(
        mainAxisSize: embedded ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.md,
              AppSpace.xl,
              0,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('assign-homework'),
                onPressed: _showAssignHomeworkSheet,
                icon: const Icon(Icons.assignment_add),
                label: const Text('Назначить ДЗ'),
              ),
            ),
          ),
          if (embedded)
            _HomeworkProgressList(
              studentId: _studentId,
              refreshKey: _homeworkRefreshKey,
              embedded: true,
            )
          else
            Expanded(
              child: _HomeworkProgressList(
                studentId: _studentId,
                refreshKey: _homeworkRefreshKey,
              ),
            ),
        ],
      ),
    );
  }

  /// Trial homework belongs to the lead until a paid subscription is issued.
  /// Staff therefore need the same progress surface before conversion; the
  /// server moves these rows to the student atomically with subscription issue.
  Widget _buildLeadProgressTab(ColorScheme cs, {bool embedded = false}) {
    return _HomeworkProgressList(
      leadId: _leadId,
      refreshKey: _homeworkRefreshKey,
      embedded: embedded,
    );
  }

  // ── Student action bar (overflow menu hosts the v7 student actions) ───────
  // #13: Align + Wrap (как у лид-бара в tabs_a) вместо жёсткого Row: на
  // телефоне карточка — bottom sheet во всю ширину, и три кнопки с отступами
  // не влезали в 320–360dp — правый край переполнялся. Wrap переносит кнопки
  // на вторую строку.
  Widget _buildStudentActionBar(ColorScheme cs) {
    final busy = _loadingStudent || _student == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.lg,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ClientArchiveButton(
              entityType: 'student',
              entityId: _studentId,
              allowed: clientRoleCanArchive(
                ref.read(releaseGateStatusProvider).asData?.value.role ?? '',
              ),
              onArchived: () => _closeCard(true),
            ),
            // #6: переход в расписание — на ближайшее занятие ученика, а без
            // занятий просто на сегодняшний день.
            OutlinedButton.icon(
              onPressed: busy ? null : _openScheduleFromCard,
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
      ),
    );
  }

  /// Flat gold button used inside the v7 «Задать ДЗ» sheet (ported helper).
  Future<void> _showIssueSubscriptionSheet() async {
    final crm = ref.read(magicCrmServiceProvider);
    final issuingForLead = !_isStudent;
    List<Map<String, dynamic>> packages;
    try {
      final response = await crm.listSubscriptionPackages(limit: 100);
      // The server returns the active projection. Keep this defensive filter
      // so a stale/mixed cache can never offer an archived template for a new
      // issued subscription.
      packages = activeSubscriptionPackages(response);
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

    if (!issuingForLead) {
      final recipientLabel = [
        _clientLastName,
        _clientFirstName,
      ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
      final issued = await showSubscriptionIssueFormSheet(
        context,
        package: selected,
        recipientStudentId: _studentId,
        recipientLabel: recipientLabel.isEmpty
            ? 'Текущий ученик'
            : recipientLabel,
        searchPayers: (query) async {
          final rows = await crm.searchClientRefs(
            q: query,
            type: 'student',
            limit: 50,
          );
          return [
            for (final row in rows)
              if (row['ref'] is Map &&
                  (row['ref'] as Map)['id']?.toString().isNotEmpty == true)
                SearchableSelectItem(
                  id: (row['ref'] as Map)['id'].toString(),
                  label: row['label']?.toString().trim().isNotEmpty == true
                      ? row['label'].toString()
                      : 'Ученик без имени',
                  subtitle: 'Личный счёт ученика',
                ),
          ];
        },
        onPreview: (input) =>
            crm.previewSubscriptionPurchase(_studentId, input: input),
        onSubmit: (submission) async {
          await crm.purchaseSubscription(
            _studentId,
            input: submission.purchase,
            preview: submission.preview,
            identity: submission.identity,
          );
        },
      );
      if (issued != true || !mounted) return;
      _dirty = true;
      MagicToast.show(
        context,
        'Абонемент куплен',
        detail: selected['name']?.toString(),
        type: MagicToastType.success,
      );
      _fetchStudentData();
      return;
    }

    if (issuingForLead) _emitState(() => _converting = true);
    try {
      // The package endpoint atomically copies the persisted lead record.
      // Save the in-memory draft first; otherwise choosing a package closes
      // the card and silently drops fields typed since the last Save action.
      if (_edited && !await _persistEdits()) return;
      await crm.issueLeadSubscription(_leadId, packageId);
      if (!mounted) return;
      _dirty = true;
      MagicToast.show(
        context,
        'Абонемент выдан — лид стал учеником',
        detail: selected['name']?.toString(),
        type: MagicToastType.success,
      );
      // Reopen from «Ученики» against the freshly-created student id. This
      // also prevents any stale lead id from being reused by later actions.
      _closeCard(true);
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось выдать абонемент',
        detail: '$e',
        type: MagicToastType.danger,
      );
    } finally {
      if (mounted) {
        _emitState(() => _converting = false);
      }
    }
  }

  Future<void> _showReplaceSubscriptionFlow(
    Subscription oldSubscription,
  ) async {
    final issuedSubscriptionId = oldSubscription.id;
    if (_replacingSubscription ||
        !oldSubscription.isActive ||
        issuedSubscriptionId == null ||
        issuedSubscriptionId.isEmpty) {
      return;
    }

    final crm = ref.read(magicCrmServiceProvider);
    _emitState(() => _replacingSubscription = true);
    try {
      final response = await crm.listSubscriptionPackages(limit: 100);
      final packages = activeSubscriptionPackages(response);
      if (!mounted) return;
      if (packages.isEmpty) {
        MagicToast.show(
          context,
          'Нет доступных абонементов для замены',
          type: MagicToastType.info,
        );
        return;
      }

      final selected = await showIssueSubscriptionSheet(
        context,
        packages: packages,
        title: 'Новый абонемент',
        subtitle: 'Выберите активный пакет для замены',
      );
      if (selected == null || !mounted) return;
      final newPackageId = selected['id']?.toString();
      if (newPackageId == null || newPackageId.isEmpty) return;

      final preview = await crm.previewSubscriptionReplacement(
        _studentId,
        issuedSubscriptionId: issuedSubscriptionId,
        newPackageId: newPackageId,
      );
      if (!mounted) return;

      final replaced = await showSubscriptionReplacementSheet(
        context,
        oldSubscription: oldSubscription,
        preview: preview,
        onConfirm: (confirmation) async {
          await crm.replaceSubscription(
            _studentId,
            issuedSubscriptionId: issuedSubscriptionId,
            input: confirmation.input,
            identity: confirmation.identity,
          );
        },
      );
      if (replaced != true || !mounted) return;

      _dirty = true;
      await _fetchStudentData();
      if (!mounted) return;
      MagicToast.show(
        context,
        'Абонемент заменён',
        detail: preview.newPackage.name,
        type: MagicToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось заменить абонемент',
        detail: '$error',
        type: MagicToastType.danger,
      );
    } finally {
      if (mounted) {
        _emitState(() => _replacingSubscription = false);
      }
    }
  }

  Future<void> _showCancelSubscriptionFlow(Subscription subscription) async {
    final issuedSubscriptionId = subscription.id;
    if (_replacingSubscription ||
        _cancellingSubscription ||
        !subscription.isActive ||
        issuedSubscriptionId == null ||
        issuedSubscriptionId.isEmpty) {
      return;
    }

    final crm = ref.read(magicCrmServiceProvider);
    _emitState(() => _cancellingSubscription = true);
    try {
      final preview = await crm.previewSubscriptionCancellation(
        _studentId,
        issuedSubscriptionId: issuedSubscriptionId,
      );
      if (!mounted) return;

      final cancelled = await showSubscriptionCancellationSheet(
        context,
        preview: preview,
        onConfirm: (confirmation) async {
          await crm.cancelSubscription(
            _studentId,
            issuedSubscriptionId: issuedSubscriptionId,
            input: confirmation.input,
            identity: confirmation.identity,
          );
        },
      );
      if (cancelled != true || !mounted) return;

      _dirty = true;
      await _fetchStudentData();
      if (!mounted) return;
      MagicToast.show(
        context,
        'Абонемент отменён',
        detail: preview.package.name,
        type: MagicToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось отменить абонемент',
        detail: '$error',
        type: MagicToastType.danger,
      );
    } finally {
      if (mounted) {
        _emitState(() => _cancellingSubscription = false);
      }
    }
  }

  Future<void> _showAssignHomeworkSheet() async {
    final crm = ref.read(magicCrmServiceProvider);

    List<Map<String, dynamic>> homeworks = const [];
    try {
      homeworks = await crm.listHomeworks(studentId: _studentId, limit: 5);
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
        studentId: _studentId,
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
    String? errorText,
    bool isDense = false,
    Widget? suffixIcon,
  }) => clientCardInputDecoration(
    cs,
    label: label,
    hint: hint,
    helperText: helperText,
    errorText: errorText,
    isDense: isDense,
    suffixIcon: suffixIcon,
  );

  /// #9: статус из HolliHop — подписью под пикером статуса, а не отдельной
  /// строкой в «Дополнительно»: это одно и то же поле в двух системах.
  String? get _hhStatusHelper {
    final name = _hhField('statusName');
    return name == null ? null : 'Статус в HolliHop: $name';
  }

  Widget _buildStatusPicker(ColorScheme cs, StatusRecord current) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: DropdownButtonFormField<String>(
        // Легаси-фолбэк 'new' (лид «Без статуса») и имена статусов в списке
        // UUID-значений не встречаются — такой «статус» показываем как пустой
        // выбор, а не роняем dropdown-assert (#2).
        initialValue:
            _statuses.any((s) => s.$1 == _leadData['status']?.toString())
            ? _leadData['status']?.toString()
            : null,
        isExpanded: true,
        decoration: _inputDecoration(
          cs,
          label: 'Статус',
          helperText: _hhStatusHelper,
          isDense: true,
        ),
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
    final funnel = _studentFunnel;
    if (funnel == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: InputDecorator(
          decoration: _inputDecoration(
            cs,
            label: 'Этап воронки',
            errorText: _studentFunnelError,
          ),
          child: const Text('Этап недоступен'),
        ),
      );
    }
    final configuredCurrent = funnel.stages
        .where((stage) => stage.key == current)
        .firstOrNull;
    final options = funnel.activeStages
        .where(
          (stage) =>
              configuredCurrent == null ||
              stage.key == current ||
              configuredCurrent.allowedTransitions.contains(stage.key),
        )
        .toList(growable: false);
    final currentConfigured = funnel.stages.any(
      (stage) => stage.key == current && stage.active,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: DropdownButtonFormField<String>(
        key: ValueKey('student-funnel-status-${funnel.scopeVersion}-$current'),
        initialValue: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: _inputDecoration(
          cs,
          label: 'Этап воронки',
          helperText: configuredCurrent == null && current.isNotEmpty
              ? 'Старый статус нужно сопоставить с этапом.'
              : 'Доступны только разрешённые переходы.',
          isDense: true,
        ),
        items: [
          if (current.isNotEmpty && !currentConfigured)
            DropdownMenuItem(
              value: current,
              enabled: false,
              child: Text('Требует сопоставления: $current'),
            ),
          ...options.map(
            (stage) =>
                DropdownMenuItem(value: stage.key, child: Text(stage.label)),
          ),
        ],
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
