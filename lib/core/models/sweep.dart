import 'dart:convert';

class WandbSweep {
  const WandbSweep({
    required this.id,
    required this.name,
    this.displayName,
    this.method,
    this.state,
    this.description,
    this.bestLoss,
    this.config = const {},
    this.createdAt,
    this.updatedAt,
    this.runCount = 0,
    this.runCountExpected,
  });

  final String id;
  final String name;
  final String? displayName;
  final String? method; // random, grid, bayes
  final String? state; // RUNNING, FINISHED, etc.
  final String? description;
  final double? bestLoss;
  final Map<String, dynamic> config;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int runCount;
  final int? runCountExpected;

  factory WandbSweep.fromJson(Map<String, dynamic> json) {
    return WandbSweep(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['displayName'] as String?,
      method: json['method'] as String?,
      state: json['state'] as String?,
      description: json['description'] as String?,
      bestLoss: (json['bestLoss'] as num?)?.toDouble(),
      config: _parseConfig(json['config']),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      runCount: json['runCount'] as int? ?? 0,
      runCountExpected: json['runCountExpected'] as int?,
    );
  }

  static Map<String, dynamic> _parseConfig(dynamic value) {
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

  String get label => displayName ?? name;
}
