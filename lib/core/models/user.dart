class WandbUser {
  const WandbUser({
    required this.id,
    required this.username,
    this.name,
    this.email,
    required this.entity,
    this.teams = const [],
  });

  final String id;
  final String username;
  final String? name;
  final String? email;
  final String entity;
  final List<String> teams;

  factory WandbUser.fromJson(Map<String, dynamic> json) {
    final teamsEdges = json['teams']?['edges'] as List? ?? [];
    return WandbUser(
      id: json['id'] as String,
      username: json['username'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      entity: json['entity'] as String,
      teams: teamsEdges
          .map((e) => (e as Map<String, dynamic>)['node']['name'] as String)
          .toList(),
    );
  }

  /// All available entities: personal entity + team names.
  List<String> get allEntities => [entity, ...teams];
}
