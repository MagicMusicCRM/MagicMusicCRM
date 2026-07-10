import 'package:flutter/material.dart';

/// KVA-238: пресеты ставок педагога (₽ за астрономический час) — уровень UI,
/// бекенд хранит произвольное значение.
const List<num> kTeacherRatePresets = [600, 700, 750, 900];

/// Выбор ставки педагога: пресеты 600/700/750/900, «Входит в оклад» (0),
/// «Другая…» (ручной ввод) и, при [allowInherit], «Ставка педагога» (null —
/// снять переопределение группы). Используется в карточке педагога, диалогах
/// группы и drill-down отчёта «Статистика преподавателей».
class TeacherRateSelector extends StatefulWidget {
  /// Текущее значение: num — ставка (0 = «входит в оклад»), null — «ставка
  /// педагога» при [allowInherit] или «не выбрано».
  final num? initialRate;
  final bool allowInherit;
  final String label;

  /// null означает «наследовать ставку педагога» (только при [allowInherit]).
  final ValueChanged<num?> onChanged;

  const TeacherRateSelector({
    super.key,
    required this.onChanged,
    this.initialRate,
    this.allowInherit = false,
    this.label = 'Ставка (₽/астр.ч.)',
  });

  @override
  State<TeacherRateSelector> createState() => _TeacherRateSelectorState();
}

class _TeacherRateSelectorState extends State<TeacherRateSelector> {
  static const _inherit = 'inherit';
  static const _salary = 'salary';
  static const _custom = 'custom';

  late String _mode;
  final _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final rate = widget.initialRate;
    if (rate == null) {
      _mode = widget.allowInherit ? _inherit : _custom;
    } else if (rate == 0) {
      _mode = _salary;
    } else if (kTeacherRatePresets.contains(rate)) {
      _mode = rate.toString();
    } else {
      _mode = _custom;
      _customController.text = rate.toString();
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _emit() {
    switch (_mode) {
      case _inherit:
        widget.onChanged(null);
      case _salary:
        widget.onChanged(0);
      case _custom:
        widget.onChanged(
          num.tryParse(_customController.text.trim().replaceAll(',', '.')),
        );
      default:
        widget.onChanged(num.parse(_mode));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('rate-mode-$_mode'),
          initialValue: _mode,
          decoration: InputDecoration(labelText: widget.label),
          items: [
            if (widget.allowInherit)
              const DropdownMenuItem(
                value: _inherit,
                child: Text('Ставка педагога (по умолчанию)'),
              ),
            ...kTeacherRatePresets.map(
              (rate) => DropdownMenuItem(
                value: rate.toString(),
                child: Text('$rate ₽'),
              ),
            ),
            const DropdownMenuItem(
              value: _salary,
              child: Text('Входит в оклад'),
            ),
            const DropdownMenuItem(value: _custom, child: Text('Другая…')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _mode = value);
            _emit();
          },
        ),
        if (_mode == _custom) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _customController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Своя ставка, ₽/астр.ч.',
            ),
            onChanged: (_) => _emit(),
            validator: (value) {
              final text = value?.trim().replaceAll(',', '.') ?? '';
              if (text.isEmpty) return 'Введите ставку';
              final parsed = num.tryParse(text);
              if (parsed == null || parsed < 0) return 'Некорректная ставка';
              return null;
            },
          ),
        ],
      ],
    );
  }
}
