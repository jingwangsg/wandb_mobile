import 'dart:convert';

class ValuePresentation {
  const ValuePresentation({
    required this.inlineText,
    required this.fullText,
    required this.isJson,
    required this.isExpandable,
  });

  final String inlineText;
  final String fullText;
  final bool isJson;
  final bool isExpandable;

  factory ValuePresentation.fromValue(dynamic value) {
    final jsonValue = _tryJsonValue(value);
    final isJson = jsonValue != null;
    final fullText =
        jsonValue != null
            ? const JsonEncoder.withIndent('  ' ).convert(jsonValue)
            : _stringify(value);
    final inlineText = _inlinePreview(
      isJson ? jsonEncode(jsonValue) : fullText,
    );
    final isExpandable =
        isJson || fullText.length > 80 || fullText.contains('\n');

    return ValuePresentation(
      inlineText: inlineText,
      fullText: fullText,
      isJson: isJson,
      isExpandable: isExpandable,
    );
  }

  static Object? _tryJsonValue(dynamic value) {
    if (value is Map || value is List) return value;
    if (value is String) {
      final trimmed = value.trim();
      if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is Map || parsed is List) return parsed;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _stringify(dynamic value) {
    if (value == null) return 'null';
    return value.toString();
  }

  static String _inlinePreview(String text) {
    return text
        .replaceAll('\\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
  }
}
