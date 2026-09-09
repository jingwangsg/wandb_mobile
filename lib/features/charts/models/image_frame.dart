class LoggedImage {
  const LoggedImage({required this.path, this.caption});
  final String path;
  final String? caption;
}

class ImageFrame {
  const ImageFrame({required this.step, required this.images});
  final int step;
  final List<LoggedImage> images;
}

ImageFrame? imageFrameFromRow(Map<String, dynamic> row, String metric) {
  final value = row[metric];
  final step = row['_step'];
  if (step is! num || value is! Map) return null;
  final images = <LoggedImage>[];
  if (value['path'] is String &&
      (value['_type'] as String? ?? '').contains('image')) {
    images.add(
      LoggedImage(
        path: value['path'] as String,
        caption: value['caption'] as String?,
      ),
    );
  }
  final filenames = value['filenames'] as List?;
  final captions = value['captions'] as List? ?? [];
  if (filenames != null) {
    for (final (index, path) in filenames.indexed) {
      if (path is String)
        images.add(
          LoggedImage(
            path: path,
            caption:
                index < captions.length ? captions[index]?.toString() : null,
          ),
        );
    }
  }
  for (final image in value['images'] as List? ?? []) {
    if (image is Map && image['path'] is String)
      images.add(
        LoggedImage(
          path: image['path'] as String,
          caption: image['caption']?.toString(),
        ),
      );
  }
  return images.isEmpty ? null : ImageFrame(step: step.toInt(), images: images);
}

int nearestImageFrame(List<ImageFrame> frames, int step) {
  var nearest = 0;
  for (var index = 1; index < frames.length; index++) {
    if ((frames[index].step - step).abs() < (frames[nearest].step - step).abs())
      nearest = index;
  }
  return nearest;
}
