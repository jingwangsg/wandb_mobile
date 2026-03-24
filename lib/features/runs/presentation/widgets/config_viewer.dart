import 'dart:convert';

import 'value_presentation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

/// Collapsible key-value tree for run config.
class ConfigViewer extends StatefulWidget {
  const ConfigViewer({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  State<ConfigViewer> createState() => _ConfigViewerState();
}

class _ConfigViewerState extends State<ConfigViewer> {
  bool _expanded = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEntries =
        widget.config.entries
            .where((entry) => !entry.key.startsWith('_'))
            .toList();
    final entries =
        _searchQuery.isEmpty
            ? allEntries
            : allEntries
                .where(
                  (e) =>
                      e.key.toLowerCase().contains(_searchQuery.toLowerCase()),
                )
                .toList();
    final countText =
        _searchQuery.isEmpty
            ? '${allEntries.length} keys'
            : '${entries.length}/${allEntries.length} keys';

    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Config',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(countText, style: const TextStyle(color: Colors.white38)),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Filter keys...',
                  hintStyle: const TextStyle(fontSize: 11),
                  prefixIcon: const Icon(Icons.search, size: 14),
                  suffixIcon:
                      _searchQuery.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                          : null,
                  isDense: true,
                  constraints: const BoxConstraints(minHeight: 34),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children:
                    entries
                        .map(
                          (entry) => _ConfigRow(
                            keyName: entry.key,
                            value: entry.value,
                          ),
                        )
                        .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfigRow extends StatefulWidget {
  const _ConfigRow({required this.keyName, required this.value});

  final String keyName;
  final dynamic value;

  @override
  State<_ConfigRow> createState() => _ConfigRowState();
}

class _ConfigRowState extends State<_ConfigRow> {
  bool _hovered = false;

  Future<void> _copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied value')),
    );
  }

  Future<void> _copyValue(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied value')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentation = ValuePresentation.fromValue(widget.value);
    final mouseConnected =
        RendererBinding.instance.mouseTracker.mouseIsConnected;
    final showExpandButton =
        presentation.isExpandable && (!mouseConnected || _hovered);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: () => _copyText(widget.keyName),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    widget.keyName,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: ValueKey('config-value-${widget.keyName}'),
                      onTap: () => _copyValue(presentation.fullText),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            presentation.inlineText,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (presentation.isExpandable)
                    IgnorePointer(
                      ignoring: !showExpandButton,
                      child: AnimatedOpacity(
                        opacity: showExpandButton ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'View full value',
                          icon: const Icon(Icons.open_in_full, size: 18),
                          onPressed:
                              () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  fullscreenDialog: true,
                                  builder:
                                      (_) => _ConfigValueViewerPage(
                                        title: widget.keyName,
                                        presentation: presentation,
                                      ),
                                ),
                              ),
                        ),
                      ),
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

class _ConfigValueViewerPage extends StatelessWidget {
  const _ConfigValueViewerPage({
    required this.title,
    required this.presentation,
  });

  final String title;
  final ValuePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final content =
        presentation.isJson
            ? SelectableText.rich(
              TextSpan(
                children: _JsonSyntaxHighlighter.highlight(
                  presentation.fullText,
                ),
              ),
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'JetBrains Mono',
                height: 1.4,
              ),
            )
            : SelectableText(
              presentation.fullText,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'JetBrains Mono',
                height: 1.4,
              ),
            );

    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width,
            ),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JsonSyntaxHighlighter {
  static const _defaultStyle = TextStyle(color: Colors.white);
  static const _keyStyle = TextStyle(color: Color(0xFF7DD3FC));
  static const _stringStyle = TextStyle(color: Color(0xFF86EFAC));
  static const _numberStyle = TextStyle(color: Color(0xFFFDE68A));
  static const _booleanStyle = TextStyle(color: Color(0xFFF9A8D4));
  static const _nullStyle = TextStyle(color: Color(0xFFC4B5FD));
  static const _punctuationStyle = TextStyle(color: Colors.white70);

  static List<TextSpan> highlight(String text) {
    final spans = <TextSpan>[];
    var index = 0;

    while (index < text.length) {
      final char = text[index];

      if (char == '"') {
        final start = index;
        index++;
        while (index < text.length) {
          final current = text[index];
          if (current == r'\') {
            index += 2;
            continue;
          }
          index++;
          if (current == '"') {
            break;
          }
        }
        final token = text.substring(start, index.clamp(start, text.length));
        var lookahead = index;
        while (lookahead < text.length && _isWhitespace(text[lookahead])) {
          lookahead++;
        }
        final isKey = lookahead < text.length && text[lookahead] == ':';
        spans.add(
          TextSpan(text: token, style: isKey ? _keyStyle : _stringStyle),
        );
        continue;
      }

      if (_isNumberStart(char)) {
        final start = index;
        index++;
        while (index < text.length && _isNumberPart(text[index])) {
          index++;
        }
        spans.add(
          TextSpan(text: text.substring(start, index), style: _numberStyle),
        );
        continue;
      }

      if (text.startsWith('true', index) || text.startsWith('false', index)) {
        final literal = text.startsWith('true', index) ? 'true' : 'false';
        spans.add(TextSpan(text: literal, style: _booleanStyle));
        index += literal.length;
        continue;
      }

      if (text.startsWith('null', index)) {
        spans.add(const TextSpan(text: 'null', style: _nullStyle));
        index += 4;
        continue;
      }

      if ('{}[]:,'.contains(char)) {
        spans.add(TextSpan(text: char, style: _punctuationStyle));
        index++;
        continue;
      }

      spans.add(TextSpan(text: char, style: _defaultStyle));
      index++;
    }

    return spans;
  }

  static bool _isWhitespace(String value) => value.trim().isEmpty;

  static bool _isNumberStart(String value) =>
      value == '-' || int.tryParse(value) != null;

  static bool _isNumberPart(String value) => '0123456789+-.eE'.contains(value);
}
