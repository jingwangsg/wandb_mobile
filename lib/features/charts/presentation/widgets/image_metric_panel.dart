import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/resource_refs.dart';
import '../../../../core/providers/mobile_preferences.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/widgets/mobile_controls.dart';
import '../../../../core/widgets/wandb_icon.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../runs/providers/runs_providers.dart';
import '../../models/image_frame.dart';
import '../../providers/image_history_provider.dart';
import '../../providers/panel_providers.dart';

final imageUrlsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, ({RunRef run, String paths})>((
      ref,
      request,
    ) async {
      final repository = ref.watch(runsRepositoryProvider);
      final urls = <String, String>{};
      String? cursor;
      do {
        final page = await repository.getRunFiles(
          entity: request.run.entity,
          project: request.run.project,
          runName: request.run.runName,
          fileNames: List<String>.from(jsonDecode(request.paths) as List),
          cursor: cursor,
          limit: 100,
        );
        for (final file in page.items) {
          final url = file.directUrl ?? file.url;
          if (url != null) urls[file.name] = url;
        }
        if (!page.hasNextPage) break;
        if (page.endCursor == null || page.endCursor == cursor)
          throw StateError('Image file pagination did not advance');
        cursor = page.endCursor;
      } while (true);
      return urls;
    });

class ImageMetricPanel extends ConsumerStatefulWidget {
  const ImageMetricPanel({
    super.key,
    required this.run,
    required this.metric,
    required this.lastStep,
  });
  final RunRef run;
  final String metric;
  final int lastStep;
  @override
  ConsumerState<ImageMetricPanel> createState() => _ImageMetricPanelState();
}

class _ImageMetricPanelState extends ConsumerState<ImageMetricPanel> {
  int? _selectedStep;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(ImageMetricPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run != widget.run || oldWidget.metric != widget.metric) {
      _selectedStep = null;
      _page = 0;
    }
    if (oldWidget.run != widget.run ||
        oldWidget.metric != widget.metric ||
        oldWidget.lastStep != widget.lastStep) {
      _loadHistory();
    }
  }

  void _loadHistory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(
              imageHistoryProvider((
                run: widget.run,
                metric: widget.metric,
              )).notifier,
            )
            .loadThrough(widget.lastStep);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(mobilePreferencesProvider);
    final starred = isMetricStarred(
      preferences,
      widget.run.projectRef,
      widget.metric,
    );
    final provider = imageHistoryProvider((
      run: widget.run,
      metric: widget.metric,
    ));
    ref.listen(provider.notifier, (_, _) => _loadHistory());
    final frames = ref.watch(provider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.metric,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: starred ? 'Unstar panel' : 'Star panel',
                  onPressed:
                      () => ref
                          .read(mobilePreferencesProvider.notifier)
                          .toggleMetric(
                            widget.run.projectRef.path,
                            widget.metric,
                          ),
                  icon: WandbIcon(
                    starred ? 'star_(filled)' : 'star',
                    size: 20,
                    color: starred ? WandbColors.star : null,
                  ),
                ),
              ],
            ),
            if (frames.hasError && frames.hasValue)
              TextButton(
                onPressed: _loadHistory,
                child: const Text('Unable to load more images · Retry'),
              ),
            frames.when(
              skipError: frames.hasValue,
              loading:
                  () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              error:
                  (error, _) => MobileEmptyState(
                    title: 'Unable to load images',
                    message: '$error',
                    icon: 'warning',
                    onRetry: _loadHistory,
                  ),
              data: (items) {
                if (items.isEmpty)
                  return const SizedBox(
                    height: 180,
                    child: Center(child: Text('No images logged')),
                  );
                final frameIndex =
                    _selectedStep == null
                        ? items.length - 1
                        : nearestImageFrame(items, _selectedStep!);
                final frame = items[frameIndex];
                final urlRequest = (
                  run: widget.run,
                  paths: jsonEncode(
                    frame.images.map((image) => image.path).toList(),
                  ),
                );
                final urls = ref.watch(imageUrlsProvider(urlRequest));
                final pageCount = (frame.images.length / 4).ceil();
                final viewportHeight = frame.images.length == 1 ? 210.0 : 240.0;
                return Column(
                  children: [
                    SizedBox(
                      height: viewportHeight,
                      child: urls.when(
                        loading:
                            () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                        error:
                            (error, _) => Center(
                              child: TextButton(
                                onPressed:
                                    () => ref.invalidate(
                                      imageUrlsProvider(urlRequest),
                                    ),
                                child: const Text('Retry images'),
                              ),
                            ),
                        data:
                            (paths) => PageView.builder(
                              key: ValueKey(frame.step),
                              itemCount: pageCount,
                              onPageChanged:
                                  (value) => setState(() => _page = value),
                              itemBuilder: (context, page) {
                                final images =
                                    frame.images
                                        .skip(page * 4)
                                        .take(4)
                                        .toList();
                                final columns = images.length == 1 ? 1 : 2;
                                final rows = (images.length / columns).ceil();
                                return GridView.builder(
                                  padding: EdgeInsets.zero,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: images.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        mainAxisSpacing: 4,
                                        crossAxisSpacing: 4,
                                        mainAxisExtent:
                                            (viewportHeight - 4 * (rows - 1)) /
                                            rows,
                                      ),
                                  itemBuilder:
                                      (context, index) => InkWell(
                                        onTap:
                                            () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder:
                                                    (_) => ImageGalleryScreen(
                                                      images: frame.images,
                                                      urls: paths,
                                                      initialIndex:
                                                          page * 4 + index,
                                                    ),
                                              ),
                                            ),
                                        child: RunImage(
                                          url: paths[images[index].path],
                                          caption: images[index].caption,
                                        ),
                                      ),
                                );
                              },
                            ),
                      ),
                    ),
                    if (pageCount > 1)
                      Text(
                        '${_page + 1} / $pageCount',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (items.length > 1)
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: frameIndex.toDouble(),
                              max: (items.length - 1).toDouble(),
                              divisions: items.length - 1,
                              onChanged:
                                  (value) => setState(() {
                                    _selectedStep = items[value.round()].step;
                                    _page = 0;
                                  }),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final controller = TextEditingController(
                                text: frame.step.toString(),
                              );
                              final step = await showDialog<int>(
                                context: context,
                                builder:
                                    (dialog) => AlertDialog(
                                      title: const Text('Jump to step'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Logged range: ${items.first.step} – ${items.last.step}',
                                          ),
                                          const Text(
                                            'Snaps to nearest logged step.',
                                          ),
                                          TextField(
                                            controller: controller,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Step',
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () => Navigator.pop(dialog),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            final value = int.tryParse(
                                              controller.text,
                                            );
                                            if (value != null)
                                              Navigator.pop(dialog, value);
                                          },
                                          child: const Text('Go to step'),
                                        ),
                                      ],
                                    ),
                              );
                              controller.dispose();
                              if (step != null && mounted)
                                setState(() {
                                  _selectedStep = step;
                                  _page = 0;
                                });
                            },
                            child: Text('Step ${frame.step}'),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Step ${frame.step}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class RunImage extends ConsumerWidget {
  const RunImage({super.key, required this.url, this.caption});
  final String? url;
  final String? caption;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || !['https', 'http'].contains(uri.scheme))
      return const Center(child: Text('Image unavailable'));
    final auth = ref.watch(authProvider);
    final api = Uri.parse(auth.baseUrl ?? defaultWandbBaseUrl);
    final headers =
        uri.origin == api.origin && auth.apiKey != null
            ? {
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('api:${auth.apiKey}'))}',
            }
            : null;
    return Column(
      children: [
        Expanded(
          child: Image.network(
            url!,
            headers: headers,
            fit: BoxFit.contain,
            semanticLabel: caption ?? 'Logged image',
            errorBuilder:
                (_, _, _) => const Center(child: Text('Image unavailable')),
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class ImageGalleryScreen extends StatefulWidget {
  const ImageGalleryScreen({
    super.key,
    required this.images,
    required this.urls,
    required this.initialIndex,
  });
  final List<LoggedImage> images;
  final Map<String, String> urls;
  final int initialIndex;
  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${_index + 1} / ${widget.images.length}')),
    body: PageView.builder(
      controller: _pages,
      itemCount: widget.images.length,
      onPageChanged: (value) => setState(() => _index = value),
      itemBuilder:
          (context, index) => InteractiveViewer(
            minScale: 1,
            maxScale: 10,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RunImage(
                url: widget.urls[widget.images[index].path],
                caption: widget.images[index].caption,
              ),
            ),
          ),
    ),
  );
}
