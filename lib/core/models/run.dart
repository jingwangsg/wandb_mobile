import 'dart:convert';

enum RunState {
  running,
  finished,
  failed,
  crashed,
  preempted,
  preempting,
  pending,
  unknown;

  static RunState fromString(String? s) {
    if (s == null) return RunState.unknown;
    return RunState.values.firstWhere(
      (e) => e.name == s.toLowerCase(),
      orElse: () => RunState.unknown,
    );
  }

  bool get isActive => this == running || this == preempting || this == pending;
  bool get isTerminal => this == finished || this == failed || this == crashed;
}

class WandbRun {
  const WandbRun({
    required this.id,
    required this.name,
    required this.displayName,
    required this.state,
    this.config = const {},
    this.summaryMetrics = const {},
    this.systemMetrics = const {},
    this.tags = const [],
    this.group,
    this.jobType,
    this.sweepName,
    this.createdAt,
    this.heartbeatAt,
    this.description,
    this.notes,
    this.userName,
    this.historyLineCount = 0,
    this.historyKeys,
  });

  final String id;
  final String name; // internal run ID
  final String displayName;
  final RunState state;
  final Map<String, dynamic> config;
  final Map<String, dynamic> summaryMetrics;
  final Map<String, dynamic> systemMetrics;
  final List<String> tags;
  final String? group;
  final String? jobType;
  final String? sweepName;
  final DateTime? createdAt;
  final DateTime? heartbeatAt;
  final String? description;
  final String? notes;
  final String? userName;
  final int historyLineCount;
  final Map<String, dynamic>? historyKeys;

  factory WandbRun.fromJson(Map<String, dynamic> json) {
    return WandbRun(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['displayName'] as String? ?? json['name'] as String,
      state: RunState.fromString(json['state'] as String?),
      config: _parseJsonString(json['config']),
      summaryMetrics: _parseJsonString(json['summaryMetrics']),
      systemMetrics: _parseJsonString(json['systemMetrics']),
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      group: json['group'] as String?,
      jobType: json['jobType'] as String?,
      sweepName: json['sweepName'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      heartbeatAt: json['heartbeatAt'] != null
          ? DateTime.tryParse(json['heartbeatAt'] as String)
          : null,
      description: json['description'] as String?,
      notes: json['notes'] as String?,
      userName:
          (json['user'] as Map<String, dynamic>?)?['username'] as String?,
      historyLineCount: json['historyLineCount'] as int? ?? 0,
      historyKeys: _parseJsonString(json['historyKeys']),
    );
  }

  /// wandb returns config/summaryMetrics/systemMetrics as JSON strings.
  static Map<String, dynamic> _parseJsonString(dynamic value) {
    if (value == null) return const {};
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        final parsed = jsonDecode(value);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {}
    }
    return const {};
  }

  /// Extract a flat config map, unwrapping wandb's {"key": {"value": X}} format.
  Map<String, dynamic> get flatConfig {
    return config.map((key, value) {
      if (value is Map && value.containsKey('value')) {
        return MapEntry(key, value['value']);
      }
      return MapEntry(key, value);
    });
  }

  Duration? get duration {
    if (createdAt == null) return null;
    final end = heartbeatAt ?? DateTime.now();
    return end.difference(createdAt!);
  }
}
