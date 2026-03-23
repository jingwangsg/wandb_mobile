import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/diagnostics/diagnostic_format.dart';
import '../../../../core/diagnostics/runtime_diagnostics.dart';
import '../../../../core/models/paginated.dart';
import '../../../../core/models/run_file.dart';
import '../../../../core/utils/format_utils.dart';
import '../../providers/runs_providers.dart';

class RunFilesPanel extends ConsumerStatefulWidget {
  const RunFilesPanel({
    super.key,
    required this.entity,
    required this.project,
    required this.runName,
  });

  final String entity;
  final String project;
  final String runName;

  @override
  ConsumerState<RunFilesPanel> createState() => _RunFilesPanelState();
}

class _RunFilesPanelState extends ConsumerState<RunFilesPanel> {
  PaginatedResult<RunFile>? _files;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _requestSequence = 0;
  Map<String, Object?>? _lastRequestDetails;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles({bool append = false}) async {
    final currentFiles = _files;
    if (append) {
      if (_loadingMore || currentFiles == null || !currentFiles.hasNextPage) {
        return;
      }
    }

    final requestId = ++_requestSequence;
    final cursor = append ? currentFiles?.endCursor : null;
    final requestDetails = <String, Object?>{
      'entity': widget.entity,
      'project': widget.project,
      'runName': widget.runName,
      'cursor': cursor,
      'limit': 50,
      'append': append,
    };

    setState(() {
      _error = null;
      _lastRequestDetails = requestDetails;
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
    });

    RuntimeDiagnostics.instance.record(
      'run_files_request',
      append ? 'Loading additional run files' : 'Loading run files',
      data: requestDetails,
    );

    try {
      final repo = ref.read(runsRepositoryProvider);
      final result = await repo.getRunFiles(
        entity: widget.entity,
        project: widget.project,
        runName: widget.runName,
        cursor: cursor,
      );
      if (!mounted || requestId != _requestSequence) return;

      final mergedFiles =
          append && currentFiles != null
              ? currentFiles.appendPage(result)
              : result;

      setState(() {
        _files = mergedFiles;
        _loading = false;
        _loadingMore = false;
      });

      RuntimeDiagnostics.instance.record(
        'run_files_request_succeeded',
        'Loaded run files',
        data: {
          ...requestDetails,
          'count': mergedFiles.items.length,
          'totalCount': mergedFiles.totalCount,
          'hasNextPage': mergedFiles.hasNextPage,
        },
      );
    } catch (e, st) {
      RuntimeDiagnostics.instance.record(
        'run_files_request_failed',
        'Failed to load run files',
        data: {...requestDetails, 'error': e.toString()},
        stackTrace: st,
      );
      if (!mounted || requestId != _requestSequence) return;

      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openFile(RunFile file) async {
    final url = file.directUrl ?? file.url;
    if (url == null) return;

    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open file URL')));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to open file')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _files == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _buildErrorView();

    final files = _files?.items ?? const <RunFile>[];
    if (files.isEmpty) {
      return const Center(child: Text('No files found'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Run Files',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                _files?.totalCount != null
                    ? '${_files!.totalCount} files'
                    : '${files.length} files',
                style: const TextStyle(color: Colors.white54),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : () => _loadFiles(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: files.length + (_files!.hasNextPage ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index >= files.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed:
                          _loadingMore ? null : () => _loadFiles(append: true),
                      icon:
                          _loadingMore
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.expand_more),
                      label: Text(
                        _loadingMore ? 'Loading…' : 'Load more files',
                      ),
                    ),
                  ),
                );
              }

              final file = files[index];
              return ListTile(
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _formatSubtitle(file),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54),
                ),
                trailing: TextButton.icon(
                  onPressed:
                      file.directUrl != null || file.url != null
                          ? () => _openFile(file)
                          : null,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatSubtitle(RunFile file) {
    final parts = <String>[
      if (file.formattedSize.isNotEmpty) file.formattedSize,
      if (file.mimetype != null && file.mimetype!.isNotEmpty) file.mimetype!,
      if (file.updatedAt != null) formatRelativeTime(file.updatedAt),
    ];
    return parts.isEmpty ? 'No metadata available' : parts.join(' • ');
  }

  Widget _buildErrorView() {
    final diagnostics = RuntimeDiagnostics.instance;
    final requestText =
        _lastRequestDetails == null
            ? 'No request captured.'
            : formatDiagnosticJson(_lastRequestDetails!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Failed to load files',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SelectableText(
          _error ?? 'Unknown error',
          style: const TextStyle(
            color: Colors.white70,
            fontFamily: 'JetBrains Mono',
          ),
        ),
        const SizedBox(height: 16),
        _RunFilesDiagnosticSection(
          title: 'Request Parameters',
          body: requestText,
        ),
        const SizedBox(height: 12),
        _RunFilesDiagnosticSection(
          title: 'Recent Diagnostics',
          body: diagnostics.formatRecentEntries(),
        ),
        if (diagnostics.logFilePath != null) ...[
          const SizedBox(height: 12),
          _RunFilesDiagnosticSection(
            title: 'Local Log File',
            body: diagnostics.logFilePath!,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _loadFiles,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _RunFilesDiagnosticSection extends StatelessWidget {
  const _RunFilesDiagnosticSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            body,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
