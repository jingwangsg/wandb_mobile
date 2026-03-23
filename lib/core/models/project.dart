class WandbProject {
  const WandbProject({
    required this.id,
    required this.name,
    required this.entityName,
    this.description,
    this.createdAt,
    this.isBenchmark = false,
    this.userName,
  });

  final String id;
  final String name;
  final String entityName;
  final String? description;
  final DateTime? createdAt;
  final bool isBenchmark;
  final String? userName;

  factory WandbProject.fromJson(Map<String, dynamic> json) {
    return WandbProject(
      id: json['id'] as String,
      name: json['name'] as String,
      entityName: json['entityName'] as String,
      description: json['description'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      isBenchmark: json['isBenchmark'] as bool? ?? false,
      userName: (json['user'] as Map<String, dynamic>?)?['username'] as String?,
    );
  }

  String get path => '$entityName/$name';
}
