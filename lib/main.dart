import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'startup/startup_gate_page.dart';
import 'features/game/view/content_view.dart';
import 'features/game/view/test_view.dart';
import 'features/game/feedback/feedback_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SensorySafariApp());
}

class SensorySafariApp extends StatelessWidget {
  const SensorySafariApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensory Safari',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      builder: (context, child) {
        final current = MediaQuery.textScalerOf(context);
        final clamped = current.clamp(minScaleFactor: 0.8, maxScaleFactor: 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: clamped),
          child: child!,
        );
      },
      routes: {
        '/home': (_) => const ContentView(),
        '/test': (_) => const TestViewPage(),
        '/feedback': (_) => const FeedbackPage(),
      },
      home: const StartupGatePage(),
    );
  }
}