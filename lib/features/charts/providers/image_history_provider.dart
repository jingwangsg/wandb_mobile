import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/resource_refs.dart';
import '../../runs/data/runs_repository.dart';
import '../../runs/providers/runs_providers.dart';
import '../models/image_frame.dart';

class ImageHistoryLoader extends StateNotifier<AsyncValue<List<ImageFrame>>> {
  ImageHistoryLoader(this._repository, this._run, this._metric)
    : super(const AsyncValue.loading());

  final RunsRepository _repository;
  final RunRef _run;
  final String _metric;
  int _nextStep = 0;
  int _lastStep = -1;
  Completer<void>? _loading;

  Future<void> loadThrough(int lastStep) async {
    if (!mounted) return;
    _lastStep = math.max(_lastStep, lastStep);
    if (_loading != null) return _loading!.future;
    if (_nextStep > _lastStep) {
      if (state.isLoading) state = const AsyncValue.data([]);
      return;
    }
    final completion = _loading = Completer<void>();
    state = const AsyncValue<List<ImageFrame>>.loading().copyWithPrevious(
      state,
    );
    try {
      while (mounted && _nextStep <= _lastStep) {
        final end = math.min(_nextStep + 1000, _lastStep + 1);
        final rows = await _repository.getHistoryPage(
          entity: _run.entity,
          project: _run.project,
          runName: _run.runName,
          minStep: _nextStep,
          maxStep: end,
          pageSize: 1000,
          keys: [_metric],
        );
        if (!mounted) return;
        final frames = {
          for (final frame in state.valueOrNull ?? const <ImageFrame>[])
            frame.step: frame,
        };
        for (final row in rows) {
          final frame = imageFrameFromRow(row, _metric);
          if (frame != null) frames[frame.step] = frame;
        }
        _nextStep = end;
        state = AsyncValue.data(
          frames.values.toList()..sort((a, b) => a.step.compareTo(b.step)),
        );
      }
    } catch (error, stack) {
      if (mounted) {
        state = AsyncValue<List<ImageFrame>>.error(
          error,
          stack,
        ).copyWithPrevious(state);
      }
    } finally {
      _loading = null;
      completion.complete();
    }
  }
}

final imageHistoryProvider = StateNotifierProvider.autoDispose.family<
  ImageHistoryLoader,
  AsyncValue<List<ImageFrame>>,
  ({RunRef run, String metric})
>(
  (ref, request) => ImageHistoryLoader(
    ref.watch(runsRepositoryProvider),
    request.run,
    request.metric,
  ),
);
