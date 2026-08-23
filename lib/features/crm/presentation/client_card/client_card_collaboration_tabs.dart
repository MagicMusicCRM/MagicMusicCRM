part of 'client_card.dart';

extension _ClientCardCollaborationTabs on _ClientCardState {
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
          _buildInfoCard('Контакты из прежней системы', [
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
}
