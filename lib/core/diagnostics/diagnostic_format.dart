import 'dart:convert';

String formatDiagnosticJson(Map<String, Object?> value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}
