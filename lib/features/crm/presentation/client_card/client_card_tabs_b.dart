part of 'client_card.dart';

extension _ClientCardTabsB on _ClientCardState {
  // ── Tab: Комментарии ─────────────────────────────────────────────────────
  Widget _buildCommentsTab(ColorScheme cs, {bool embedded = false}) {
    final comments = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Комментарии'),
          _CommentsList(
            // For a converted client both halves are loaded, merged,
            // de-duped by id and origin-badged; single-side cards pass one
            // ref and render exactly as before (no origin chip).
            refs: _halfRefs,
            showOrigin: _isConverted,
            refreshKey: _commentsRefreshKey,
          ),
        ],
      ),
    );
    final input = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.sm,
        AppSpace.xl,
        AppSpace.lg,
      ),
      child: _buildCommentInput(cs),
    );
    if (embedded) {
      return Column(children: [comments, input]);
    }
    return Column(
      children: [
        Expanded(child: comments),
        input,
      ],
    );
  }

  // ── Tab: Семья ───────────────────────────────────────────────────────────
  Widget _buildFamilyTab(ColorScheme cs, {bool embedded = false}) {
    const padding = EdgeInsets.fromLTRB(
      AppSpace.xl,
      AppSpace.lg,
      AppSpace.xl,
      AppSpace.xl,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('Семья')),
            _buildFamilyAddButton(cs),
          ],
        ),
        _familySection(
          cs,
          loading: _loadingFamily,
          family: _family,
          busy: _familyBusy,
          onRemove: _removeFamilyMember,
          onSetPrimaryPayer: _setFamilyPrimaryPayer,
          onOpen: _openFamilyMember,
        ),
        if (_clientAccessAllowed) ...[
          const SizedBox(height: AppSpace.lg),
          _buildClientAccessSection(cs),
        ],
        // #14: контактные лица живут на одной вкладке с семьёй — из Инфо
        // дубль убран.
        const SizedBox(height: AppSpace.lg),
        _buildContactPersonsEditor(cs, _isStudent ? 'students' : 'leads'),
        // #9: строка «Контакты» из выгрузки HolliHop (custom_data.contacts) —
        // только чтение, показывается когда заполнена.
        if (_hhField('contacts') != null)
          _buildInfoCard('Контакты из HolliHop', [
            _InfoRow(
              icon: Icons.family_restroom_outlined,
              label: 'Контактные лица',
              value: _hhField('contacts')!,
            ),
          ]),
      ],
    );
    if (embedded) return Padding(padding: padding, child: content);
    return SingleChildScrollView(padding: padding, child: content);
  }

  Widget _buildFamilyAddButton(ColorScheme cs) {
    return TextButton.icon(
      onPressed: _familyBusy ? null : _openAddFamilyMemberSheet,
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
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('Добавить'),
    );
  }

  Widget _buildClientAccessSection(ColorScheme cs) {
    final linkedIds = _linkedUsers
        .map((item) => item['userId']?.toString())
        .whereType<String>()
        .toSet();
    final candidates = _clientUserCandidates
        .where((item) => !linkedIds.contains(item['userId']?.toString()))
        .toList(growable: false);

    return Container(
      key: const Key('client-app-access'),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                children: [
                  const Icon(
                    Icons.mobile_friendly_rounded,
                    color: AppColor.gold,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  const Expanded(
                    child: Text(
                      'Доступ в приложение',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
              final invite = OutlinedButton.icon(
                key: const Key('client-send-invite'),
                onPressed: _clientAccessBusy ? null : _inviteClientToApp,
                icon: const Icon(Icons.mark_email_read_outlined, size: 17),
                label: const Text('Пригласить'),
              );
              if (!_mode.hasStudentHalf) return title;
              if (constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: AppSpace.sm),
                    invite,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: AppSpace.sm),
                  invite,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpace.sm),
          if (_loadingClientAccess)
            const LinearProgressIndicator(color: AppColor.gold)
          else if (_clientAccessError != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Не удалось загрузить связанные аккаунты',
                    style: TextStyle(color: cs.error),
                  ),
                ),
                TextButton(
                  onPressed: _fetchClientAccess,
                  child: const Text('Повторить'),
                ),
              ],
            )
          else ...[
            if (_linkedUsers.isEmpty)
              Text(
                'Связанных аккаунтов пока нет',
                style: TextStyle(color: cs.onSurfaceVariant),
              )
            else
              for (final user in _linkedUsers)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_user_outlined, size: 19),
                  title: Text(
                    user['name']?.toString().trim().isNotEmpty == true
                        ? user['name'].toString()
                        : 'Пользователь приложения',
                  ),
                  subtitle: Text(
                    user['linkSource'] == 'self'
                        ? 'Личный аккаунт ученика'
                        : 'Связанный аккаунт',
                  ),
                ),
            if (candidates.isNotEmpty) ...[
              const Divider(),
              Text(
                'Найдены аккаунты с тем же телефоном',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              for (final candidate in candidates)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    candidate['name']?.toString().trim().isNotEmpty == true
                        ? candidate['name'].toString()
                        : 'Пользователь приложения',
                  ),
                  subtitle: Text(
                    candidate['email']?.toString() ??
                        candidate['phone']?.toString() ??
                        '',
                  ),
                  trailing: TextButton(
                    key: Key(
                      'client-link-user-${candidate['userId']?.toString()}',
                    ),
                    onPressed: _clientAccessBusy
                        ? null
                        : () => _linkClientUser(candidate),
                    child: const Text('Связать'),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  // ── Tab: История ─────────────────────────────────────────────────────────
  Widget _buildHistoryTab(ColorScheme cs, {bool embedded = false}) {
    const padding = EdgeInsets.fromLTRB(
      AppSpace.xl,
      AppSpace.lg,
      AppSpace.xl,
      AppSpace.xl,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_internalContextAllowed) ...[
          _buildOperationalHistory(),
          const SizedBox(height: AppSpace.lg),
        ],
        _sectionTitle('История статусов'),
        _statusHistorySection(
          cs,
          loading: _loadingHistory,
          history: _statusHistory,
        ),
      ],
    );
    if (embedded) return Padding(padding: padding, child: content);
    return SingleChildScrollView(padding: padding, child: content);
  }

  // ══ STUDENT (entityType == 'student') ════════════════════════════════════
  // Ported from student_detail_screen.dart, adapted to the compact dialog and
  // the unified comments tab. Lead methods above are untouched.

  /// Resolves the student display name with a fallback to the linked profile,
  /// matching student_detail_screen.
  ({String name, String phone, String email}) _studentContact() {
    final s = _student ?? const <String, dynamic>{};
    final profile = s['profiles'] as Map<String, dynamic>?;
    final sfName = s['first_name']?.toString() ?? '';
    final slName = s['last_name']?.toString() ?? '';
    var name = '$sfName $slName'.trim();
    if (name.isEmpty && profile != null) {
      name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
          .trim();
    }
    final phone =
        (s['phone']?.toString().trim().isNotEmpty == true
                ? s['phone']
                : profile?['phone'])
            ?.toString() ??
        '—';
    final email =
        (s['email']?.toString().trim().isNotEmpty == true
                ? s['email']
                : profile?['email'])
            ?.toString() ??
        '—';
    return (
      name: name.isEmpty ? 'Без имени' : name,
      phone: phone,
      email: email,
    );
  }

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == '—' ? null : text;
  }

  String? get _clientFirstName => _isStudent
      ? _nonEmpty(_student?['first_name'])
      : _nonEmpty(_leadData['name'] ?? _leadData['first_name']);

  String? get _clientLastName => _isStudent
      ? _nonEmpty(_student?['last_name'])
      : _nonEmpty(_leadData['last_name']);

  String get _clientPresentationLabel {
    final name = [
      _clientLastName,
      _clientFirstName,
    ].whereType<String>().join(' ').trim();
    return name.isEmpty ? 'Без имени' : name;
  }

  void _syncWorkspaceTitle() {
    WorkspaceNavigationScope.maybeOf(
      context,
    )?.controller.updateEntityPresentation(
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: _entityId,
        variant: widget.entityType,
      ),
      EntityPresentationReference(primary: _clientPresentationLabel),
    );
  }

  String? get _clientPhone => _isStudent
      ? _nonEmpty(_student?['phone'])
      : _nonEmpty(_leadData['phone']);

  String? get _clientEmail => _isStudent
      ? _nonEmpty(_student?['email'])
      : _nonEmpty(_leadData['email']);

  String? get _clientSourceId => _isStudent
      ? _nonEmpty(_student?['source_id'] ?? _leadData['source_id'])
      : _nonEmpty(_leadData['source_id']);

  String? get _clientBranchId {
    final studentCustom = _student?['custom_data'];
    if (_isStudent && studentCustom is Map) {
      return _nonEmpty(
        studentCustom['branchId'] ??
            studentCustom['branch_id'] ??
            _student?['branch_id'],
      );
    }
    if (_isStudent) return _nonEmpty(_student?['branch_id']);
    return _nonEmpty(_leadData['branch_id']);
  }

  void _updateClientCore(String key, dynamic value) {
    _emitState(() {
      if (_mode.hasLeadHalf) {
        switch (key) {
          case 'firstName':
            _leadData['name'] = value;
            _leadData['first_name'] = value;
          case 'lastName':
            _leadData['last_name'] = value;
          case 'phone':
            _leadData['phone'] = value;
          case 'email':
            _leadData['email'] = value;
          case 'branchId':
            _leadData['branch_id'] = value;
          case 'sourceId':
            _leadData['source_id'] = value;
        }
      }
      if (_mode.hasStudentHalf && _student != null) {
        switch (key) {
          case 'firstName':
            _student!['first_name'] = value;
          case 'lastName':
            _student!['last_name'] = value;
          case 'phone':
            _student!['phone'] = value;
          case 'email':
            _student!['email'] = value;
          case 'branchId':
            final cd = Map<String, dynamic>.from(
              _student!['custom_data'] ?? {},
            );
            if (value == null || value == '') {
              cd.remove('branchId');
            } else {
              cd['branchId'] = value;
            }
            _student!['custom_data'] = cd;
          case 'sourceId':
            _student!['source_id'] = value;
        }
      }
      _edited = true;
    });
  }

  // Parse the balance defensively (it can arrive as a string) and color it:
  // red < 0, green > 0, neutral at exactly 0. (Ported from student_detail.)
  num? get _studentBalanceNum => _balance?.balance;

  void _refreshLedger() {
    _fetchStudentData();
  }

  /// «Остаток: 7 астр.ч. / 14 000 ₽» — денежная часть считается по цене пакета
  /// пропорционально оставшимся часам; без пакета показываем только часы.

  /// Возраст «N лет». Считает **сервер** (`age.ts`): дата рождения, если она
  /// есть, иначе вписанное руками число. Здесь только подпись — правило одно
  /// для лида и ученика, и две копии разъехались бы.
  String? _ageLabel() {
    Map<String, dynamic>? source;
    if (_mode.hasStudentHalf && _student != null && _student!['age'] != null) {
      source = _student;
    }
    source ??= _leadData['age'] != null ? _leadData : null;
    if (source == null) return null;

    final years = (source['age'] as num?)?.toInt();
    if (years == null) return null;
    // Младенцу «0 лет» — не ответ. Сервер отдаёт месяцы только для
    // посчитанного из даты рождения возраста, у вписанного руками их нет.
    final months = (source['age_months'] as num?)?.toInt();
    if (years == 0 && months != null) return _monthsLabel(months);
    return '$years ${_pluralRu(years, 'год', 'года', 'лет')}';
  }

  String _monthsLabel(int months) =>
      '$months ${_pluralRu(months, 'месяц', 'месяца', 'месяцев')}';

  /// Русское склонение по числу: 1 год / 2 года / 5 лет, с оговоркой на 11–14.
  String _pluralRu(int n, String one, String few, String many) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return many;
    if (mod10 == 1) return one;
    if (mod10 >= 2 && mod10 <= 4) return few;
    return many;
  }

  /// Дата обращения. Берём разрешённое сервером `appeal_at` (исходная дата из
  /// HolliHop → иначе момент, когда запись появилась в приложении), а на
  /// `created_at` откатываемся только ради старых ответов без этого поля.
  String? _appealAtLabel(Map<String, dynamic> data) {
    final raw = data['appeal_at'] ?? data['created_at'];
    final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (dt == null) return null;
    return DateFormat('dd.MM.yyyy HH:mm', 'ru').format(dt);
  }

  /// Пояснение к дате: важно отличать настоящую дату из HolliHop от той, что
  /// приложение поставило само, — иначе «01.03.2023» и «сегодня» выглядят
  /// одинаково достоверно.
  String? _appealAtSourceLabel(Map<String, dynamic> data) {
    return switch (data['appeal_at_source']?.toString()) {
      'hollihop' => 'из HolliHop',
      'app' => 'дата появления в приложении',
      _ => null,
    };
  }

  String? _leadCreatedAtLabel() => _appealAtLabel(_leadData);

  Color _studentBalanceColor(ColorScheme cs) {
    final b = _studentBalanceNum;
    if (b == null || b == 0) return cs.onSurfaceVariant;
    return b < 0 ? AppTheme.danger : AppTheme.success;
  }

  // Pill badge for the header («Ученик» / «Лид→Ученик»).
  Widget _buildStudentHeader(ColorScheme cs, StatusRecord curStatus) {
    final contact = _studentContact();
    final converted = _isConverted;
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
            child: Icon(
              converted ? Icons.swap_horiz_rounded : Icons.school_outlined,
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
                  contact.name,
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
                      _headerBadge(converted ? 'Лид→Ученик' : 'Ученик'),
                      // For a converted client surface BOTH halves: the lead
                      // status (origin) and the student balance.
                      if (converted) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: curStatus.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            curStatus.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      if (_balance != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Баланс: ${_balance!.balanceRaw} ₽',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _studentBalanceColor(cs),
                            ),
                          ),
                        ),
                      ],
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
}
