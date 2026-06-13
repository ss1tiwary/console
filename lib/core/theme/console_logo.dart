import 'package:flutter/material.dart';

class ConsoleLogo extends StatelessWidget {
  final double size;
  const ConsoleLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.2),
      child: Image.asset(
        'assets/icon/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
