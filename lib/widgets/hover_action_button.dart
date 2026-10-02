import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'dart:math' as math;

class HoverActionButton extends StatefulWidget {
  final String text;
  final String? loadingText;
  final VoidCallback? onTap;
  final bool isLoading;
  final double height;
  final bool isDestructive;
  final bool useZoom;
  final Color? color;

  const HoverActionButton({
    super.key,
    required this.text,
    this.loadingText,
    this.onTap,
    this.isLoading = false,
    this.height = 56,
    this.isDestructive = false,
    this.useZoom = true,
    this.color,
  });

  @override
  State<HoverActionButton> createState() => _HoverActionButtonState();
}

class _HoverActionButtonState extends State<HoverActionButton> with SingleTickerProviderStateMixin {
  bool _isActive = false;
  late AnimationController _truckController;

  @override
  void initState() {
    super.initState();
    _truckController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isLoading) _truckController.repeat();
  }

  @override
  void didUpdateWidget(HoverActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading) {
      _truckController.repeat();
    } else {
      _truckController.stop();
    }
  }

  @override
  void dispose() {
    _truckController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isEnabled = widget.onTap != null && !widget.isLoading;
    bool isRed = widget.isDestructive || 
                 widget.text.toLowerCase().contains("delete") || 
                 widget.text.toLowerCase().contains("reject") ||
                 widget.text.toLowerCase().contains("archive");

    final double screenWidth = MediaQuery.of(context).size.width;
    final double fontSize = (screenWidth * 0.045).clamp(14.0, 18.0);
    final double loadingFontSize = (screenWidth * 0.04).clamp(12.0, 16.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isActive = isEnabled),
      onExit: (_) => setState(() => _isActive = false),
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isActive = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isActive = false) : null,
        onTapCancel: isEnabled ? () => setState(() => _isActive = false) : null,
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: (widget.useZoom && _isActive) ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: widget.height,
            margin: const EdgeInsets.symmetric(horizontal: 4), // Add small margin to prevent shadow clipping
            decoration: BoxDecoration(
              gradient: widget.color != null 
                ? LinearGradient(colors: [widget.color!, widget.color!.withOpacity(0.8)])
                : LinearGradient(
                    colors: isEnabled
                        ? (isRed 
                            ? [Colors.redAccent, Colors.red.shade900]
                            : [AppColors.loginButtonStart, AppColors.loginButtonEnd])
                        : [Colors.grey.shade400, Colors.grey.shade500],
                  ),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: widget.isLoading
                ? _buildLoadingContent(loadingFontSize)
                : Text(
                    widget.text,
                    style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingContent(double fontSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _truckController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(math.sin(_truckController.value * 2 * math.pi) * 4, 0),
              child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 24),
            );
          },
        ),
        const SizedBox(width: 12),
        Text(
          widget.loadingText ?? 'Processing...',
          style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ],
    );
  }
}
