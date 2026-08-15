import 'package:intl/intl.dart';

String clientTableFieldText(Map<String, dynamic> field) {
  final label = field['label']?.toString().trim() ?? '';
  final value = clientCustomFieldDisplayValue(
    field['value'],
    field['valueType']?.toString() ?? 'text',
  );
  return label.isEmpty ? value : '$label: $value';
}

String clientCustomFieldDisplayValue(Object? value, String valueType) {
  if (value == null) return 'Не указано';
  if (value is bool) return value ? 'Да' : 'Нет';
  if (value is Iterable) {
    final joined = value.map((item) => item.toString()).join(', ');
    return joined.isEmpty ? 'Не указано' : joined;
  }
  if (valueType == 'date' || valueType == 'datetime') {
    final parsed = DateTime.tryParse(value.toString())?.toLocal();
    if (parsed != null) {
      return DateFormat(
        valueType == 'datetime' ? 'dd.MM.yyyy HH:mm' : 'dd.MM.yyyy',
      ).format(parsed);
    }
  }
  final normalized = value is num && value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  return switch (valueType) {
    'money' => '$normalized ₽',
    'duration' => '$normalized мин.',
    _ => normalized,
  };
}
