class RunFile {
  const RunFile({
    required this.id,
    required this.name,
    this.url,
    this.directUrl,
    this.sizeBytes,
    this.mimetype,
    this.updatedAt,
    this.md5,
  });

  final String id;
  final String name;
  final String? url;
  final String? directUrl;
  final int? sizeBytes;
  final String? mimetype;
  final DateTime? updatedAt;
  final String? md5;

  factory RunFile.fromJson(Map<String, dynamic> json) {
    return RunFile(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String?,
      directUrl: json['directUrl'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      mimetype: json['mimetype'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      md5: json['md5'] as String?,
    );
  }

  String get formattedSize {
    if (sizeBytes == null) return '';
    if (sizeBytes! < 1024) return '${sizeBytes}B';
    if (sizeBytes! < 1024 * 1024) return '${(sizeBytes! / 1024).toStringAsFixed(1)}KB';
    if (sizeBytes! < 1024 * 1024 * 1024) {
      return '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(sizeBytes! / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
