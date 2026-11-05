String normalizeBlockCode(String value) {
  return value.trim().toUpperCase();
}

List<String> normalizeBlockCodes(Iterable<String> values) {
  final seen = <String>{};
  final normalized = <String>[];

  for (final value in values) {
    final block = normalizeBlockCode(value);
    if (block.isEmpty || !seen.add(block)) {
      continue;
    }
    normalized.add(block);
  }

  return normalized;
}
