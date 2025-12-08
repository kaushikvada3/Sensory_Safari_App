import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'login_page.dart';
import 'loading_page.dart';
import 'rotate_gate_page.dart';
import '../features/game/view/test_view_placeholder.dart';
import '../features/game/view/content_view.dart';


class StartupGatePage extends StatefulWidget {
  const StartupGatePage({super.key});
  @override
  State<StartupGatePage> createState() => _StartupGatePageState();
}

class _StartupGatePageState extends State<StartupGatePage> {
  bool readyForApp = false;
  bool prewarmGame = false;

  @override
  void initState() {
    super.initState();
    // enter in portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLogin());
  }

  Future<void> _showLogin() async {
    await _presentFullScreen(
      builder: (_) => LoginPage(onComplete: _loginComplete),
      portraitOnly: true,
    );
  }

  void _loginComplete() {
    Navigator.of(context).pop(); // close login
    _showLoading();
  }

  Future<void> _showLoading() async {
    await _presentFullScreen(
      builder: (_) => LoadingPage(onComplete: _loadingComplete),
      portraitOnly: true,
    );
  }

  void _loadingComplete() {
    Navigator.of(context).pop(); // close loading
    // allow landscape while waiting for user to rotate
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _showRotateGate();
  }

  Future<void> _showRotateGate() async {
    await _presentFullScreen(
      builder: (_) => RotateGatePage(onReady: _rotateReady),
      portraitOnly: false,
    );
  }

  void _rotateReady() {
    Navigator.of(context).pop(); // close rotate
    // lock landscape for the app
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OrientationPauseOverlay(
          onPause: () {},
          onResume: () {},
          child: ContentView(
            onStart: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TestViewPage()),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _presentFullScreen({
    required WidgetBuilder builder,
    required bool portraitOnly,
  }) async {
    if (portraitOnly) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    await Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      barrierDismissible: false,
      barrierColor: Colors.black,
      pageBuilder: (routeCtx, __, ___) => builder(routeCtx),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(width: 40, height: 40, child: CircularProgressIndicator()),
      ),
    );
  }
}
