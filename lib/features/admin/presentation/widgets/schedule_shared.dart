// Shared presentation-only constants and helpers for the schedule feature,
// used by the main widget and the extracted per-view widgets.

const monthNamesNominative = [
  '',
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

const weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// Russian plural selector: [one] (1, 21…), [few] (2–4, 22–24…), [many] (0,
/// 5–20, 11–14…).
String pluralRu(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

const monthNamesGenitive = [
  '',
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// yyyy-MM-dd key for a date (used to index per-day summaries). Pure.
String dateOnly(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Normalises a schedule conflict payload to a list of type strings. Pure.
List<String> conflictTypes(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList();
}

/// Top-level schedule view mode.
enum ScheduleView { year, month, day }

/// Day-view grouping mode.
enum DayViewMode { byRoom, byTeacher }
