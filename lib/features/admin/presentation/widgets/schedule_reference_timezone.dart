import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

tz.Location _location(String timezone) {
  if (!_initialized) {
    timezone_data.initializeTimeZones();
    _initialized = true;
  }
  return tz.getLocation(timezone);
}

DateTime scheduleLocalToUtc(DateTime date, String time, String timezone) {
  final parts = time.split(':').map(int.parse).toList();
  final local = tz.TZDateTime(
    _location(timezone),
    date.year,
    date.month,
    date.day,
    parts[0],
    parts[1],
  );
  if (local.year != date.year ||
      local.month != date.month ||
      local.day != date.day ||
      local.hour != parts[0] ||
      local.minute != parts[1]) {
    throw ArgumentError('Local time does not exist in $timezone.');
  }
  return local.toUtc();
}

tz.TZDateTime scheduleUtcToLocal(DateTime utc, String timezone) =>
    tz.TZDateTime.from(utc, _location(timezone));
