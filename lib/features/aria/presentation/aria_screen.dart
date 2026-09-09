import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/wandb_icon.dart';
import '../../../core/models/resource_refs.dart';
import '../data/aria_repository.dart';

class AriaScreen extends ConsumerStatefulWidget {
  const AriaScreen({super.key});
  @override
  ConsumerState<AriaScreen> createState() => _AriaScreenState();
}

class _AriaScreenState extends ConsumerState<AriaScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <AriaTurn>[];
  final _references = <Map<String, dynamic>>[];
  Timer? _poll;
  CancelToken? _request;
  bool _busy = false;
  bool _refreshing = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          _turns.lastOrNull?.active == true &&
          !_refreshing &&
          TickerMode.valuesOf(context).enabled &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refreshTurn();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _request?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshTurn() async {
    if (_turns.isEmpty || _refreshing) return;
    final generation = _generation;
    final id = _turns.last.id;
    _refreshing = true;
    _request = CancelToken();
    try {
      final turn = await ref
          .read(ariaRepositoryProvider)
          .getTurn(id, cancelToken: _request);
      if (mounted && generation == _generation) {
        setState(() {
          _turns[_turns.indexWhere((item) => item.id == id)] = turn;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          !(error is DioException && CancelToken.isCancel(error)))
        setState(() => _error = ariaErrorMessage(error));
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _send([String? text]) async {
    final prompt = (text ?? _input.text).trim();
    if (prompt.isEmpty || _busy || _turns.lastOrNull?.active == true) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final turn = await ref
          .read(ariaRepositoryProvider)
          .createTurn(
            prompt,
            parentId: _turns.lastOrNull?.id,
            project: ref.read(ariaProjectContextProvider),
            references: List.of(_references),
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _turns.add(turn);
        _references.clear();
        _input.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients)
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
      await _refreshTurn();
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() => _error = ariaErrorMessage(error));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final browsedProject = ref.watch(ariaProjectContextProvider);
    final firstTurn = _turns.firstOrNull;
    final project =
        firstTurn?.data['wandb_entity'] is String &&
                firstTurn?.data['wandb_project'] is String
            ? ProjectRef(
              entity: firstTurn!.data['wandb_entity'] as String,
              project: firstTurn.data['wandb_project'] as String,
            )
            : browsedProject;
    final active = _turns.lastOrNull?.active == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARIA'),
        leading: IconButton(
          tooltip: 'Chats',
          icon: const WandbIcon('history'),
          onPressed: () async {
            final id = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const AriaHistoryScreen()),
            );
            if (id == null || !mounted) return;
            final generation = ++_generation;
            _request?.cancel();
            setState(() {
              _busy = true;
              _error = null;
            });
            try {
              final turns = await ref.read(ariaRepositoryProvider).turns(id);
              if (mounted && generation == _generation)
                setState(() {
                  _turns
                    ..clear()
                    ..addAll(turns);
                });
            } catch (error) {
              if (mounted && generation == _generation)
                setState(() => _error = ariaErrorMessage(error));
            } finally {
              if (mounted && generation == _generation)
                setState(() => _busy = false);
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const WandbIcon('compose'),
            onPressed:
                _busy
                    ? null
                    : () {
                      _generation++;
                      _request?.cancel();
                      setState(() {
                        _turns.clear();
                        _references.clear();
                        _error = null;
                      });
                    },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (project != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const WandbIcon('folder_project', size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        project.path,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child:
                  _turns.isEmpty
                      ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              const WandbIcon('lightboard', size: 56),
                              const SizedBox(height: 16),
                              Text(
                                'How can I help?',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 24),
                              for (final prompt in [
                                'How are my active runs doing?',
                                'Did any runs crash or fail recently? Figure out why.',
                                'What can you do?',
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Card(
                                    child: ListTile(
                                      title: Text(prompt),
                                      trailing: const WandbIcon(
                                        'chevron_(next)',
                                        size: 16,
                                      ),
                                      onTap: _busy ? null : () => _send(prompt),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                      : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _turns.length,
                        itemBuilder:
                            (context, index) => AriaTurnView(
                              turn: _turns[index],
                              onAnswer: _send,
                            ),
                      ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          active
                              ? _refreshTurn
                              : () => setState(() => _error = null),
                      child: Text(active ? 'Retry' : 'Dismiss'),
                    ),
                  ],
                ),
              ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_references.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  children: [
                    for (final reference in _references)
                      InputChip(
                        label: Text(
                          '${reference['project_name']}${reference['run_name'] == null ? '' : '/${reference['run_name']}'}',
                        ),
                        onDeleted:
                            () => setState(() => _references.remove(reference)),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Reference project or run',
                    icon: const WandbIcon('add_(new)'),
                    onPressed: () async {
                      final controller = TextEditingController(
                        text: project?.path ?? '',
                      );
                      final value = await showDialog<String>(
                        context: context,
                        builder:
                            (dialog) => AlertDialog(
                              title: const Text('Reference project or run'),
                              content: TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  hintText: 'entity/project[/run]',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed:
                                      () => Navigator.pop(
                                        dialog,
                                        controller.text.trim(),
                                      ),
                                  child: const Text('Add'),
                                ),
                              ],
                            ),
                      );
                      controller.dispose();
                      if (value == null || !mounted) return;
                      final parts = value.split('/');
                      if ((parts.length != 2 && parts.length != 3) ||
                          parts.any((part) => part.isEmpty)) {
                        setState(
                          () =>
                              _error =
                                  'Use entity/project or entity/project/run',
                        );
                        return;
                      }
                      setState(
                        () => _references.add({
                          'type':
                              parts.length == 2 ? 'wandb_project' : 'wandb_run',
                          'entity_name': parts[0],
                          'project_name': parts[1],
                          if (parts.length == 3) 'run_name': parts[2],
                        }),
                      );
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(hintText: 'Ask ARIA'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    tooltip: active ? 'Stop response' : 'Send',
                    icon: WandbIcon(active ? 'stop_(solid)' : 'up'),
                    onPressed:
                        _busy
                            ? null
                            : active
                            ? () async {
                              try {
                                await ref
                                    .read(ariaRepositoryProvider)
                                    .cancel(_turns.last.id);
                                await _refreshTurn();
                              } catch (error) {
                                if (mounted)
                                  setState(
                                    () => _error = ariaErrorMessage(error),
                                  );
                              }
                            }
                            : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AriaTurnView extends ConsumerWidget {
  const AriaTurnView({super.key, required this.turn, required this.onAnswer});
  final AriaTurn turn;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responses = {
      for (final tool in turn.tools.where((tool) => tool['type'] == 'response'))
        tool['call_id']: tool,
    };
    final answer = StringBuffer();
    final messageWidgets = <Widget>[];
    for (final record in turn.messages) {
      final raw = record['message'] as Map? ?? record;
      final role = record['role'] ?? raw['role'];
      if (role == 'user' || role == 'tool' || role == 'system') continue;
      final content = record['content'] ?? raw['content'];
      final text =
          content is String
              ? content
              : content is List
              ? content
                  .map(
                    (part) =>
                        part is Map ? part['text'] ?? '' : part.toString(),
                  )
                  .join('\n')
              : '';
      final reasoning = raw['reasoning_content'] ?? raw['reasoning'];
      if (reasoning != null)
        messageWidgets.add(
          ExpansionTile(
            title: const Text('Thinking'),
            leading: const WandbIcon('reasoning'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(reasoning.toString()),
              ),
            ],
          ),
        );
      if (text.isNotEmpty) {
        answer.writeln(text);
        messageWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MarkdownBody(
              data: text,
              selectable: true,
              onTapLink: (_, href, _) {
                final uri = Uri.tryParse(href ?? '');
                if (uri != null && ['https', 'http'].contains(uri.scheme))
                  launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(left: 36, bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: SelectableText(turn.prompt),
            ),
          ),
          ...messageWidgets,
          for (final tool in turn.tools.where(
            (tool) => tool['type'] == 'invocation',
          ))
            Card(
              child: ExpansionTile(
                leading: const WandbIcon('list_bullets_(alt)', size: 20),
                title: Text(tool['name']?.toString() ?? 'Tool'),
                subtitle: Text(
                  responses[tool['call_id']] == null
                      ? turn.active
                          ? 'Running'
                          : 'Cancelled'
                      : responses[tool['call_id']]!['is_error'] == true
                      ? 'Error'
                      : 'Completed',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Args'),
                        SelectableText(
                          const JsonEncoder.withIndent(
                            '  ',
                          ).convert(tool['arguments']),
                          style: const TextStyle(
                            fontFamily: 'Inconsolata',
                            fontSize: 13,
                          ),
                        ),
                        if (responses[tool['call_id']] != null) ...[
                          const SizedBox(height: 12),
                          const Text('Output'),
                          SelectableText(
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(responses[tool['call_id']]!['output']),
                            style: const TextStyle(
                              fontFamily: 'Inconsolata',
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (turn.active)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Thinking…'),
                ],
              ),
            ),
          if (turn.state == 'errored' || turn.state == 'expired')
            const Text(
              'ARIA could not complete this response. You can send a follow-up to retry.',
            ),
          if (turn.state == 'cancelled') const Text('Response stopped'),
          if (!turn.active && turn.questions.isNotEmpty)
            OutlinedButton(
              onPressed: () async {
                final controllers = [
                  for (final _ in turn.questions) TextEditingController(),
                ];
                final response = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder:
                      (sheet) => StatefulBuilder(
                        builder:
                            (context, update) => Padding(
                              padding: EdgeInsets.fromLTRB(
                                20,
                                0,
                                20,
                                24 + MediaQuery.viewInsetsOf(context).bottom,
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final (index, question)
                                        in turn.questions.indexed) ...[
                                      Text(
                                        question['question'] as String,
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                      ),
                                      for (final option
                                          in question['options'] as List)
                                        ListTile(
                                          title: Text(option.toString()),
                                          leading: Icon(
                                            controllers[index].text == option
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_unchecked,
                                          ),
                                          onTap:
                                              () => update(
                                                () =>
                                                    controllers[index].text =
                                                        option.toString(),
                                              ),
                                        ),
                                      TextField(
                                        controller: controllers[index],
                                        decoration: const InputDecoration(
                                          hintText: 'Type your answer…',
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    FilledButton(
                                      onPressed: () {
                                        if (controllers.any(
                                          (c) => c.text.trim().isEmpty,
                                        ))
                                          return;
                                        Navigator.pop(
                                          sheet,
                                          [
                                            for (final (index, question)
                                                in turn.questions.indexed)
                                              '${question['question']}: ${controllers[index].text}',
                                          ].join('\n'),
                                        );
                                      },
                                      child: const Text('Submit and continue'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ),
                );
                for (final controller in controllers) {
                  controller.dispose();
                }
                if (response != null) onAnswer(response);
              },
              child: const Text('Answer questions'),
            ),
          if (!turn.active)
            Row(
              children: [
                IconButton(
                  tooltip: 'Copy response',
                  onPressed:
                      () => Clipboard.setData(
                        ClipboardData(text: answer.toString()),
                      ),
                  icon: const WandbIcon('copy', size: 18),
                ),
                for (final positive in [true, false])
                  IconButton(
                    tooltip: positive ? 'Helpful' : 'Not helpful',
                    icon: WandbIcon(
                      positive ? 'thumbs_up' : 'thumbs_down',
                      size: 18,
                    ),
                    onPressed: () async {
                      final controller = TextEditingController();
                      final reason = await showDialog<String>(
                        context: context,
                        builder:
                            (dialog) => AlertDialog(
                              title: Text(
                                positive
                                    ? 'What went well?'
                                    : 'What went wrong?',
                              ),
                              content: TextField(
                                controller: controller,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText: 'Share details (optional)',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed:
                                      () => Navigator.pop(
                                        dialog,
                                        controller.text,
                                      ),
                                  child: const Text('Send'),
                                ),
                              ],
                            ),
                      );
                      controller.dispose();
                      if (reason == null) return;
                      try {
                        await ref
                            .read(ariaRepositoryProvider)
                            .feedback(turn.id, positive, reason);
                      } catch (error) {
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ariaErrorMessage(error))),
                          );
                      }
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class AriaHistoryScreen extends ConsumerStatefulWidget {
  const AriaHistoryScreen({super.key});
  @override
  ConsumerState<AriaHistoryScreen> createState() => _AriaHistoryScreenState();
}

class _AriaHistoryScreenState extends ConsumerState<AriaHistoryScreen> {
  final _threads = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(ariaRepositoryProvider)
          .threads(offset: _threads.length);
      if (mounted)
        setState(() {
          _threads.addAll(page);
          _hasMore = page.length == 30;
        });
    } catch (error) {
      if (mounted) setState(() => _error = ariaErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chats')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          ListTile(
            title: Text(_error!),
            trailing: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        for (final thread in _threads)
          Card(
            child: ListTile(
              title: Text(
                (thread['title'] as String).isEmpty
                    ? thread['prompt_preview'] as String? ?? 'Untitled chat'
                    : thread['title'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${thread['wandb_entity']}/${thread['wandb_project']}',
              ),
              onTap: () => Navigator.pop(context, thread['id'] as String),
              onLongPress: () async {
                final action = await showModalBottomSheet<String>(
                  context: context,
                  builder:
                      (sheet) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                thread['prompt_preview'] as String? ??
                                    thread['title'] as String,
                              ),
                            ),
                            for (final action in ['Rename', 'Delete'])
                              ListTile(
                                title: Text(action),
                                onTap: () => Navigator.pop(sheet, action),
                              ),
                          ],
                        ),
                      ),
                );
                if (action == null || !context.mounted) return;
                final controller = TextEditingController(
                  text: thread['title'] as String,
                );
                final result = await showDialog<String>(
                  context: context,
                  builder:
                      (dialog) => AlertDialog(
                        title: Text(
                          action == 'Rename' ? 'Rename chat' : 'Delete chat?',
                        ),
                        content:
                            action == 'Rename'
                                ? TextField(
                                  controller: controller,
                                  maxLength: 255,
                                  decoration: const InputDecoration(
                                    hintText: 'Chat name',
                                  ),
                                )
                                : const Text(
                                  'This conversation will be removed from your chats.',
                                ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed:
                                () => Navigator.pop(dialog, controller.text),
                            child: Text(action),
                          ),
                        ],
                      ),
                );
                controller.dispose();
                if (result == null) return;
                try {
                  final repository = ref.read(ariaRepositoryProvider);
                  if (action == 'Rename') {
                    await repository.rename(thread['id'] as String, result);
                  } else {
                    await repository.archive(thread['id'] as String);
                  }
                  if (mounted) {
                    setState(() {
                      if (action == 'Rename') {
                        thread['title'] = result;
                      } else {
                        _threads.remove(thread);
                      }
                    });
                  }
                } catch (error) {
                  if (mounted) setState(() => _error = ariaErrorMessage(error));
                }
              },
            ),
          ),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_hasMore && !_loading)
          TextButton(onPressed: _load, child: const Text('Load more')),
        if (_threads.isEmpty && !_loading && _error == null)
          const Center(child: Text('No chats yet')),
      ],
    ),
  );
}
