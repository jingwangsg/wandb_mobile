import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/resource_refs.dart';
import '../../../core/models/run.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/mobile_controls.dart';
import '../../../core/widgets/wandb_icon.dart';
import '../../charts/presentation/panels_view.dart';
import '../../aria/data/aria_repository.dart';
import '../providers/runs_providers.dart';
import '../providers/run_metadata_provider.dart';
import 'widgets/run_files_panel.dart';
import 'widgets/run_logs_view.dart';

class RunDetailScreen extends ConsumerStatefulWidget {
  const RunDetailScreen({
    super.key,
    required this.entity,
    required this.project,
    required this.runName,
    this.run,
    this.embedded = false,
  });
  final String entity;
  final String project;
  final String runName;
  final WandbRun? run;
  final bool embedded;

  @override
  ConsumerState<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends ConsumerState<RunDetailScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  WandbRun? _run;
  Object? _error;
  Timer? _poll;
  bool _loading = false;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        ref.read(ariaProjectContextProvider.notifier).state = ProjectRef(
          entity: widget.entity,
          project: widget.project,
        );
    });
    _run = widget.run;
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    if (_run == null) _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          (_run?.state.isActive ?? true) &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final run = await ref
          .read(runsRepositoryProvider)
          .getRun(
            entity: widget.entity,
            project: widget.project,
            runName: widget.runName,
          );
      if (mounted) setState(() => _run = run);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final project = ProjectRef(entity: widget.entity, project: widget.project);
    final body =
        run == null
            ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : MobileEmptyState(
                  title: 'Unable to load run',
                  message: '$_error',
                  icon: 'warning',
                  onRetry: _load,
                )
            : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: WandbColors.forRunState(run.state.name),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${run.state.name} · ${formatRelativeTime(run.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (_stopping) const Text('Stop requested'),
                    ],
                  ),
                ),
                if (_error != null)
                  ListTile(
                    title: const Text('Unable to refresh run'),
                    trailing: TextButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ),
                TabBar(
                  controller: _tabs,
                  tabs: const [
                    Tab(text: 'Charts'),
                    Tab(text: 'Overview'),
                    Tab(text: 'Logs'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      PanelsView(
                        project: project,
                        run: run,
                        visible: _tabs.index == 0,
                      ),
                      RunOverviewView(
                        run: run,
                        runRef: RunRef(
                          entity: widget.entity,
                          project: widget.project,
                          runName: run.name,
                        ),
                      ),
                      RunLogsView(
                        run: RunRef(
                          entity: widget.entity,
                          project: widget.project,
                          runName: run.name,
                        ),
                        active: run.state.isActive,
                        visible: _tabs.index == 2,
                      ),
                    ],
                  ),
                ),
              ],
            );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          run?.displayName ?? widget.runName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const WandbIcon('overflow_(horizontal)'),
            itemBuilder:
                (_) => [
                  const PopupMenuItem(
                    value: 'project',
                    child: Text('View project'),
                  ),
                  const PopupMenuItem(value: 'files', child: Text('Files')),
                  const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                  if (run != null &&
                      run.state.isActive &&
                      !run.readOnly &&
                      !_stopping)
                    const PopupMenuItem(value: 'stop', child: Text('Stop run')),
                ],
            onSelected: (action) async {
              if (action == 'project') {
                context.go(
                  '/projects/${Uri.encodeComponent(widget.entity)}/${Uri.encodeComponent(widget.project)}',
                );
              }
              if (action == 'refresh') _load();
              if (action == 'files') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => Scaffold(
                          appBar: AppBar(title: const Text('Files')),
                          body: RunFilesPanel(
                            entity: widget.entity,
                            project: widget.project,
                            runName: widget.runName,
                          ),
                        ),
                  ),
                );
              }
              if (action != 'stop' || run == null) return;
              final confirmed = await showDialog<bool>(
                context: context,
                builder:
                    (dialogContext) => AlertDialog(
                      title: const Text('Stop this run?'),
                      content: Text(
                        'Stop run “${run.displayName}”? This action cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Stop Run'),
                        ),
                      ],
                    ),
              );
              if (confirmed != true || !mounted) return;
              setState(() => _stopping = true);
              try {
                await ref.read(runsRepositoryProvider).stopRun(run.id);
                await _load();
              } catch (error) {
                if (context.mounted) {
                  setState(() => _stopping = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not stop run: $error')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: body,
    );
  }
}

class RunOverviewView extends ConsumerWidget {
  const RunOverviewView({super.key, required this.run, required this.runRef});
  final WandbRun run;
  final RunRef runRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(runMetadataProvider(runRef));
    final environment = metadata.valueOrNull ?? {};
    final sections = <String, Map<String, dynamic>>{
      'Run overview': {
        'State': run.state.name,
        'Run ID': run.name,
        if (run.userName != null) 'Author': run.userName,
        if (run.createdAt != null)
          'Start time': run.createdAt!.toLocal().toString(),
        if (run.duration != null) 'Runtime': formatDuration(run.duration!),
        if (run.group != null) 'Group': run.group,
        if (run.jobType != null) 'Job type': run.jobType,
        if (run.tags.isNotEmpty) 'Tags': run.tags,
        if (run.notes?.isNotEmpty == true) 'Notes': run.notes,
        for (final entry
            in const {
              'os': 'OS',
              'python': 'Python version',
              'executable': 'Python executable',
              'cpu_count': 'CPU count',
              'cpu_count_logical': 'Logical CPU count',
              'gpu': 'GPU type',
              'gpu_count': 'GPU count',
            }.entries)
          if (environment[entry.key] != null)
            entry.value: environment[entry.key],
      },
      'Config': Map.fromEntries(
        run.flatConfig.entries.where((entry) => !entry.key.startsWith('_')),
      ),
      'Summary': Map.fromEntries(
        run.summaryMetrics.entries.where((entry) => !entry.key.startsWith('_')),
      ),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (metadata.hasError)
          ListTile(
            title: const Text('Unable to load environment details'),
            trailing: TextButton(
              onPressed: () => ref.invalidate(runMetadataProvider(runRef)),
              child: const Text('Retry'),
            ),
          ),
        for (final section in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              section.key,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Card(
            child: Column(
              children: [
                if (section.value.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No values logged'),
                  ),
                for (final entry in section.value.entries)
                  Builder(
                    builder: (context) {
                      final value =
                          entry.value is String
                              ? entry.value as String
                              : const JsonEncoder.withIndent(
                                '  ',
                              ).convert(entry.value);
                      return InkWell(
                        onLongPress:
                            () => showModalBottomSheet<void>(
                              context: context,
                              builder:
                                  (sheet) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final row in [false, true])
                                          ListTile(
                                            leading: const WandbIcon('copy'),
                                            title: Text(
                                              row ? 'Copy Row' : 'Copy Value',
                                            ),
                                            onTap: () async {
                                              await Clipboard.setData(
                                                ClipboardData(
                                                  text:
                                                      row
                                                          ? '${entry.key}: $value'
                                                          : value,
                                                ),
                                              );
                                              if (sheet.mounted) {
                                                Navigator.pop(sheet);
                                              }
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                            ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                value,
                                style: const TextStyle(
                                  fontFamily: 'Inconsolata',
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
