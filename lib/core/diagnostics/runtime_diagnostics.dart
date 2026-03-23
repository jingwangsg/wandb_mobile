import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class RuntimeDiagnosticEntry {
  const RuntimeDiagnosticEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    this.data,
    this.stackTrace,
  });

  final DateTime timestamp;
  final String category;
  final String message;
  final Map<String, Object?>? data;
  final String? stackTrace;

  Map<String, Object?> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'category': category,
      'message': message,
      if (data != null) 'data': data,
      if (stackTrace != null) 'stackTrace': stackTrace,
    };
  }

  String toDisplayString() {
    final buffer = StringBuffer()
      ..writeln('[${timestamp.toIso8601String()}] $category')
      ..writeln(message);
    if (data != null && data!.isNotEmpty) {
      buffer.writeln(const JsonEncoder.withIndent('  ').convert(data));
    }
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      buffer.writeln(stackTrace);
    }
    return buffer.toString().trimRight();
  }
}

class RuntimeDiagnostics {
  RuntimeDiagnostics._();

  static final RuntimeDiagnostics instance = RuntimeDiagnostics._();
  static const _maxEntries = 80;

  final ValueNotifier<List<RuntimeDiagnosticEntry>> entries = ValueNotifier(
    const [],
  );

  File? _logFile;
  Future<void> _writeQueue = Future<void>.value();
  bool _initialized = false;
  bool _handlersInstalled = false;

  String? get logFilePath => _logFile?.path;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final directory = await getApplicationSupportDirectory();
      final diagnosticsDirectory = Directory('${directory.path}/diagnostics');
      if (!await diagnosticsDirectory.exists()) {
        await diagnosticsDirectory.create(recursive: true);
      }

      _logFile = File('${diagnosticsDirectory.path}/runtime.log');
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
    } catch (_) {
      _logFile = null;
    }
  }

  void installFlutterHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    final previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      record(
        'flutter_error',
        details.exceptionAsString(),
        data: {
          if (details.library != null) 'library': details.library,
          if (details.context != null)
            'context': details.context!.toDescription(),
        },
        stackTrace: details.stack,
      );
      previousFlutterErrorHandler?.call(details);
    };

    ErrorWidget.builder = (details) {
      record(
        'error_widget',
        details.exceptionAsString(),
        data: {
          if (details.library != null) 'library': details.library,
          if (details.context != null)
            'context': details.context!.toDescription(),
        },
        stackTrace: details.stack,
      );
      return _DiagnosticErrorWidget(details: details);
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      record(
        'platform_error',
        error.toString(),
        stackTrace: stackTrace,
      );
      return false;
    };
  }

  void record(
    String category,
    String message, {
    Map<String, Object?>? data,
    StackTrace? stackTrace,
  }) {
    final entry = RuntimeDiagnosticEntry(
      timestamp: DateTime.now(),
      category: category,
      message: message,
      data: _normalizeMap(data),
      stackTrace: stackTrace?.toString(),
    );

    final nextEntries = [...entries.value, entry];
    final overflow = nextEntries.length - _maxEntries;
    if (overflow > 0) {
      nextEntries.removeRange(0, overflow);
    }
    entries.value = List.unmodifiable(nextEntries);

    if (_logFile == null) return;

    final line = '${jsonEncode(entry.toJson())}\n';
    _writeQueue = _writeQueue
        .then(
          (_) => _logFile!.writeAsString(
            line,
            mode: FileMode.append,
            flush: true,
          ),
        )
        .catchError((_) {});
  }

  String formatRecentEntries({int limit = 8}) {
    final recentEntries = entries.value.reversed.take(limit).toList().reversed;
    if (recentEntries.isEmpty) return 'No diagnostics captured yet.';
    return recentEntries.map((entry) => entry.toDisplayString()).join('\n\n');
  }

  static Map<String, Object?>? _normalizeMap(Map<String, Object?>? value) {
    if (value == null) return null;
    return value.map((key, value) => MapEntry(key, _normalizeValue(value)));
  }

  static Object? _normalizeValue(Object? value) {
    if (value == null ||
        value is String ||
        value is num ||
        value is bool) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Duration) return value.toString();
    if (value is StackTrace) return value.toString();
    if (value is Iterable) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(
          key.toString(),
          _normalizeValue(value),
        ),
      );
    }
    return value.toString();
  }
}

class _DiagnosticErrorWidget extends StatelessWidget {
  const _DiagnosticErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final diagnostics = RuntimeDiagnostics.instance;
    final sections = [
      'Unhandled build error',
      '',
      details.exceptionAsString(),
      if (diagnostics.logFilePath != null) ...[
        '',
        'Local log:',
        diagnostics.logFilePath!,
      ],
      '',
      'Recent diagnostics:',
      diagnostics.formatRecentEntries(limit: 5),
    ];

    return Material(
      color: const Color(0xFF3A0000),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            sections.join('\n'),
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'JetBrains Mono',
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
