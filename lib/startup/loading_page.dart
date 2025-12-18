import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Simple, friendly loading page that matches LoginPage's theme.
/// - Same teal→green gradient and faint icon backdrop
/// - Big title + tiny subtitle
/// - Determinate progress ring + numeric percent
/// - Calls onComplete() when it reaches 100%
class LoadingPage extends StatefulWidget {
  final VoidCallback onComplete;
  const LoadingPage({super.key, required this.onComplete});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  late final Timer _progressTimer;
  double _progress = 0; // 0..1

  @override
  void initState() {
    super.initState();
    // Keep login flow portrait-only here as well.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Smooth, quick fill to 100% (~2.4s) then continue.
    _progressTimer = Timer.periodic(const Duration(milliseconds: 40), (t) {
      setState(() => _progress = (_progress + 0.016).clamp(0, 1));
      if (_progress >= 1) {
        t.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onComplete();
        });
      }
    });
  }

  @override
  void dispose() {
    _progressTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).clamp(0, 100).toInt();

    return Scaffold(
      body: Stack(
        children: [
          // ---- Portrait background image ----
          Positioned.fill(
            child: Image.asset(
              'assets/portrait_background.jpg',
              fit: BoxFit.cover,
            ),
          ),

          // ---- Same faint decorative icons as LoginPage ----
          const IgnorePointer(
            child: Opacity(
              opacity: 0.08,
              child: Stack(
                children: [
                  Positioned(left: -16, top: 80, child: Icon(Icons.pets, size: 120, color: Colors.white)),
                  Positioned(right: -8, top: 220, child: Icon(Icons.pets, size: 80, color: Colors.white)),
                  Positioned(left: 24, bottom: 140, child: Icon(Icons.eco, size: 100, color: Colors.white)),
                  Positioned(right: 18, bottom: 60, child: Icon(Icons.forest, size: 110, color: Colors.white)),
                ],
              ),
            ),
          ),

          // ---- Content ----
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pets, size: 48, color: Colors.white),
                      const SizedBox(height: 10),
                      const Text(
                        'Preparing your Safari…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Progress ring matching the friendly style
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: CircularProgressIndicator(
                                value: _progress,
                                strokeWidth: 6,
                                backgroundColor: Colors.white.withOpacity(0.25),
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            Text(
                              '$percent%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),
                      const Text(
                        'This will only take a moment',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}