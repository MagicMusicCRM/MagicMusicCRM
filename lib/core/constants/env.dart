import 'runtime_env_stub.dart'
    if (dart.library.io) 'runtime_env_io.dart';

class Env {
  static const String magicApiBaseUrl = String.fromEnvironment(
    'MAGIC_API_BASE_URL',
    defaultValue: 'https://api.phantom-net.ru/api',
  );

  /// Isolates per-instance local state (secure-storage token keys) so the same
  /// desktop binary can run several windows logged into different accounts.
  /// Set the `MAGIC_PROFILE` environment variable before launching (e.g. via a
  /// .bat), or pass `--dart-define=MAGIC_PROFILE=...` at build time. Empty by
  /// default → the shared, backward-compatible storage keys.
  static String get storageNamespace {
    const fromDefine = String.fromEnvironment('MAGIC_PROFILE');
    final raw = fromDefine.isNotEmpty
        ? fromDefine
        : (readRuntimeEnv('MAGIC_PROFILE') ?? '');
    return raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  }

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
