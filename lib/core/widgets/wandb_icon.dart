import 'package:flutter/material.dart';

class WandbIcon extends StatelessWidget {
  const WandbIcon(this.name, {super.key, this.size = 24, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icons/$name.png',
    width: size,
    height: size,
    color: color ?? IconTheme.of(context).color,
    excludeFromSemantics: true,
  );
}
