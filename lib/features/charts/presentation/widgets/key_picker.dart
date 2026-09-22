import 'package:flutter/material.dart';

import '../../../../core/widgets/wandb_icon.dart';

/// Bottom sheet with a search field over a list of keys, as in the web's
/// X-axis and metric menus.
class KeyPicker extends StatefulWidget {
  const KeyPicker({
    super.key,
    required this.title,
    required this.options,
    required this.onSelected,
    this.selected,
    this.labelOf,
  });
  final String title;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  /// Display text for an option; defaults to the key itself.
  final String Function(String key)? labelOf;

  @override
  State<KeyPicker> createState() => _KeyPickerState();
}

class _KeyPickerState extends State<KeyPicker> {
  String _query = '';

  String _label(String key) => widget.labelOf?.call(key) ?? key;

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final matches = [
      for (final key in widget.options)
        if (_label(key).toLowerCase().contains(query) ||
            key.toLowerCase().contains(query))
          key,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const WandbIcon('close'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search ${widget.title.toLowerCase()}',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: WandbIcon('search'),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final key = matches[index];
                  return ListTile(
                    title: Text(
                      _label(key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing:
                        key == widget.selected
                            ? const WandbIcon('checkmark', size: 18)
                            : null,
                    onTap: () {
                      widget.onSelected(key);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
