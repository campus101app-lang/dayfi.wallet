import 'package:flutter/material.dart';

class AuroraAssistantButton extends StatefulWidget {
  final VoidCallback onPressed;
  const AuroraAssistantButton({super.key, required this.onPressed});

  @override
  State<AuroraAssistantButton> createState() => _AuroraAssistantButtonState();
}

class _AuroraAssistantButtonState extends State<AuroraAssistantButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _anim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).colorScheme.surface;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          return GestureDetector(
            onTap: widget.onPressed,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: SweepGradient(
                  center: Alignment.center,
                  startAngle: _anim.value * 2 * 3.14159,
                  colors: const [
                    Color(0xFFa78bfa),
                    Color(0xFF38bdf8),
                    Color(0xFF34d399),
                    Color(0xFFf472b6),
                    Color(0xFFa78bfa),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFFa78bfa), Color(0xFF38bdf8)],
                      ).createShader(bounds),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFFa78bfa), Color(0xFF38bdf8), Color(0xFF34d399)],
                      ).createShader(bounds),
                      child: const Text(
                        'Zemba Assistant',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class SpinningBorderAssistantButton extends StatefulWidget {
  final VoidCallback onPressed;
  const SpinningBorderAssistantButton({super.key, required this.onPressed});

  @override
  State<SpinningBorderAssistantButton> createState() =>
      _SpinningBorderAssistantButtonState();
}

class _SpinningBorderAssistantButtonState
    extends State<SpinningBorderAssistantButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: SizedBox(
        height: 52,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            return GestureDetector(
              onTap: widget.onPressed,
              child: CustomPaint(
                painter: _SpinningBorderPainter(_ctrl.value),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, color: textColor, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          'Zemba Assistant',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SpinningBorderPainter extends CustomPainter {
  final double progress;
  _SpinningBorderPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    final gradient = SweepGradient(
      startAngle: progress * 2 * 3.14159,
      endAngle: progress * 2 * 3.14159 + 2 * 3.14159,
      colors: const [
        Color(0xFF7c3aed),
        Color(0xFF06b6d4),
        Color(0xFF10b981),
        Color(0xFFf59e0b),
        Color(0xFFef4444),
        Color(0xFF7c3aed),
      ],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rRect, paint);
  }

  @override
  bool shouldRepaint(_SpinningBorderPainter old) => old.progress != progress;
}

class BreathingAssistantButton extends StatefulWidget {
  final VoidCallback onPressed;
  const BreathingAssistantButton({super.key, required this.onPressed});

  @override
  State<BreathingAssistantButton> createState() => _BreathingAssistantButtonState();
}

class _BreathingAssistantButtonState extends State<BreathingAssistantButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _shimmer = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return GestureDetector(
            onTap: widget.onPressed,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFa78bfa).withOpacity(0.35 + _glow.value * 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFa78bfa).withOpacity(_glow.value * 0.22),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: const Color(0xFF38bdf8).withOpacity(_glow.value * 0.13),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFa78bfa), Color(0xFF38bdf8)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFa78bfa).withOpacity(_glow.value * 0.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        textColor,
                        const Color(0xFFa78bfa),
                        textColor,
                      ],
                      stops: [
                        (_shimmer.value - 0.3).clamp(0.0, 1.0),
                        _shimmer.value.clamp(0.0, 1.0),
                        (_shimmer.value + 0.3).clamp(0.0, 1.0),
                      ],
                    ).createShader(bounds),
                    child: Text(
                      'Zemba Assistant',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class HolographicAssistantButton extends StatefulWidget {
  final VoidCallback onPressed;
  const HolographicAssistantButton({super.key, required this.onPressed});

  @override
  State<HolographicAssistantButton> createState() =>
      _HolographicAssistantButtonState();
}

class _HolographicAssistantButtonState extends State<HolographicAssistantButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _sheen;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _sheen = Tween<double>(begin: -0.5, end: 1.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return GestureDetector(
            onTap: widget.onPressed,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: SweepGradient(
                  startAngle: _ctrl.value * 2 * 3.14159,
                  endAngle: _ctrl.value * 2 * 3.14159 + 2 * 3.14159,
                  colors: const [
                    Color(0xFFf79533),
                    Color(0xFFf37055),
                    Color(0xFFef4e7b),
                    Color(0xFFa166ab),
                    Color(0xFF5073b8),
                    Color(0xFF1098ad),
                    Color(0xFF07b39b),
                    Color(0xFF6fba82),
                    Color(0xFFf79533),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(1.5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  children: [
                    Container(color: bg),
                    // Sheen sweep
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(_sheen.value * 400, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0),
                                Colors.white.withOpacity(0.12),
                                Colors.white.withOpacity(0),
                              ],
                              stops: const [0.3, 0.5, 0.7],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Content
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFFf79533),
                              Color(0xFFef4e7b),
                              Color(0xFF5073b8),
                              Color(0xFF07b39b),
                            ],
                          ).createShader(bounds),
                          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFFf79533),
                              Color(0xFFef4e7b),
                              Color(0xFFa166ab),
                              Color(0xFF5073b8),
                              Color(0xFF07b39b),
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'Zemba Assistant',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}