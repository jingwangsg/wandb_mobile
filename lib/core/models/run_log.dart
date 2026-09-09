class RunLogLine {
  const RunLogLine({
    required this.cursor,
    required this.text,
    this.number,
    this.timestamp,
  });

  final String cursor;
  final String text;
  final int? number;
  final String? timestamp;
}

class RunLogPage {
  const RunLogPage({
    required this.lines,
    this.startCursor,
    this.endCursor,
    this.hasPreviousPage = false,
    this.hasNextPage = false,
  });

  final List<RunLogLine> lines;
  final String? startCursor;
  final String? endCursor;
  final bool hasPreviousPage;
  final bool hasNextPage;
}
