import 'dart:io';

class NamingPolicyException {
  const NamingPolicyException({
    required this.target,
    required this.category,
    required this.reason,
    required this.owner,
    required this.removeWhen,
  });

  final String target;
  final String category;
  final String reason;
  final String owner;
  final String removeWhen;
}

class NamingViolation {
  const NamingViolation(this.path, this.rule);

  final String path;
  final String rule;
}

List<String> trackedPaths() {
  final result = Process.runSync('git', const ['ls-files']);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      const ['ls-files'],
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
  return (result.stdout as String)
      .split(RegExp(r'\r?\n'))
      .where((path) => path.isNotEmpty)
      .toList();
}

List<String> trackedDartSources() => trackedPaths()
    .where((path) => path.startsWith('lib/') && path.endsWith('.dart'))
    .toList();

List<NamingViolation> findNamingViolations({
  required Iterable<String> paths,
  required List<NamingPolicyException> exceptions,
}) {
  final generation = RegExp(r'(^|[/_-])v\d+([/_.-]|$)', caseSensitive: false);
  final partSuffix = RegExp(r'_[abc]\.dart$', caseSensitive: false);
  final temporary = RegExp(
    r'(^|[/_])(old|new|temp|tmp)([/_.-]|$)',
    caseSensitive: false,
  );
  final testBucket = RegExp(r'^test/features/(v\d+|s\d+)/');
  bool productionSource(String path) =>
      path.startsWith('lib/') || path.startsWith('server/src/');

  return [
    for (final path in paths.where(productionSource))
      if (!isExceptionCovered(path, exceptions) && generation.hasMatch(path))
        NamingViolation(path, 'production-generation-name'),
    for (final path in paths.where((path) => path.startsWith('lib/')))
      if (!isExceptionCovered(path, exceptions) && partSuffix.hasMatch(path))
        NamingViolation(path, 'mechanical-part-suffix'),
    for (final path in paths.where(productionSource))
      if (!isExceptionCovered(path, exceptions) && temporary.hasMatch(path))
        NamingViolation(path, 'temporary-name'),
    for (final path in paths.where(testBucket.hasMatch))
      if (!isExceptionCovered(path, exceptions))
        NamingViolation(path, 'test-generation-bucket'),
  ];
}

List<NamingViolation> findSymbolViolations({
  required Map<String, String> sources,
  required List<NamingPolicyException> exceptions,
}) {
  final generationSymbol = RegExp(
    r'\b(?:_?V\d+[A-Z][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*V\d+(?:[A-Z][A-Za-z0-9_]*)?)\b',
  );

  return [
    for (final entry in sources.entries)
      for (final match in generationSymbol.allMatches(
        _withoutCommentsAndStrings(entry.value),
      ))
        if (!isExceptionCovered('${entry.key}::${match.group(0)}', exceptions))
          NamingViolation(
            '${entry.key}::${match.group(0)}',
            'production-generation-symbol',
          ),
  ];
}

bool isExceptionCovered(
  String finding,
  Iterable<NamingPolicyException> exceptions,
) => exceptions.any((exception) {
  final target = exception.target.trim();
  if (target.isEmpty) return false;
  return target.contains('::') ? target == finding : finding.startsWith(target);
});

List<NamingViolation> findExceptionValidationViolations({
  required Iterable<NamingPolicyException> exceptions,
  required Iterable<String> trackedPaths,
  required Map<String, String> sources,
}) {
  final tracked = trackedPaths.toList();
  return [
    for (final exception in exceptions) ...[
      if (exception.target.trim().isEmpty)
        NamingViolation(exception.target, 'empty-target'),
      if (exception.category.trim().isEmpty)
        NamingViolation(exception.target, 'empty-category'),
      if (exception.reason.trim().isEmpty)
        NamingViolation(exception.target, 'empty-reason'),
      if (exception.owner.trim().isEmpty)
        NamingViolation(exception.target, 'empty-owner'),
      if (exception.removeWhen.trim().isEmpty)
        NamingViolation(exception.target, 'empty-remove_when'),
      if (!_matchesTrackedPathOrSymbol(exception, tracked, sources))
        NamingViolation(exception.target, 'unused-naming-exception'),
    ],
  ];
}

bool _matchesTrackedPathOrSymbol(
  NamingPolicyException exception,
  Iterable<String> paths,
  Map<String, String> sources,
) {
  final target = exception.target.trim();
  if (target.isEmpty) return false;
  final targetParts = target.split('::');
  final targetPath = targetParts.first;
  if (!paths.any((path) => path.startsWith(targetPath))) return false;
  if (targetParts.length == 1) return true;

  final source = sources[targetPath];
  if (source == null) return false;
  return findSymbolViolations(
    sources: {targetPath: source},
    exceptions: const [],
  ).any((violation) => violation.path == exception.target);
}

String _withoutCommentsAndStrings(String source) {
  final result = StringBuffer();
  var index = 0;

  while (index < source.length) {
    final current = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';

    if (current == '/' && next == '/') {
      final end = source.indexOf('\n', index);
      final stop = end == -1 ? source.length : end;
      result.write(' ' * (stop - index));
      index = stop;
      continue;
    }
    if (current == '/' && next == '*') {
      final end = source.indexOf('*/', index + 2);
      final stop = end == -1 ? source.length : end + 2;
      result.write(
        source.substring(index, stop).replaceAll(RegExp(r'[^\n]'), ' '),
      );
      index = stop;
      continue;
    }

    final quoteIndex =
        current.toLowerCase() == 'r' && (next == "'" || next == '"')
        ? index + 1
        : (current == "'" || current == '"' ? index : -1);
    if (quoteIndex != -1) {
      final quote = source[quoteIndex];
      final triple =
          quoteIndex + 2 < source.length &&
          source[quoteIndex + 1] == quote &&
          source[quoteIndex + 2] == quote;
      var stop = quoteIndex + (triple ? 3 : 1);
      while (stop < source.length) {
        if (!triple && source[stop] == '\\') {
          stop += 2;
          continue;
        }
        if (triple &&
            stop + 2 < source.length &&
            source[stop] == quote &&
            source[stop + 1] == quote &&
            source[stop + 2] == quote) {
          stop += 3;
          break;
        }
        if (!triple && source[stop] == quote) {
          stop++;
          break;
        }
        stop++;
      }
      result.write(
        source.substring(index, stop).replaceAll(RegExp(r'[^\n]'), ' '),
      );
      index = stop;
      continue;
    }

    result.write(current);
    index++;
  }

  return result.toString();
}
