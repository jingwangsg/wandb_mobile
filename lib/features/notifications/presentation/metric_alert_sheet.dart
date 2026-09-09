import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/resource_refs.dart';
import '../../../core/widgets/mobile_controls.dart';
import '../../../core/widgets/wandb_icon.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/notifications_repository.dart';

class MetricAlertSheet extends ConsumerStatefulWidget {
  const MetricAlertSheet({super.key, required this.project, this.metric});
  final ProjectRef project;
  final String? metric;
  @override
  ConsumerState<MetricAlertSheet> createState() => _MetricAlertSheetState();
}

class _MetricAlertSheetState extends ConsumerState<MetricAlertSheet> {
  final _amount = TextEditingController();
  String _direction = 'ANY';
  String _basis = 'ABSOLUTE';
  bool _creating = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final personal =
        ref.watch(authProvider.select((auth) => auth.user?.entity)) ==
        widget.project.entity;
    final rules = ref.watch(notificationRulesProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.metric == null
                          ? 'Run failed alert'
                          : _creating
                          ? 'Create alert for ${widget.metric}'
                          : '${widget.metric} automation alerts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const WandbIcon('close'),
                  ),
                ],
              ),
              Text(
                widget.project.path,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              if (personal)
                const Text(
                  'Notifications cannot be created for personal projects. Please use a project associated with a team.',
                )
              else if (!_creating && widget.metric != null) ...[
                rules.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, _) => MobileEmptyState(
                        title: 'Unable to load alerts',
                        message: '$error',
                        icon: 'warning',
                        onRetry:
                            () => ref.invalidate(notificationRulesProvider),
                      ),
                  data:
                      (items) => Column(
                        children: [
                          for (final rule in items.where(
                            (rule) =>
                                rule.entity == widget.project.entity &&
                                rule.project == widget.project.project &&
                                rule.metric == widget.metric,
                          ))
                            ListTile(
                              title: Text(rule.name),
                              trailing: IconButton(
                                tooltip: 'Delete alert',
                                icon: const WandbIcon('delete'),
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(notificationsRepositoryProvider)
                                        .delete(rule.id);
                                    ref.invalidate(notificationRulesProvider);
                                  } catch (error) {
                                    if (mounted) {
                                      setState(() => _error = '$error');
                                    }
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                ),
                FilledButton(
                  onPressed: () => setState(() => _creating = true),
                  child: const Text('Add alert'),
                ),
              ] else ...[
                if (widget.metric != null) ...[
                  Text(
                    'Metric threshold',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _direction,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'ANY',
                        child: Text('Increases or decreases by at least'),
                      ),
                      DropdownMenuItem(
                        value: 'INCREASE',
                        child: Text('Increases by at least'),
                      ),
                      DropdownMenuItem(
                        value: 'DECREASE',
                        child: Text('Decreases by at least'),
                      ),
                    ],
                    onChanged:
                        _saving
                            ? null
                            : (value) => setState(() => _direction = value!),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ABSOLUTE', label: Text('Absolute')),
                      ButtonSegment(value: 'RELATIVE', label: Text('Relative')),
                    ],
                    selected: {_basis},
                    onSelectionChanged:
                        _saving
                            ? null
                            : (value) => setState(() => _basis = value.single),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amount,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ex. 10',
                      suffixText: _basis == 'RELATIVE' ? '%' : null,
                    ),
                  ),
                ] else
                  const Text(
                    'Receive a notification when a future run in this project fails or crashes.',
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed:
                      _saving
                          ? null
                          : () async {
                            final amount = double.tryParse(_amount.text.trim());
                            if (widget.metric != null &&
                                (amount == null ||
                                    !amount.isFinite ||
                                    amount <= 0)) {
                              setState(
                                () =>
                                    _error =
                                        'Change amount must be a valid positive number',
                              );
                              return;
                            }
                            setState(() {
                              _saving = true;
                              _error = null;
                            });
                            try {
                              await ref
                                  .read(notificationsRepositoryProvider)
                                  .create(
                                    project: widget.project,
                                    metric: widget.metric,
                                    direction: _direction,
                                    basis: _basis,
                                    amount: amount,
                                  );
                              ref.invalidate(notificationRulesProvider);
                              if (context.mounted) Navigator.pop(context);
                            } catch (error) {
                              final message =
                                  error is DioException
                                      ? error.response?.data
                                      : null;
                              if (mounted) {
                                setState(
                                  () =>
                                      _error =
                                          message is Map
                                              ? message['error']?.toString()
                                              : '$error',
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                  child: Text(_saving ? 'Creating…' : 'Create'),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
