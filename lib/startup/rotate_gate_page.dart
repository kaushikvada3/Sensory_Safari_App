import 'package:flutter/material.dart';

class RotateGatePage extends StatefulWidget {
  final VoidCallback onReady;
  const RotateGatePage({super.key, required this.onReady});

  @override
  State<RotateGatePage> createState() => _RotateGatePageState();
}

class _RotateGatePageState extends State<RotateGatePage> {
  bool _didComplete = false;

  void _scheduleReadyOnce() {
    if (_didComplete) return;
    _didComplete = true;
    // Run AFTER the current build/layout is done
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          if (isLandscape) {
            // Don’t call directly in build; schedule it.
            _scheduleReadyOnce();
          } else {
            // If they rotate back, allow completion again later.
            _didComplete = false;
          }

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xE6000000), Color(0xFF000000)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: const SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.screen_rotation, size: 64, color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'Rotate to Landscape',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 6),
                    Text(
                      'We’ll continue automatically once you’re in landscape.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
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

/// Wrap your gameplay with this to auto-pause when the device rotates to portrait
/// and show the same "Rotate to Landscape" message as RotateGatePage.
///
/// Usage:
///   OrientationPauseOverlay(
///     onPause: _pauseGame,     // stop timers/animations
///     onResume: _resumeGame,   // restart timers/animations
///     child: YourGameView(),
///   )
class OrientationPauseOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const OrientationPauseOverlay({
    super.key,
    required this.child,
    required this.onPause,
    required this.onResume,
  });

  @override
  State<OrientationPauseOverlay> createState() => _OrientationPauseOverlayState();
}

class _OrientationPauseOverlayState extends State<OrientationPauseOverlay> {
  bool _paused = false; // true when in portrait

  void _maybeHandle(Orientation orientation) {
    final wantPause = orientation == Orientation.portrait;
    if (wantPause && !_paused) {
      _paused = true;
      // Defer callbacks/state to after build to avoid setState-in-build warnings
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onPause();
        setState(() {});
      });
    } else if (!wantPause && _paused) {
      _paused = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onResume();
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        _maybeHandle(orientation);
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_paused)
              AbsorbPointer(
                absorbing: true,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xE6000000), Color(0xFF000000)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: const SafeArea(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.screen_rotation, size: 64, color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Rotate to Landscape',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'We\'ll resume automatically once you\'re in landscape.',
                            style: TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}