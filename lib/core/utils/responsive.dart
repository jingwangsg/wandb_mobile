import 'package:flutter/widgets.dart';

/// Breakpoints for responsive layout.
const kCompactWidth = 600.0; // Narrow phones
const kMediumWidth = 900.0;  // Wide phones / small tablets

bool isCompact(double width) => width < kCompactWidth;
bool isMedium(double width) => width >= kCompactWidth && width < kMediumWidth;
bool isExpanded(double width) => width >= kMediumWidth;

/// Number of grid columns based on available width.
int adaptiveColumns(double width) {
  if (width < kCompactWidth) return 1;
  if (width < kMediumWidth) return 2;
  return 3;
}

/// Horizontal padding that scales with width.
double adaptivePadding(double width) {
  if (width < kCompactWidth) return 16.0;
  if (width < kMediumWidth) return 24.0;
  return 32.0;
}

/// Master-detail split ratio for wide screens.
/// Returns the flex value for the master (list) panel.
int masterFlex(double width) => width >= kMediumWidth ? 2 : 3;

/// Returns the flex value for the detail panel.
int detailFlex(double width) => width >= kMediumWidth ? 5 : 4;

/// A convenience widget that builds different layouts based on width.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
  });

  /// Layout for narrow phones (<600dp).
  final Widget compact;

  /// Layout for wide phones / small tablets (600-900dp).
  /// Falls back to [compact] if null.
  final Widget Function(BuildContext, double width)? medium;

  /// Layout for large tablets / desktop (>900dp).
  /// Falls back to [medium] then [compact] if null.
  final Widget Function(BuildContext, double width)? expanded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (isExpanded(w) && expanded != null) {
          return expanded!(context, w);
        }
        if (!isCompact(w) && medium != null) {
          return medium!(context, w);
        }
        return compact;
      },
    );
  }
}
