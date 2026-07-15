import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

part 'finance_widget_widgets.dart';

/// v7 «Расход» category options — Russian label ↔ backend key.
///
/// Backend keys (P5-5) are the canonical `app.expenses.category` values; the
/// labels are what the user picks in the «Добавить расход» sheet.
const List<({String key, String label})> _kExpenseCategories = [
  (key: 'rent', label: 'Аренда'),
  (key: 'salary', label: 'Зарплата'),
  (key: 'utilities', label: 'Коммуналка'),
  (key: 'marketing', label: 'Маркетинг'),
  (key: 'equipment', label: 'Оборудование'),
  (key: 'supplies', label: 'Расходники'),
  (key: 'tax', label: 'Налоги'),
  (key: 'other', label: 'Прочее'),
];

String _expenseCategoryLabel(String? key) {
  for (final c in _kExpenseCategories) {
    if (c.key == key) return c.label;
  }
  return 'Прочее';
}

class FinanceWidget extends ConsumerStatefulWidget {
  const FinanceWidget({super.key});

  @override
  ConsumerState<FinanceWidget> createState() => _FinanceWidgetState();
}

class _FinanceWidgetState extends ConsumerState<FinanceWidget> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  Object? _loadError;
  double _total = 0;
  int _totalCount = 0;
  bool _addingPayment = false;
  String _period = 'month';

  /// When set, overrides [_period] with an explicit user-picked window;
  /// `to` is then prokinut into every analytics call (otherwise «сейчас»).
  DateTimeRange? _customRange;

  // ── Expenses (v7 «Расход» flow, P5-6) ──────────────────────────────────────
  List<Map<String, dynamic>> _expenses = [];
  bool _expensesLoading = true;
  double _expensesTotal = 0;
  bool _savingExpense = false;

  // ── Finance export (P5-7, KVA-198) ─────────────────────────────────────────
  /// Guards the «Экспорт» buttons so a slow download cannot be re-triggered
  /// (and so the UI can show a spinner) — the download runs off the UI thread.
  bool _exporting = false;

  // ── Realtime invalidation (crm.changed) ───────────────────────────────────
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
    _loadPayments();
    _loadExpenses();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    super.dispose();
  }

  DateTime _periodStart() {
    final range = _customRange;
    if (range != null) return range.start;
    final now = DateTime.now();
    switch (_period) {
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'year':
        return DateTime(now.year, 1, 1);
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  DateTime _periodEnd() => _customRange?.end ?? DateTime.now();

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
    );
    if (picked == null || !mounted) return;
    setState(() => _customRange = picked);
    _loadPayments();
    _loadExpenses();
  }

  Future<void> _loadPayments() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final from = _periodStart();

      // Headline total comes from the server aggregate over the FULL period,
      // not a fold over the (capped) page — otherwise «Итого» silently
      // understates revenue once a period exceeds the page size.
      final result = await ref
          .read(magicCrmServiceProvider)
          .listPaymentsWithTotal(
            from: from.toIso8601String(),
            to: _periodEnd().toIso8601String(),
            limit: 100,
          );

      setState(() {
        _payments = result.items;
        _total = result.totalAmount.toDouble();
        _totalCount = result.totalCount;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _addPayment() async {
    if (_addingPayment) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PaymentDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _addingPayment = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createPayment(
            studentId: result['student_id'].toString(),
            amount: result['amount'] as num,
            paymentDate: DateTime.now().toIso8601String(),
            method: result['type']?.toString(),
          );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Платёж добавлен'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadPayments();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось добавить платёж: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _addingPayment = false);
    }
  }

  Future<void> _loadExpenses() async {
    if (mounted) setState(() => _expensesLoading = true);
    try {
      final res = await ref
          .read(magicCrmServiceProvider)
          .listExpenses(
            from: _periodStart().toIso8601String(),
            to: _periodEnd().toIso8601String(),
            limit: 50,
          );
      final items = (res['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final total = (res['total'] as num?)?.toDouble() ?? 0;
      if (!mounted) return;
      setState(() {
        _expenses = items;
        _expensesTotal = total;
        _expensesLoading = false;
      });
    } catch (_) {
      // Expenses are a secondary panel — never block the payments view if the
      // aggregate fails; just show an empty state and let the user retry.
      if (!mounted) return;
      setState(() {
        _expenses = [];
        _expensesTotal = 0;
        _expensesLoading = false;
      });
    }
  }

  Future<void> _addExpense() async {
    if (_savingExpense) return;
    final result = await showMagicSheet<Map<String, dynamic>>(
      context,
      title: 'Добавить расход',
      subtitle: 'Сумма, категория и комментарий',
      icon: Icons.receipt_long_rounded,
      builder: (_) => const _ExpenseSheetForm(),
    );
    if (result == null || !mounted) return;

    setState(() => _savingExpense = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createExpense(
            amount: result['amount'] as num,
            category: result['category'] as String,
            description: result['description'] as String?,
            branchId: result['branchId'] as String?,
          );
      if (mounted) {
        MagicToast.show(
          context,
          'Расход добавлен',
          type: MagicToastType.success,
        );
      }
      await _loadExpenses();
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось добавить расход',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _savingExpense = false);
    }
  }

  /// Downloads the authenticated monthly finance export for the current period
  /// and opens it. [ext] is `csv` or `xlsx`; the endpoint is
  /// `GET /analytics/finance/monthly.<ext>` with the same `from`/`to` window the
  /// widget's other analytics calls use.
  ///
  /// Unlike chat attachments (pre-signed URLs), these endpoints require the
  /// `Authorization` header, so we read the Bearer token straight off the shared
  /// [MagicApiClient] (token store + base URL) and attach it to the `Dio`
  /// download. Guarded by [_exporting] + `mounted` so it never blocks the UI.
  Future<void> _exportFinance(String ext) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final api = ref.read(magicApiClientProvider);
      final tokens = await api.readTokens();
      final accessToken = tokens?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        if (mounted) {
          MagicToast.show(
            context,
            'Не удалось экспортировать',
            detail: 'Нет авторизации — войдите снова',
            type: MagicToastType.danger,
          );
        }
        return;
      }
      final tokenType = tokens?.tokenType.isNotEmpty == true
          ? tokens!.tokenType
          : 'Bearer';

      // Base URL is normalised to a trailing slash by MagicApiClient; the path
      // is normalised to no leading slash to match its request pipeline.
      final baseUrl = api.rawDio.options.baseUrl;
      final url =
          '$baseUrl'
          'analytics/finance/monthly.$ext';

      final from = _periodStart().toIso8601String();
      final to = _periodEnd().toIso8601String();

      final dir = await _exportDirectory();
      final stamp = DateFormat('yyyyMM').format(_periodStart());
      final fileName = 'finance-$stamp.$ext';
      final savePath = '${dir.path}${Platform.pathSeparator}$fileName';

      await Dio().download(
        url,
        savePath,
        queryParameters: {'from': from, 'to': to},
        options: Options(
          headers: {'Authorization': '$tokenType $accessToken'},
          responseType: ResponseType.bytes,
        ),
      );

      await OpenFilex.open(savePath);
      if (mounted) {
        MagicToast.show(
          context,
          'Файл сохранён',
          detail: fileName,
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      debugPrint('Finance export error: $e');
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка экспорта',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Prefers the platform Downloads folder; falls back to Android external
  /// storage and finally the temp dir — mirrors [FileAttachmentWidget].
  Future<Directory> _exportDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      await downloads.create(recursive: true);
      return downloads;
    }
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final fallback = Directory('${external.path}/Download');
        await fallback.create(recursive: true);
        return fallback;
      }
    }
    final temp = await getTemporaryDirectory();
    await temp.create(recursive: true);
    return temp;
  }

  String _typeLabel(String? t) {
    switch (t) {
      case 'extra_lesson':
        return 'Доп. занятие';
      case 'other':
        return 'Прочее';
      default:
        return 'Абонемент';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: refresh totals/lists when another staff member records a payment
    // or an expense.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || !mounted) return;
      if (event.isFallbackPoll) return;
      if (event.entity != 'payment' && event.entity != 'expense') return;
      // Skip while a load or an add (payment/expense) is in flight — those
      // refetch themselves on completion.
      if (_loading || _addingPayment || _savingExpense) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _loading || _addingPayment || _savingExpense) return;
        _loadPayments();
        _loadExpenses();
      });
    });
    final fmt = NumberFormat('#,##0', 'ru');
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _addingPayment ? null : _addPayment,
        child: _addingPayment
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant.withAlpha(90)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Итого поступлений',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${fmt.format(_total)} ₽',
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_customRange != null)
                        Text(
                          '${DateFormat('d MMM yyyy', 'ru').format(_customRange!.start)} — '
                          '${DateFormat('d MMM yyyy', 'ru').format(_customRange!.end)}',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      if (_totalCount > _payments.length)
                        Text(
                          'Всего платежей: $_totalCount · '
                          'показаны первые ${_payments.length}',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Выбрать диапазон',
                  onPressed: _pickRange,
                  icon: Icon(
                    Icons.calendar_today_rounded,
                    size: 20,
                    color: _customRange != null
                        ? AppTheme.success
                        : colors.onSurfaceVariant,
                  ),
                ),
                if (_customRange != null)
                  IconButton(
                    tooltip: 'Сбросить диапазон',
                    onPressed: () {
                      setState(() => _customRange = null);
                      _loadPayments();
                      _loadExpenses();
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'week', label: Text('Нед.')),
                    ButtonSegment(value: 'month', label: Text('Мес.')),
                    ButtonSegment(value: 'year', label: Text('Год')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) {
                    setState(() {
                      _period = s.first;
                      _customRange = null;
                    });
                    _loadPayments();
                    _loadExpenses();
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppTheme.success.withAlpha(30)
                          : Colors.transparent,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppTheme.success
                          : colors.onSurfaceVariant,
                    ),
                    side: WidgetStateProperty.all(
                      BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _ExportBar(
            exporting: _exporting,
            onExportCsv: () => _exportFinance('csv'),
            onExportXlsx: () => _exportFinance('xlsx'),
          ),
          _ExpensesPanel(
            loading: _expensesLoading,
            saving: _savingExpense,
            total: _expensesTotal,
            expenses: _expenses,
            onAdd: _addExpense,
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: AppTheme.success),
                  )
                : _loadError != null
                ? _FinanceError(error: _loadError, onRetry: _loadPayments)
                : _payments.isEmpty
                ? Center(
                    child: Text(
                      'Нет платежей за период',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: AppTheme.success,
                    onRefresh: _loadPayments,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _payments.length,
                      itemBuilder: (ctx, i) {
                        final p = _payments[i];
                        final amount =
                            double.tryParse(p['amount'].toString()) ?? 0;
                        final type = _typeLabel(p['type'] as String?);
                        final student = p['students'];
                        final name = student != null
                            ? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'
                                  .trim()
                            : 'Неизвестный ученик';
                        // Show when the payment actually happened
                        // (payment_date), not when the row was inserted, so
                        // late-entered payments don't appear in the wrong period.
                        final rawDate = p['payment_date'] ?? p['created_at'];
                        final dt = rawDate != null
                            ? DateTime.tryParse(rawDate.toString())
                            : null;
                        final dateStr = dt != null
                            ? DateFormat(
                                'd MMM yyyy, HH:mm',
                                'ru',
                              ).format(dt.toLocal())
                            : '';
                        final note = (p['notes'] ?? p['description'] ?? '')
                            .toString()
                            .trim();
                        final subtitle = [
                          type,
                          if (dateStr.isNotEmpty) dateStr,
                          if (note.isNotEmpty) note,
                        ].join(' · ');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: student != null
                                ? () async {
                                    final id = student['id']?.toString();
                                    if (id == null || id.isEmpty) return;
                                    await showClientCard(
                                      context,
                                      entityType: 'student',
                                      entityId: id,
                                    );
                                    _loadPayments();
                                  }
                                : null,
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(25),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.payments_rounded,
                                color: AppTheme.success,
                              ),
                            ),
                            title: Text(
                              name.isEmpty ? 'Без имени' : name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              subtitle,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Text(
                              '${fmt.format(amount)} ₽',
                              style: const TextStyle(
                                color: AppTheme.success,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

