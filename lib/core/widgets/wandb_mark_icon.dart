import 'package:flutter/material.dart';

import '../theme/colors.dart';

class WandbMarkIcon extends StatelessWidget {
  const WandbMarkIcon({super.key, this.size = 18, this.compact = false});

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? size * 0.44 : size * 0.46;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WandbColors.yellow,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Text(
        'W',
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: fontSize,
          height: 1,
        ),
      ),
    );
  }
}
