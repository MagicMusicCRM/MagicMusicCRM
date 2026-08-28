part of 'client_card.dart';

extension _ClientCardOverviewTab on _ClientCardState {
  // ── Tab: Клиент ───────────────────────────────────────────────────────────
  Widget _buildClientInfoTab(
    ColorScheme cs,
    StatusRecord curStatus, {
    bool embedded = false,
  }) {
    if (_isStudent) {
      return _studentGuard(
        cs,
        () => _buildClientInfoContent(cs, curStatus, embedded: embedded),
      );
    }
    return _buildClientInfoContent(cs, curStatus, embedded: embedded);
  }

  Widget _buildClientInfoContent(
    ColorScheme cs,
    StatusRecord curStatus, {
    required bool embedded,
  }) {
    final duplicateCandidates = _duplicateCandidates
        .where(_isCurrentLeadDuplicateCandidate)
        .toList();
    const padding = EdgeInsets.fromLTRB(
      AppSpace.xl,
      AppSpace.lg,
      AppSpace.xl,
      AppSpace.xl,
    );
    final content = Theme(
      data: clientCardControlTheme(Theme.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_internalContextAllowed) ...[
            ClientInternalNoteCard(
              loading: _internalContextLoading,
              error: _internalContextError,
              note: _internalNote,
              onSave: _saveInternalNote,
              onRetry: _fetchInternalContext,
            ),
            const SizedBox(height: AppSpace.lg),
          ],
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
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: RuPhoneField(
              // Epoch key, not value key — see _buildClientTextField.
              key: ValueKey('client-phone-$_editorEpoch'),
              initialCanonical: _clientPhone,
              decoration: _inputDecoration(cs, label: 'Телефон', isDense: true),
              onCanonicalChanged: (c) {
                _updateClientCore('phone', c.isEmpty ? null : c);
              },
            ),
          ),
          _buildClientTextField(
            cs,
            'Электронная почта',
            _clientEmail,
            (value) => _updateClientCore('email', value),
            keyboard: TextInputType.emailAddress,
          ),
          if (!_loadingMetadata) _buildBranchDropdown(cs, 'Основной филиал'),
          if (!_loadingMetadata) _buildSourceDropdown(cs),

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
            // #7: «Ответственный» — пикер по справочнику сотрудников. A lead
            // writes canonical assignedTo; a student keeps compatible custom_data.
            _buildResponsiblePicker(cs, _isStudent ? 'students' : 'leads'),
            // Возраст: поле ввода, пока нет даты рождения, иначе — посчитанное
            // сервером значение только на просмотр.
            _buildAgeCustomField(cs, _isStudent ? 'students' : 'leads'),
            // KVA-234: мультидисциплины чипами. Контактные лица переехали на
            // вкладку «Семья» (#14) — здесь они дублировали её.
            _buildDisciplinesChips(cs, _isStudent ? 'students' : 'leads'),
            ..._buildCustomFieldControls(
              cs,
              _isStudent ? 'students' : 'leads',
              includeKeys: _ClientCardState._primaryBusinessCustomFieldKeys,
            ),
            // Чёрный список — у обеих половин карточки, а не только у ученика:
            // аккаунт клиента цепляется к любой из них.
            _buildBlacklistToggle(cs),
          ],

          const SizedBox(height: AppSpace.lg),
          _buildCustomFieldsExpansion(cs),

          if (_mode.hasStudentHalf) ...[
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
            const SizedBox(height: AppSpace.lg),
            _studentGroupsInfoCard(groups: _groups),
          ],

          // Дата обращения ученика (✔ решение владельца 16.07: поле живёт на
          // стороне students). У импортированных 3105 учеников она уже лежала
          // в custom_data.addressDate — просто её никто не показывал.
          if (_mode.hasStudentHalf &&
              !_mode.hasLeadHalf &&
              _student != null) ...[
            if (_appealAtLabel(_student!) != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Обращение', [
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Дата обращения',
                  value: _appealAtLabel(_student!)!,
                  hint: _appealAtSourceLabel(_student!),
                ),
                // #9: «Дата визита» из бывшей секции «Дополнительно» — теперь
                // строкой в «Обращении», рядом с датой обращения.
                if (_visitDateLabel() != null)
                  _InfoRow(
                    icon: Icons.event_available_outlined,
                    label: 'Дата визита',
                    value: _visitDateLabel()!,
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
                if (_visitDateLabel() != null)
                  _InfoRow(
                    icon: Icons.event_available_outlined,
                    label: 'Дата визита',
                    value: _visitDateLabel()!,
                  ),
              ]),
            ],
          ],

          const SizedBox(height: AppSpace.lg),
          ClientAppUserPanel(
            entityType: _mode.hasStudentHalf ? 'student' : 'lead',
            entityId: _mode.hasStudentHalf ? _studentId : _leadId,
          ),

          // Агрегат «Связи и активность» — это активность ЛИДА (пробные,
          // похожие лиды). У ученика без лид-половины лид-карточка не грузится
          // вовсе (_loadingCard остался бы true), и секция крутила бы спиннер
          // вечно — поэтому она только при наличии лид-половины.
          if (_mode.hasLeadHalf) ...[
            const SizedBox(height: AppSpace.lg),
            _sectionTitle('Связи и активность'),
            _buildAggregateCard(cs, includeTasks: false),
          ],

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
    if (embedded) {
      return Padding(
        padding: padding,
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: content,
          ),
        ),
      );
    }
    return SingleChildScrollView(padding: padding, child: content);
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

  // Секция «Дополнительно» распущена (#9): «Ответственный» стал пикером (#7),
  // статус HolliHop — подписью у пикеров статуса, «Тип обращения» читается
  // алиасом addressType в общей форме, «Дата визита» — строкой в «Обращении»,
  // «Контактные лица» — на вкладке «Семья» (#14). «Тип лида» и UTM удалены.

  // ── Tab: Задачи ──────────────────────────────────────────────────────────
}
