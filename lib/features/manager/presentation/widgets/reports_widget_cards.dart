part of 'reports_widget.dart';

/// Analytics & finance cards for the overview tab (KVA-198). Split out of the
/// State to keep reports_widget.dart focused on tab/data orchestration.
extension _ReportsAnalyticsCards on _ReportsWidgetState {
  /// «Источники» — lead-source breakdown with an optional share bar.
  Widget _buildSourcesCard() {
    return _AnalyticsCard(
      title: 'Источники',
      icon: Icons.call_split_rounded,
      isLoading: _sources == null && !_sourcesError,
      isError: _sourcesError,
      isEmpty: _readList(_sources, const ['sources', 'items']).isEmpty,
      child: Builder(
        builder: (context) {
          final rows = _readList(_sources, const ['sources', 'items']);
          final colors = Theme.of(context).colorScheme;
          final fmt = NumberFormat('#,##0', 'ru');
          final maxCount = rows.fold<num>(0, (m, r) {
            final c = _asDouble(_pick(r, const ['leads', 'count', 'total']));
            return c > m ? c : m;
          });
          return Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _pick(r, const [
                                    'displayName',
                                    'display_name',
                                    'source',
                                    'name',
                                  ])?.toString() ??
                                  '(не указан)',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            fmt.format(
                              _asDouble(
                                _pick(r, const ['leads', 'count', 'total']),
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColor.gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: maxCount <= 0
                              ? 0
                              : (_asDouble(
                                          _pick(r, const [
                                            'leads',
                                            'count',
                                            'total',
                                          ]),
                                        ) /
                                        maxCount)
                                    .clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: colors.surfaceContainerHighest
                              .withAlpha(60),
                          valueColor: const AlwaysStoppedAnimation(
                            AppTheme.secondaryGold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// «Качество данных» — missing-field / quality metrics as labelled stat rows.
  Widget _buildDataQualityCard() {
    return _AnalyticsCard(
      title: 'Качество данных',
      icon: Icons.verified_outlined,
      isLoading: _dataQuality == null && !_dataQualityError,
      isError: _dataQualityError,
      isEmpty: _dataQuality == null || _dataQuality!.isEmpty,
      child: Builder(
        builder: (context) {
          final data = _dataQuality ?? const <String, dynamic>{};
          final leads = data['leads'] is Map
              ? Map<String, dynamic>.from(data['leads'] as Map)
              : const <String, dynamic>{};
          final students = data['students'] is Map
              ? Map<String, dynamic>.from(data['students'] as Map)
              : const <String, dynamic>{};
          final metrics = <(String, Object?)>[
            ('Лиды всего', _pick(leads, const ['total'])),
            (
              'Лиды без телефона',
              _pick(leads, const ['missingPhone', 'missing_phone']),
            ),
            (
              'Лиды без филиала',
              _pick(leads, const ['missingBranch', 'missing_branch']),
            ),
            ('Ученики всего', _pick(students, const ['total'])),
            (
              'Ученики без филиала',
              _pick(students, const ['missingBranch', 'missing_branch']),
            ),
            (
              'Ученики без направления',
              _pick(students, const [
                'missingDiscipline',
                'missing_discipline',
              ]),
            ),
          ].where((m) => m.$2 != null).toList();

          // Fallback: if the response shape is flatter than expected, render
          // whatever numeric top-level keys it does contain.
          final rows = metrics.isNotEmpty
              ? metrics
              : data.entries
                    .where((e) => e.value is num)
                    .map((e) => (e.key, e.value as Object?))
                    .toList();

          return Column(
            children: [
              for (final m in rows)
                _StatRow(
                  label: m.$1,
                  value: NumberFormat('#,##0', 'ru').format(_asDouble(m.$2)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// «Ответственные» — per-manager lead distribution.
  Widget _buildResponsibleCard() {
    final rows = _readList(_responsible, const ['responsibles', 'items']);
    final hasUnassigned =
        _responsible != null &&
        _pick(_responsible, const ['unassignedLeads', 'unassigned_leads']) !=
            null;
    return _AnalyticsCard(
      title: 'Ответственные',
      icon: Icons.people_alt_outlined,
      isLoading: _responsible == null && !_responsibleError,
      isError: _responsibleError,
      isEmpty: rows.isEmpty && !hasUnassigned,
      child: Builder(
        builder: (context) {
          final fmt = NumberFormat('#,##0', 'ru');
          final unassigned = _asDouble(
            _pick(_responsible, const ['unassignedLeads', 'unassigned_leads']),
          );
          return Column(
            children: [
              for (final r in rows)
                _StatRow(
                  label:
                      _pick(r, const [
                        'name',
                        'fullName',
                        'full_name',
                      ])?.toString() ??
                      '—',
                  value: fmt.format(
                    _asDouble(_pick(r, const ['leads', 'count', 'total'])),
                  ),
                  valueColor: AppColor.gold,
                ),
              if (hasUnassigned)
                _StatRow(
                  label: 'Без ответственного',
                  value: fmt.format(unassigned),
                  valueColor: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            ],
          );
        },
      ),
    );
  }

  /// «Финансы по месяцам» — compact monthly income / expense / net table.
  Widget _buildFinanceMonthlyCard() {
    final rows = _readList(_financeMonthly, const ['items', 'monthly']);
    return _AnalyticsCard(
      title: 'Финансы по месяцам',
      icon: Icons.account_balance_wallet_outlined,
      isLoading: _financeMonthly == null && !_financeMonthlyError,
      isError: _financeMonthlyError,
      isEmpty: rows.isEmpty,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          final fmt = NumberFormat('#,##0', 'ru');
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: SizedBox.shrink()),
                    _financeHeaderCell('Доход', colors),
                    _financeHeaderCell('Расход', colors),
                    _financeHeaderCell('Итог', colors),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final r in rows) _buildFinanceRow(r, fmt, colors),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFinanceRow(
    Map<String, dynamic> r,
    NumberFormat fmt,
    ColorScheme colors,
  ) {
    final revenue = _asDouble(
      _pick(r, const ['revenue', 'income', 'incomeTotal']),
    );
    final expenses = _asDouble(
      _pick(r, const ['expenses', 'expense', 'expensesTotal']),
    );
    // Use server-provided net if present, otherwise derive it defensively.
    final netRaw = _pick(r, const ['net', 'profit', 'balance']);
    final net = netRaw != null ? _asDouble(netRaw) : revenue - expenses;
    final monthLabel = _financeMonthLabel(
      _pick(r, const ['monthStart', 'month_start', 'month']),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              monthLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          _financeValueCell(fmt.format(revenue), AppColor.success),
          _financeValueCell(fmt.format(expenses), AppColor.danger),
          _financeValueCell(
            fmt.format(net),
            net >= 0 ? AppTheme.secondaryGold : AppColor.danger,
          ),
        ],
      ),
    );
  }

  Widget _financeHeaderCell(String label, ColorScheme colors) {
    return Expanded(
      flex: 2,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _financeValueCell(String value, Color color) {
    return Expanded(
      flex: 2,
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
