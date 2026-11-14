import 'package:flutter/material.dart';

/// Декоративный фон для экранов входа/регистрации — крупные мягкие
/// сине-голубые круги за формой, в духе референса, но без градиентов
/// и лишних деталей, чтобы не спорить с минималистичным стилем
/// остального приложения. Круги полупрозрачные и статичные (не мешают
/// читаемости полей поверх них).
class AuthBackground extends StatelessWidget {
  final Widget child;

  const AuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned(
          top: -80,
          right: -60,
          child: _Circle(
            size: 220,
            color: colorScheme.primary.withValues(alpha: 0.14),
          ),
        ),
        Positioned(
          top: 60,
          left: -70,
          child: _Circle(
            size: 140,
            color: colorScheme.primaryContainer.withValues(alpha: 0.35),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -80,
          child: _Circle(
            size: 260,
            color: colorScheme.primary.withValues(alpha: 0.10),
          ),
        ),
        Positioned(
          bottom: -40,
          right: -40,
          child: _Circle(
            size: 160,
            color: colorScheme.primaryContainer.withValues(alpha: 0.28),
          ),
        ),
        child,
      ],
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final Color color;

  const _Circle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
