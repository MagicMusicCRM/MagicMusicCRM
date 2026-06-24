import 'dart:io' show Platform;

/// Native (desktop/mobile) implementation: reads a real process environment
/// variable so the same binary can run multiple isolated instances.
String? readRuntimeEnv(String key) => Platform.environment[key];
