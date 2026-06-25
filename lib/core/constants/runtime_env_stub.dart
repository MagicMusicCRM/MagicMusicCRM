/// Web fallback: no process environment is available, so there is no runtime
/// override (the compile-time --dart-define still applies).
String? readRuntimeEnv(String key) => null;
