import 'package:flutter/material.dart';

class WandbColors {
  WandbColors._();

  // Brand
  static const yellow = Color(0xFFFFBE00);
  static const darkBg = Color(0xFF1A1A2E);
  static const surface = Color(0xFF16213E);
  static const surfaceElevated = Color(0xFF0F3460);

  // Semantic — run states
  static const success = Color(0xFF4CAF50);
  static const running = Color(0xFF2196F3);
  static const failed = Color(0xFFFF5252);
  static const crashed = Color(0xFFFF5252);
  static const warning = Color(0xFFFF9800);
  static const pending = Color(0xFF9E9E9E);

  // Chart palette (10 colors, colorblind-friendly)
  static const chartPalette = [
    Color(0xFF2196F3), // Blue
    Color(0xFFFF9800), // Orange
    Color(0xFF4CAF50), // Green
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF00BCD4), // Cyan
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF8BC34A), // Light Green
    Color(0xFF3F51B5), // Indigo
    Color(0xFFCDDC39), // Lime
  ];

  static Color forRunState(String? state) {
    switch (state?.toLowerCase()) {
      case 'running':
        return running;
      case 'finished':
        return success;
      case 'failed':
        return failed;
      case 'crashed':
        return crashed;
      case 'preempted':
      case 'preempting':
        return warning;
      case 'pending':
        return pending;
      default:
        return pending;
    }
  }
}
