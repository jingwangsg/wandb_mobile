import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/run.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/responsive.dart';
import 'widgets/config_viewer.dart';
import 'widgets/metrics_chart_panel.dart';
import 'widgets/summary_viewer.dart';

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

  /// When true, displayed inside master-detail split (no own Scaffold/AppBar).
  final bool embedded;

  @override
  ConsumerState<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends ConsumerState<RunDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    if (run == null) {
      final body = const Center(child: Text('Run data not available'));
      if (widget.embedded) return body;
      return Scaffold(
        appBar: AppBar(title: Text(widget.runName)),
        body: body,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // When embedded in master-detail, check if we have enough width for side-by-side
        final wideDetail =
            widget.embedded && constraints.maxWidth >= 500 ||
            !widget.embedded && !isCompact(constraints.maxWidth);

        if (wideDetail) {
          return _buildWideLayout(run, constraints.maxWidth);
        }
        return _buildNarrowLayout(run);
      },
    );
  }

  /// Narrow: traditional tab-based layout.
  Widget _buildNarrowLayout(WandbRun run) {
    final content = Column(
      children: [
        // Header info when embedded
        if (widget.embedded) _EmbeddedHeader(run: run),
        // Tab bar
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Metrics'),
            Tab(text: 'System'),
            Tab(text: 'Files'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _OverviewTab(run: run),
              MetricsChartPanel(
                entity: widget.entity,
                project: widget.project,
                runName: run.name,
                run: run,
              ),
              _PlaceholderTab(icon: Icons.memory, label: 'System Metrics'),
              _PlaceholderTab(icon: Icons.folder_open, label: 'Run Files'),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: _AppBarTitle(run: run),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Metrics'),
            Tab(text: 'System'),
            Tab(text: 'Files'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(run: run),
          MetricsChartPanel(
            entity: widget.entity,
            project: widget.project,
            runName: run.name,
            run: run,
          ),
          _PlaceholderTab(icon: Icons.memory, label: 'System Metrics'),
          _PlaceholderTab(icon: Icons.folder_open, label: 'Run Files'),
        ],
      ),
    );
  }

  /// Wide: Overview on left, Metrics on right — no tabs needed.
  Widget _buildWideLayout(WandbRun run, double width) {
    final body = Column(
      children: [
        if (widget.embedded) _EmbeddedHeader(run: run),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Overview (scrollable)
              SizedBox(
                width: width * 0.42,
                child: _OverviewTab(run: run),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              // Right: Metrics chart
              Expanded(
                child: MetricsChartPanel(
                  entity: widget.entity,
                  project: widget.project,
                  runName: run.name,
                  run: run,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: _AppBarTitle(run: run)),
      body: body,
    );
  }
}

/// Compact header shown when detail is embedded in master-detail split.
class _EmbeddedHeader extends StatelessWidget {
  const _EmbeddedHeader({required this.run});
  final WandbRun run;

  @override
  Widget build(BuildContext context) {
    final stateColor = WandbColors.forRunState(run.state.name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: stateColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              run.displayName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${run.state.name} • ${formatRelativeTime(run.createdAt)}',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.run});
  final WandbRun run;

  @override
  Widget build(BuildContext context) {
    final stateColor = WandbColors.forRunState(run.state.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(run.displayName, style: const TextStyle(fontSize: 16)),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: stateColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${run.state.name} • ${formatRelativeTime(run.createdAt)}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white24),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.run});
  final WandbRun run;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Run Info',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _InfoRow('Name', run.displayName),
                _InfoRow('ID', run.name),
                if (run.group != null) _InfoRow('Group', run.group!),
                if (run.jobType != null) _InfoRow('Job Type', run.jobType!),
                if (run.userName != null) _InfoRow('User', run.userName!),
                if (run.duration != null)
                  _InfoRow('Duration', formatDuration(run.duration!)),
                if (run.tags.isNotEmpty) _InfoRow('Tags', run.tags.join(', ')),
                if (run.notes != null && run.notes!.isNotEmpty)
                  _InfoRow('Notes', run.notes!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (run.summaryMetrics.isNotEmpty)
          SummaryViewer(metrics: run.summaryMetrics),
        const SizedBox(height: 8),
        if (run.config.isNotEmpty) ConfigViewer(config: run.flatConfig),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
