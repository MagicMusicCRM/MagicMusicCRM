class Env {
  static const String magicApiBaseUrl = String.fromEnvironment(
    'MAGIC_API_BASE_URL',
    defaultValue: 'https://api.phantom-net.ru/api',
  );

  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const String sentryEnvironment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'production',
  );
  static const String sentryRelease = String.fromEnvironment('SENTRY_RELEASE');
  static const String sentryTracesSampleRateRaw = String.fromEnvironment(
    'SENTRY_TRACES_SAMPLE_RATE',
    defaultValue: '0',
  );

  static bool get sentryEnabled => sentryDsn.trim().isNotEmpty;

  static double get sentryTracesSampleRate =>
      double.tryParse(sentryTracesSampleRateRaw) ?? 0;
}
