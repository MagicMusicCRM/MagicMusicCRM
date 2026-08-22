import 'dart:convert';
import 'dart:io';

import 'src/naming_policy.dart';

void main() {
  final paths = trackedPaths();
  final exceptions = _loadExceptions(File('tool/naming_exceptions.json'));
  final sources = {
    for (final path in trackedDartSources())
      path: File(path).readAsStringSync(),
  };
  final errors = <NamingViolation>[
    ...findExceptionValidationViolations(
      exceptions: exceptions,
      trackedPaths: paths,
      sources: sources,
    ),
    ...findNamingViolations(paths: paths, exceptions: exceptions),
    ...findSymbolViolations(sources: sources, exceptions: exceptions),
  ];

  final reported = <String>{};
  for (final error in errors) {
    final line = '${error.path}: ${error.rule}';
    if (reported.add(line)) stderr.writeln(line);
  }
  if (errors.isNotEmpty) exitCode = 1;
}

List<NamingPolicyException> _loadExceptions(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! List) {
    throw const FormatException('Naming exceptions must be a JSON array.');
  }
  return [
    for (final entry in decoded)
      if (entry is Map<String, dynamic>)
        NamingPolicyException(
          target: entry['target'] as String? ?? '',
          category: entry['category'] as String? ?? '',
          reason: entry['reason'] as String? ?? '',
          owner: entry['owner'] as String? ?? '',
          removeWhen: entry['remove_when'] as String? ?? '',
        )
      else
        throw const FormatException(
          'Every naming exception must be an object.',
        ),
  ];
}
