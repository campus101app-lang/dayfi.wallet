// lib/widgets/app_background.dart
import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.6, -0.8),
          radius: 1.4,
          colors: isDark
              ? [
                  const Color.fromARGB(255, 37, 37, 37), // deep blue-slate top-left
                  const Color.fromARGB(255, 21, 21, 21), // near-black center
                  const Color.fromARGB(255, 9, 9, 9), // pure dark bottom
                ]
              : [
                  const Color(0xFFF0F4FF),
                  const Color(0xFFFAFAFF),
                  const Color(0xFFFFFFFF),
                ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}