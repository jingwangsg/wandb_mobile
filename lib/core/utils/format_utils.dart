/// Format a Duration as a human-readable "Xd Xh Xm" or "Xm Xs" string.
String formatDuration(Duration d) {
  if (d.inDays > 0) {
    return '${d.inDays}d ${d.inHours.remainder(24)}h';
  }
  if (d.inHours > 0) {
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
  return '${d.inSeconds}s';
}

/// Format a DateTime as relative time ("2h ago", "3d ago").
String formatRelativeTime(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'just now';
}

/// Format a number for display (scientific notation for very small/large).
String formatMetricValue(dynamic value) {
  if (value == null) return '-';
  if (value is String) return value;
  if (value is int) return value.toString();
  if (value is double) {
    if (value.isNaN || value.isInfinite) return value.toString();
    final abs = value.abs();
    if (abs == 0) return '0';
    if (abs >= 1e6 || abs < 1e-3) return value.toStringAsExponential(3);
    if (abs >= 100) return value.toStringAsFixed(1);
    if (abs >= 1) return value.toStringAsFixed(3);
    return value.toStringAsFixed(4);
  }
  return value.toString();
}
