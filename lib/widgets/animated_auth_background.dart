import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class AnimatedAuthBackground extends StatefulWidget {
  final Widget child;
  final bool resizeToAvoidBottomInset;
  const AnimatedAuthBackground({
    super.key, 
    required this.child,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  State<AnimatedAuthBackground> createState() => _AnimatedAuthBackgroundState();
}

class _AnimatedAuthBackgroundState extends State<AnimatedAuthBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      body: Stack(
        children: [
          // Base "Palabo na Palinaw" Gradient (Green & White)
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: AppDecorations.authBackground,
          ),
          // Original Animated Greenish Circles
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                children: [
                  _buildCircle(
                    size: math.min(size.width * 0.7, 400.0), 
                    color: const Color(0xFF80CBC4).withAlpha(30), // Original Greenish
                    offset: Offset(math.sin(_controller.value * 2 * math.pi) * 30, math.cos(_controller.value * 2 * math.pi) * 50), 
                    top: -80, 
                    left: -80, 
                    scale: 0.8 + math.sin(_controller.value * math.pi) * 0.2
                  ),
                  _buildCircle(
                    size: math.min(size.width * 0.9, 500.0), 
                    color: const Color(0xFF4DB6AC).withAlpha(20), // Original Greenish
                    offset: Offset(math.cos(_controller.value * 2 * math.pi) * 40, math.sin(_controller.value * 2 * math.pi) * 30), 
                    bottom: -100, 
                    right: -100, 
                    scale: 0.9 + math.cos(_controller.value * math.pi) * 0.1
                  ),
                  _buildCircle(
                    size: math.min(size.width * 0.5, 300.0), 
                    color: const Color(0xFF26A69A).withAlpha(25), // Original Greenish
                    offset: Offset(math.sin(_controller.value * 2 * math.pi) * 20, math.sin(_controller.value * 2 * math.pi) * 60), 
                    top: size.height * 0.3, 
                    right: size.width * 0.05,
                    scale: 0.7 + math.sin(_controller.value * 2 * math.pi) * 0.3
                  ),
                ],
              );
            },
          ),
          // Content
          widget.child,
        ],
      ),
    );
  }

  Widget _buildCircle({required double size, required Color color, required Offset offset, double? top, double? left, double? bottom, double? right, required double scale}) {
    return Positioned(
      top: top, left: left, bottom: bottom, right: right,
      child: Transform.translate(
        offset: offset,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
