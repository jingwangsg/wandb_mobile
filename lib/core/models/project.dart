class WandbProject {
  const WandbProject({
    required this.id,
    required this.name,
    required this.entityName,
    this.description,
    this.createdAt,
    this.runCount = 0,
    this.isBenchmark = false,
    this.userName,
    this.lastActive,
    this.starred = false,
  });

  final String id;
  final String name;
  final String entityName;
  final String? description;
  final DateTime? createdAt;
  final int runCount;
  final bool isBenchmark;
  final String? userName;
  final DateTime? lastActive;
  final bool starred;

  factory WandbProject.fromJson(Map<String, dynamic> json) {
    return WandbProject(
      id: json['id'] as String,
      name: json['name'] as String,
      entityName: json['entityName'] as String,
      description: json['description'] as String?,
      createdAt:
          json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'] as String)
              : null,
      runCount: json['runCount'] as int? ?? 0,
      isBenchmark: json['isBenchmark'] as bool? ?? false,
      userName: (json['user'] as Map<String, dynamic>?)?['username'] as String?,
      lastActive: DateTime.tryParse(json['lastActive'] as String? ?? ''),
      starred: json['starred'] as bool? ?? false,
    );
  }

  String get path => '$entityName/$name';
}
