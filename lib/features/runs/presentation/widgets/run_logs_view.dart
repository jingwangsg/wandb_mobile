import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/resource_refs.dart';
import '../../../../core/models/run_log.dart';
import '../../../../core/widgets/mobile_controls.dart';
import '../../../../core/widgets/wandb_icon.dart';
import '../../providers/runs_providers.dart';

class RunLogsView extends ConsumerStatefulWidget {
  const RunLogsView({
    super.key,
    required this.run,
    required this.active,
    required this.visible,
  });
  final RunRef run;
  final bool active;
  final bool visible;

  @override
  ConsumerState<RunLogsView> createState() => _RunLogsViewState();
}

class _RunLogsViewState extends ConsumerState<RunLogsView> {
  final _scroll = ScrollController();
  final _lines = <RunLogLine>[];
  Timer? _poll;
  String _search = '';
  bool _wrap = true;
  bool _busy = false;
  bool _pendingRefresh = false;
  bool _hasOlder = false;
  String? _before;
  String? _after;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.active &&
          widget.visible &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(RunLogsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.visible && widget.visible) ||
        (oldWidget.active && !widget.active))
      _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool older = false}) async {
    if (_busy) {
      if (!older) _pendingRefresh = true;
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final follow =
        _lines.isEmpty ||
        (_scroll.hasClients && _scroll.position.extentAfter < 60);
    final previousMax =
        _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final previousOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    try {
      do {
        final previousCursor = _after;
        final page = await ref
            .read(runsRepositoryProvider)
            .getLogs(
              entity: widget.run.entity,
              project: widget.run.project,
              runName: widget.run.runName,
              before: older ? _before : null,
              after: older ? null : _after,
              limit: older ? 2000 : 10000,
            );
        if (!mounted) return;
        final known = _lines.map((line) => line.cursor).toSet();
        final incoming = page.lines.where((line) => known.add(line.cursor));
        setState(() {
          if (older) {
            _lines.insertAll(0, incoming);
          } else {
            _lines.addAll(incoming);
            _after = page.endCursor ?? _after;
          }
          if (older || _before == null) {
            _before = page.startCursor ?? _before;
            _hasOlder = page.hasPreviousPage;
          }
        });
        if (older || !page.hasNextPage || !widget.visible) break;
        if (_after == null || _after == previousCursor)
          throw StateError('Log pagination did not advance');
      } while (mounted);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        if (older) {
          _scroll.jumpTo(
            (previousOffset + _scroll.position.maxScrollExtent - previousMax)
                .clamp(0, _scroll.position.maxScrollExtent),
          );
        } else if (follow) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_pendingRefresh) {
          _pendingRefresh = false;
          _load();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines =
        _search.isEmpty
            ? _lines
            : _lines
                .where(
                  (line) =>
                      line.text.toLowerCase().contains(_search.toLowerCase()),
                )
                .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    hintText: 'Search logs',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Wrap Lines',
                isSelected: _wrap,
                onPressed: () => setState(() => _wrap = !_wrap),
                icon: const WandbIcon('wrap'),
              ),
              IconButton(
                tooltip: 'Download log file',
                onPressed:
                    widget.active
                        ? null
                        : () async {
                          try {
                            final url = await ref
                                .read(runsRepositoryProvider)
                                .getConsoleLog(
                                  entity: widget.run.entity,
                                  project: widget.run.project,
                                  runName: widget.run.runName,
                                );
                            if (url == null ||
                                !await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                )) {
                              throw StateError('Log download is unavailable');
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                icon: const WandbIcon('download'),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null && _lines.isNotEmpty)
          ListTile(
            title: Text('Could not refresh logs: $_error'),
            trailing: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        if (_hasOlder)
          TextButton(
            onPressed: _busy ? null : () => _load(older: true),
            child: const Text('Load older logs'),
          ),
        Expanded(
          child:
              _error != null && _lines.isEmpty
                  ? MobileEmptyState(
                    title: 'Unable to load logs',
                    message: '$_error',
                    onRetry: _load,
                    icon: 'warning',
                  )
                  : _lines.isEmpty && !_busy
                  ? const MobileEmptyState(
                    title: 'No logs yet',
                    icon: 'list_bullets_(alt)',
                  )
                  : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      final line = SelectableText.rich(
                        TextSpan(
                          children: ansiLogSpans(
                            lines[index].text,
                            Theme.of(context).colorScheme,
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Inconsolata',
                          fontSize: 13,
                          height: 1.4,
                        ),
                      );
                      return _wrap
                          ? line
                          : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: line,
                          );
                    },
                  ),
        ),
      ],
    );
  }
}

List<TextSpan> ansiLogSpans(String value, ColorScheme colors) {
  final spans = <TextSpan>[];
  final escapes = RegExp(r'\x1B\[([0-9;]*)m');
  Color? foreground;
  Color? background;
  FontWeight? weight;
  FontStyle? fontStyle;
  bool underline = false;
  bool strike = false;
  bool inverse = false;
  var offset = 0;
  TextStyle currentStyle() => TextStyle(
    color: inverse ? background ?? colors.surface : foreground,
    backgroundColor: inverse ? foreground ?? colors.onSurface : background,
    fontWeight: weight,
    fontStyle: fontStyle,
    decoration: TextDecoration.combine([
      if (underline) TextDecoration.underline,
      if (strike) TextDecoration.lineThrough,
    ]),
  );
  for (final match in escapes.allMatches(value)) {
    if (match.start > offset)
      spans.add(
        TextSpan(
          text: value.substring(offset, match.start),
          style: currentStyle(),
        ),
      );
    final codes =
        match
            .group(1)!
            .split(';')
            .map((code) => int.tryParse(code) ?? 0)
            .toList();
    for (var index = 0; index < codes.length; index++) {
      final code = codes[index];
      if (code == 38 || code == 48) {
        Color? color;
        if (index + 2 < codes.length && codes[index + 1] == 5) {
          color = ansiPaletteColor(codes[index + 2], colors);
          index += 2;
        } else if (index + 4 < codes.length && codes[index + 1] == 2) {
          final channels = codes.sublist(index + 2, index + 5);
          if (channels.every((channel) => channel >= 0 && channel <= 255)) {
            color = Color.fromARGB(255, channels[0], channels[1], channels[2]);
          }
          index += 4;
        }
        if (color != null) {
          if (code == 38) {
            foreground = color;
          } else {
            background = color;
          }
        }
        continue;
      }
      switch (code) {
        case 0:
          foreground = null;
          background = null;
          weight = null;
          fontStyle = null;
          underline = false;
          strike = false;
          inverse = false;
        case 1:
          weight = FontWeight.bold;
        case 3:
          fontStyle = FontStyle.italic;
        case 4:
          underline = true;
        case 7:
          inverse = true;
        case 9:
          strike = true;
        case 22:
          weight = null;
        case 23:
          fontStyle = null;
        case 24:
          underline = false;
        case 27:
          inverse = false;
        case 29:
          strike = false;
        case 39:
          foreground = null;
        case 49:
          background = null;
        default:
          if (code >= 30 && code <= 37)
            foreground = ansiPaletteColor(code - 30, colors);
          if (code >= 90 && code <= 97)
            foreground = ansiPaletteColor(code - 90 + 8, colors);
          if (code >= 40 && code <= 47)
            background = ansiPaletteColor(code - 40, colors);
          if (code >= 100 && code <= 107)
            background = ansiPaletteColor(code - 100 + 8, colors);
      }
    }
    offset = match.end;
  }
  if (offset < value.length)
    spans.add(TextSpan(text: value.substring(offset), style: currentStyle()));
  return spans;
}

Color? ansiPaletteColor(int index, ColorScheme colors) {
  if (index < 0 || index > 255) return null;
  final base = [
    colors.onSurface,
    const Color(0xFFD34B52),
    const Color(0xFF3B9B64),
    const Color(0xFFBC8A20),
    const Color(0xFF4D86CE),
    const Color(0xFFB36AD1),
    const Color(0xFF3BA6AF),
    colors.onSurface,
    const Color(0xFF808080),
    const Color(0xFFFF5555),
    const Color(0xFF55FF55),
    const Color(0xFFFFFF55),
    const Color(0xFF5555FF),
    const Color(0xFFFF55FF),
    const Color(0xFF55FFFF),
    const Color(0xFFFFFFFF),
  ];
  if (index < 16) return base[index];
  if (index >= 232) {
    final gray = 8 + (index - 232) * 10;
    return Color.fromARGB(255, gray, gray, gray);
  }
  const levels = [0, 95, 135, 175, 215, 255];
  final cube = index - 16;
  return Color.fromARGB(
    255,
    levels[cube ~/ 36],
    levels[(cube ~/ 6) % 6],
    levels[cube % 6],
  );
}
