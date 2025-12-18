import 'dart:ui' as ui; // Needed for ui.Gradient
import 'dart:ui'; // Needed for ImageFilter
import 'package:flutter/material.dart';

// ignore: unused_import
import 'package:flutter/services.dart';

/// The core container that provides the "Liquid Glass" effect:
/// - Dynamic blur (BackdropFilter)
/// - Translucent fill
/// - Specular gradient border
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurSigma;
  final List<Color>? gradientColors;
  final List<double>? gradientStops;
  final Color? solidColor;
  final Color borderColor;
  final double borderWidth;
  final double opacity;
  final List<BoxShadow>? boxShadow;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.width = double.infinity,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 20.0,
    this.blurSigma = 18.0,
    this.gradientColors,
    this.gradientStops,
    this.solidColor,
    this.borderColor = const Color(0x60FFFFFF),
    this.borderWidth = 1.0,
    this.opacity = 0.12,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow ?? [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              color: solidColor ?? (gradientColors == null ? Colors.white.withOpacity(opacity) : null),
              gradient: gradientColors != null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors!.map((c) => c.withOpacity(opacity)).toList(),
                      stops: gradientStops,
                    )
                  : null,
              border: Border.all(
                color: borderColor,
                width: borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A "Liquid Glass" styled button.
/// Applies a scale animation on press and uses the glass container.
class LiquidGlassButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double borderRadius;
  final double blurSigma;

  const LiquidGlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.borderRadius = 28.0,
    this.blurSigma = 12.0,
  });

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton> with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        child: LiquidGlassContainer(
          width: double.infinity,
          height: 56,
          borderRadius: widget.borderRadius,
          blurSigma: widget.blurSigma,
          opacity: _isPressed ? 0.25 : 0.15, // Slightly more opaque when pressed
          borderColor: Colors.white.withOpacity(_isPressed ? 0.6 : 0.3),
          child: Center(
            child: DefaultTextStyle(
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A text field wrapped in Liquid Glass.
class LiquidGlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  const LiquidGlassTextField({
    super.key,
    required this.controller,
    required this.label,
    this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassContainer(
      borderRadius: 16,
      opacity: 0.1,
      blurSigma: 12,
      borderColor: Colors.white.withOpacity(0.2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Colors.white70) : null,
          suffixIcon: suffixIcon,
          border: InputBorder.none, // Hide default border, use container's
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }
}

/// A top-level Scaffold replacement that handles the "Fluid" background blobs
/// and provides a Liquid Glass AppBar if desired.
class LiquidGlassScaffold extends StatefulWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final String? backgroundAsset; // Optional custom background image

  const LiquidGlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.backgroundAsset,
  });

  @override
  State<LiquidGlassScaffold> createState() => _LiquidGlassScaffoldState();
}

class _LiquidGlassScaffoldState extends State<LiquidGlassScaffold> with SingleTickerProviderStateMixin {
  late final AnimationController _bgCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat(reverse: true);

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.appBar, // Pass through, but usually we want a transparent one
      body: Stack(
        children: [
          // 1. Static Background Image
          Positioned.fill(
            child: widget.backgroundAsset != null
                ? Image.asset(widget.backgroundAsset!, fit: BoxFit.cover)
                : Container( // fallback gradient if no asset
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2C5364), Color(0xFF203A43), Color(0xFF0F2027)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
          ),

          // 2. Animated Fluid Blobs (The "Liquid" part)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _bgCtrl,
              builder: (context, _) {
                final t = _bgCtrl.value;
                final dx1 = (t - 0.5) * 40;
                final dy1 = (t - 0.5) * -30;
                final dx2 = (0.5 - t) * 50;
                final dy2 = (t - 0.5) * 26;
                return Stack(children: [
                  Positioned(
                    left: -80 + dx1,
                    top: -40 + dy1,
                    child: _Blob(size: 250, color: const Color(0xFF00C2B7).withOpacity(0.18)),
                  ),
                  Positioned(
                    right: -60 + dx2,
                    bottom: 120 + dy2,
                    child: _Blob(size: 200, color: const Color(0xFF7BEA5A).withOpacity(0.14)),
                  ),
                  Positioned(
                    left: 20 - dx2,
                    bottom: -80 - dy1,
                    child: _Blob(size: 300, color: const Color(0xFF38E7D3).withOpacity(0.12)),
                  ),
                ]);
              },
            ),
          ),

          // 3. Main Content (Safe Area handled by caller or here)
          Positioned.fill(child: widget.body),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BlobPainter(color),
        size: Size.square(size),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  final Color color;
  _BlobPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        size.width * 0.5,
        [color, color.withOpacity(0.0)],
        [0.0, 1.0],
      );
    canvas.drawCircle(rect.center, size.width * 0.5, paint);
  }
  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => oldDelegate.color != color;
}
