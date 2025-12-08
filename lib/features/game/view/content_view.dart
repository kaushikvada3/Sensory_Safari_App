import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui; // for ImageFilter.blur (glass effect)
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/difficulty_utils.dart';

/// ============ Settings model (like your Swift ObservableObject) ============
class SensorySafariSettings extends ChangeNotifier {
  int selectedAnimal = 0;
  int selectedDifficulty = 0;
  bool lightsOn = false;
  bool soundOn = false;
  double numTries = 5;
  double stimDuration = 5;
  double outcomeDuration = 2;

  // Adaptive mode settings
  bool adaptiveEnabled = false;          // when true, ignore selectedDifficulty and use adaptive engine
  double adaptiveSpeedMultiplier = 1.0;  // 1.0 = Adaptive, >1.0 = Adaptive (Fast)

  static final SensorySafariSettings I = SensorySafariSettings();

  static const _k = 'ss_';
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    selectedAnimal     = p.getInt('${_k}selectedAnimal') ?? selectedAnimal;
    selectedDifficulty = p.getInt('${_k}selectedDifficulty') ?? selectedDifficulty;
    lightsOn           = p.getBool('${_k}lightsOn') ?? lightsOn;
    soundOn            = p.getBool('${_k}soundOn') ?? soundOn;
    numTries           = p.getDouble('${_k}numTries') ?? numTries;
    stimDuration       = p.getDouble('${_k}stimDuration') ?? stimDuration;
    outcomeDuration    = p.getDouble('${_k}outcomeDuration') ?? outcomeDuration;
    adaptiveEnabled    = p.getBool('${_k}adaptiveEnabled') ?? adaptiveEnabled;
    adaptiveSpeedMultiplier = p.getDouble('${_k}adaptiveSpeedMultiplier') ?? adaptiveSpeedMultiplier;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('${_k}selectedAnimal', selectedAnimal);
    await p.setInt('${_k}selectedDifficulty', selectedDifficulty);
    await p.setBool('${_k}lightsOn', lightsOn);
    await p.setBool('${_k}soundOn', soundOn);
    await p.setDouble('${_k}numTries', numTries);
    await p.setDouble('${_k}stimDuration', stimDuration);
    await p.setDouble('${_k}outcomeDuration', outcomeDuration);
    await p.setBool('${_k}adaptiveEnabled', adaptiveEnabled);
    await p.setDouble('${_k}adaptiveSpeedMultiplier', adaptiveSpeedMultiplier);
  }

  void setAnimal(int i) { selectedAnimal = i; notifyListeners(); _save(); }
  void setDifficulty(int i) { selectedDifficulty = i; notifyListeners(); _save(); }
  void setLights(bool on) { lightsOn = on; notifyListeners(); _save(); }
  void setSound(bool on) { soundOn = on; notifyListeners(); _save(); }
  void setNumTries(double v) { numTries = v; notifyListeners(); _save(); }
  void setStim(double v) { stimDuration = v; notifyListeners(); _save(); }
  void setOutcome(double v) { outcomeDuration = v; notifyListeners(); _save(); }
  void setAdaptive({required bool enabled, double? speedMultiplier}) {
    adaptiveEnabled = enabled;
    if (speedMultiplier != null) adaptiveSpeedMultiplier = speedMultiplier;
    notifyListeners();
    _save();
  }
}

/// ============ ContentView ============
class ContentView extends StatefulWidget {
  final void Function()? onStart;
  const ContentView({super.key, this.onStart});

  @override
  State<ContentView> createState() => _ContentViewState();
}

class Level {
  final String key;
  final String emoji;
  final Color color;
  const Level(this.key, this.emoji, this.color);

  String get label => displayDifficultyName(key);
}

class _ContentViewState extends State<ContentView>
    with TickerProviderStateMixin {
  final SensorySafariSettings settings = SensorySafariSettings.I;

  bool _didLoad = false;

  final List<String> animals = const ["turtle", "cat", "elephant", "monkey"];
  final List<Level> levels = const [
    Level('easy', "🙂", Colors.green),
    Level('medium', "😐", Colors.blue),
    Level('hard', "😮‍💨", Colors.orange),
    Level('veryHard', "🤯", Colors.red),
    Level('adaptive', "🧠", Colors.teal),
    Level('adaptiveFast', "⚡️", Colors.orange),
  ];

  int get _safeAnimalIndex {
    final a = settings.selectedAnimal;
    return (a >= 0 && a < animals.length) ? a : 0;
  }

  int get _safeDifficultyIndex {
    final d = settings.selectedDifficulty;
    return (d >= 0 && d < levels.length) ? d : 0;
  }

  Color _goColorForDifficulty(int i) {
    if (i < 0 || i >= levels.length) return Colors.green;
    switch (levels[i].key) {
      case 'easy':
        return Colors.green;
      case 'medium':
        return Colors.blue;
      case 'hard':
        return Colors.orange;
      case 'veryHard':
        return Colors.red;
      case 'adaptive':
        return Colors.teal;
      case 'adaptiveFast':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  late final AnimationController _titlePulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  late final AnimationController _titleWobble =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  late final AnimationController _mascotBob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  late final AnimationController _adaptiveSlow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  late final AnimationController _adaptiveFast =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  final PageController _animalCtrl = PageController(viewportFraction: 1.0);
  final PageController _diffCtrl   = PageController(viewportFraction: 0.72);

  bool _showCountdown = false;

  @override
  void initState() {
    super.initState();
    if (!_didLoad) {
      _didLoad = true;
      settings.addListener(_onSettingsChanged);

      settings.load().then((_) {
        if (!mounted) return;

        bool changed = false;
        if (settings.selectedAnimal < 0 || settings.selectedAnimal >= animals.length) {
          settings.selectedAnimal = 0; changed = true;
        }
        if (settings.selectedDifficulty < 0 || settings.selectedDifficulty >= levels.length) {
          settings.selectedDifficulty = 0; changed = true;
        }
        try { _animalCtrl.jumpToPage(_safeAnimalIndex); } catch (_) {}
        try { _diffCtrl.jumpToPage(_safeDifficultyIndex); } catch (_) {}
        if (changed && mounted) setState(() {});
      });
    }
  }

  void _onSettingsChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _titlePulse.dispose();
    _titleWobble.dispose();
    _mascotBob.dispose();
    _adaptiveSlow.dispose();
    _adaptiveFast.dispose();
    _animalCtrl.dispose();
    _diffCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cap system text scale on the home/settings screen so large accessibility fonts don't break layout
    final mq = MediaQuery.of(context);
    final capped = mq.copyWith(textScaleFactor: mq.textScaleFactor.clamp(0.8, 1.2));
    return MediaQuery(
      data: capped,
      child: Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: Image.asset(
            'assets/Background.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0BBAB4), Color(0xFF61DA6E)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              );
            },
          ),
        ),

        SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final size = box.biggest;
            final compact = size.width < 930 || size.height < 420;
            final ultraCompact = size.height < 380;
            final extraTight = size.height < 360;
            final bottomSafe = MediaQuery.of(context).padding.bottom;

            // Global scaling (allow a bit smaller than before for short screens)
            const baseH = 430.0;
            final scale = (size.height / baseH).clamp(0.46, 1.0);

            // Layout metrics
            final colW = (size.width * (compact ? 0.24 : 0.20) * scale).clamp(126.0, 220.0);
            final hSpacing = (size.width * 0.018 * scale).clamp(6.0, 16.0);
            // tighten top padding a bit
            final topPad = (ultraCompact ? 0.0 : (compact ? 2.0 : 8.0)) * scale;

            // Adjust animal carousel height and max clamp (reduce by 7.1 pixels)
            final animalBoxH = ((ultraCompact ? 150.0 : (compact ? 186.0 : 288.0)) * scale).clamp(120.0, 300.0);

            // Balance difficulty card footprint against larger animal art
            final diffW = ((size.width * 0.26) * scale).clamp(150.0, 280.0);
            final diffH = ((size.height * 0.18) * scale).clamp(80.0, 160.0);

            final toggleW = (colW * 0.78).clamp(116.0, 190.0);
            final toggleH = ((colW * 0.45) * scale).clamp(62.0, 100.0);

            final double liftY = extraTight ? -12.0 : (ultraCompact ? -8.0 : (compact ? -6.0 : 0.0));
            // Reduce title font size by 7.1 pixels
            final double titleFont = (compact ? 22.9 : 32.9) * scale; // was 30.0/40.0
            final double chevronSize = (26.0 * scale).clamp(20.0, 26.0);

            return AnimatedBuilder(
              animation: settings,
              builder: (_, __) {
                final edgePad = (size.width * 0.018).clamp(8.0, 14.0);
                final safeAnimal = _safeAnimalIndex;
                final safeDiff   = _safeDifficultyIndex;

                final availableH = size.height - bottomSafe - 6.0;

                // Define fitScale to dynamically scale the layout based on available height
            final double fitScale = (availableH / (baseH + 1)).clamp(0.46, 1.0);

                // Define bottomSpacer as a constant for spacing at the bottom
                const double bottomSpacer = 20.0;

                return Padding(
                  padding: EdgeInsets.all(edgePad),
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: availableH,
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left column
                            Flexible(
                              flex: 0,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: 116, maxWidth: colW),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    StepperPill(
                                      title: "Tries",
                                      value: settings.numTries.toInt(),
                                      range: const RangeValues(1, 30),
                                      onChanged: (v) => settings.setNumTries(v.toDouble()),
                                    ),
                                    const SizedBox(height: 10),
                                    StepperPill(
                                      title: "Stimulus (sec)",
                                      value: settings.stimDuration.toInt(),
                                      range: const RangeValues(1, 10),
                                      onChanged: (v) => settings.setStim(v.toDouble()),
                                    ),
                                    const SizedBox(height: 10),
                                    StepperPill(
                                      title: "Outcome (sec)",
                                      value: settings.outcomeDuration.toInt(),
                                      range: const RangeValues(1, 10),
                                      onChanged: (v) => settings.setOutcome(v.toDouble()),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: hSpacing),

                            // Center column
                            Expanded(
                              child: Transform.translate(
                                offset: Offset(0, liftY), // Reset vertical offset to avoid further issues
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Transform.scale(
                                    scale: fitScale,
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.max,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // --- Top: title + animal ---
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(height: topPad),
                                            Padding(
                                              padding: const EdgeInsets.only(top: 0),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  AnimatedBuilder(
                                                    animation: _mascotBob,
                                                    builder: (_, __) {
                                                      final t = (_mascotBob.value * 2 - 1);
                                                      final y = t * 4;
                                                      return Transform.translate(
                                                        offset: Offset(0, y),
                                                        child: Image.asset(
                                                          'assets/${animals[safeAnimal]}.png',
                                                          // Increase mascot icon size
                                                          width: (compact ? 54 : 72) * scale,
                                                          height: (compact ? 54 : 72) * scale,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  const SizedBox(width: 13),
                                                  AnimatedBuilder(
                                                    animation: Listenable.merge([_titlePulse, _titleWobble]),
                                                    builder: (_, __) {
                                                      final pulse = 1.0 + 0.04 * (_titlePulse.value * 2 - 1).abs();
                                                      final wobble = (_titleWobble.value * 2 - 1) * 1.6;
                                                      return Transform.rotate(
                                                        angle: wobble * 3.14159 / 180.0,
                                                        child: Transform.scale(
                                                          scale: pulse,
                                                          child: FittedBox(
                                                            fit: BoxFit.scaleDown,
                                                            child: Text(
                                                              "Sensory Safari",
                                                              style: TextStyle(
                                                                fontSize: titleFont * 1.4, // Increase font size by 40%
                                                                fontWeight: FontWeight.w900,
                                                                color: Colors.white,
                                                                shadows: const [
                                                                  Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 4), // tighter
                                            Column(
                                              children: [
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: const Text(
                                                    "Animal",
                                                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                const SizedBox(height: 2), // tighter
                                                SizedBox(
                                                  height: animalBoxH,
                                                  child: Stack(
                                                    children: [
                                                      PageView.builder(
                                                        controller: _animalCtrl,
                                                        onPageChanged: (i) { HapticFeedback.mediumImpact(); settings.setAnimal(i); },
                                                        itemCount: animals.length,
                                                        itemBuilder: (_, i) {
                                                          return Center(
                                                            child: Padding(
                                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                              child: Image.asset(
                                                                'assets/${animals[i]}.png',
                                                                height: animalBoxH * 0.90,
                                                                fit: BoxFit.contain,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                      Positioned.fill(
                                                        child: Row(
                                                          children: [
                                                            IconButton(
                                                              onPressed: () {
                                                                final int prev = ((safeAnimal - 1).clamp(0, animals.length - 1)).toInt();
                                                                _animalCtrl.animateToPage(prev, duration: const Duration(milliseconds: 220), curve: Curves.easeInOut);
                                                              },
                                                              icon: Icon(Icons.chevron_left_rounded, size: chevronSize, color: Colors.white),
                                                            ),
                                                            const Spacer(),
                                                            IconButton(
                                                              onPressed: () {
                                                                final int next = ((safeAnimal + 1).clamp(0, animals.length - 1)).toInt();
                                                                _animalCtrl.animateToPage(next, duration: const Duration(milliseconds: 220), curve: Curves.easeInOut);
                                                              },
                                                              icon: Icon(Icons.chevron_right_rounded, size: chevronSize, color: Colors.white),
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),

                                        // --- Middle: Difficulty ---
                                        const SizedBox(height: 8), // tighter
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: const Text(
                                                "Difficulty Level",
                                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(height: 2), // tighter
                                            SizedBox(
                                              height: diffH + 10, // slightly tighter
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  PageView(
                                                    controller: _diffCtrl,
                                                    onPageChanged: (i) {
                                                      HapticFeedback.mediumImpact();
                                                      settings.setDifficulty(i); // keep dots in sync
                                                      if (i == 4) {
                                                        settings.setAdaptive(enabled: true, speedMultiplier: 1.0);
                                                      } else if (i == 5) {
                                                        settings.setAdaptive(enabled: true, speedMultiplier: 1.35);
                                                      } else {
                                                        settings.setAdaptive(enabled: false);
                                                      }
                                                    },
                                                    children: List<Widget>.generate(levels.length, (i) {
                                                      final rec = levels[i];
                                                      final color = rec.color;
                                                      final isSel = i == safeDiff;
                                                      final double labelFont = (compact ? (ultraCompact ? 16.0 : 18.0) : 24.0) * scale;

                                                      return Center(
                                                        child: AnimatedScale(
                                                          duration: const Duration(milliseconds: 200),
                                                          scale: isSel ? 1.02 : 0.9,
                                                          child: Container(
                                                            width: diffW,
                                                            height: diffH,
                                                            decoration: BoxDecoration(
                                                              borderRadius: BorderRadius.circular(18),
                                                              boxShadow: [
                                                                BoxShadow(color: Colors.black.withOpacity(0.26), blurRadius: 10, offset: const Offset(0, 4)),
                                                                BoxShadow(color: ((){
                                                                  Color cardColor = color;
                                                                  if (rec.key == 'adaptive') {
                                                                    final t = _adaptiveSlow.value;
                                                                    cardColor = Color.lerp(Colors.teal, Colors.blueAccent, t)!;
                                                                  } else if (rec.key == 'adaptiveFast') {
                                                                    final t = _adaptiveFast.value;
                                                                    cardColor = Color.lerp(Colors.orange, Colors.redAccent, t)!;
                                                                  }
                                                                  return cardColor.withOpacity(isSel ? 0.40 : 0.18);
                                                                })(), blurRadius: isSel ? 20 : 12, offset: const Offset(0, 8)),
                                                              ],
                                                            ),
                                                            child: ClipRRect(
                                                              borderRadius: BorderRadius.circular(18),
                                                              child: BackdropFilter(
                                                                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                                                child: Container(
                                                                  decoration: BoxDecoration(
                                                                    borderRadius: BorderRadius.circular(18),
                                                                    gradient: LinearGradient(
                                                                      begin: Alignment.topLeft,
                                                                      end: Alignment.bottomRight,
                                                                      colors: ((){
                                                                        Color cardColor = color;
                                                                        if (rec.key == 'adaptive') {
                                                                          final t = _adaptiveSlow.value;
                                                                          cardColor = Color.lerp(Colors.teal, Colors.blueAccent, t)!;
                                                                        } else if (rec.key == 'adaptiveFast') {
                                                                          final t = _adaptiveFast.value;
                                                                          cardColor = Color.lerp(Colors.orange, Colors.redAccent, t)!;
                                                                        }
                                                                        return [
                                                                          cardColor.withOpacity(isSel ? 0.58 : 0.36),
                                                                          Colors.white.withOpacity(isSel ? 0.16 : 0.10),
                                                                        ];
                                                                      })(),
                                                                    ),
                                                                    border: Border.all(
                                                                      color: ((){
                                                                        Color cardColor = color;
                                                                        if (rec.key == 'adaptive') {
                                                                          final t = _adaptiveSlow.value;
                                                                          cardColor = Color.lerp(Colors.teal, Colors.blueAccent, t)!;
                                                                        } else if (rec.key == 'adaptiveFast') {
                                                                          final t = _adaptiveFast.value;
                                                                          cardColor = Color.lerp(Colors.orange, Colors.redAccent, t)!;
                                                                        }
                                                                        return cardColor.withOpacity(isSel ? 0.68 : 0.42);
                                                                      })(),
                                                                      width: 1.4,
                                                                    ),
                                                                  ),
                                                                  alignment: Alignment.center,
                                                                  child: FittedBox(
                                                                    fit: BoxFit.scaleDown,
                                                                    child: Padding(
                                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                                      child: Column(
                                                                        mainAxisSize: MainAxisSize.min,
                                                                        children: [
                                                                          Text(rec.emoji, style: TextStyle(fontSize: (compact ? 58.0 : 84.0) * scale)),
                                                                          const SizedBox(height: 4),
                                                                          Text(
                                                                            rec.label,
                                                                            style: TextStyle(
                                                                              color: Colors.white,
                                                                              fontWeight: FontWeight.w800,
                                                                              fontSize: labelFont,
                                                                              shadows: const [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }),
                                                  ),
                                                  Positioned.fill(
                                                    child: Row(children: [
                                                      IconButton(
                                                        onPressed: () {
                                                          final int prev = ((safeDiff - 1).clamp(0, levels.length - 1)).toInt();
                                                          _diffCtrl.animateToPage(prev, duration: const Duration(milliseconds: 220), curve: Curves.easeInOut);
                                                        },
                                                        icon: Icon(Icons.chevron_left_rounded, size: chevronSize, color: Colors.white),
                                                      ),
                                                      const Spacer(),
                                                      IconButton(
                                                        onPressed: () {
                                                          final int next = ((safeDiff + 1).clamp(0, levels.length - 1)).toInt();
                                                          _diffCtrl.animateToPage(next, duration: const Duration(milliseconds: 220), curve: Curves.easeInOut);
                                                        },
                                                        icon: Icon(Icons.chevron_right_rounded, size: chevronSize, color: Colors.white),
                                                      ),
                                                    ]),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 4), // tighter
                                            Wrap(
                                              alignment: WrapAlignment.center,
                                              spacing: 8,
                                              children: List<Widget>.generate(levels.length, (i) {
                                                final sel = i == safeDiff;
                                                return Container(
                                                  width: sel ? (ultraCompact ? 6 : 8) : (ultraCompact ? 4 : 5),
                                                  height: sel ? (ultraCompact ? 6 : 8) : (ultraCompact ? 4 : 5),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(sel ? 0.95 : 0.4),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: Colors.black.withOpacity(0.15), width: 1),
                                                  ),
                                                );
                                              }),
                                            ),
                                          ],
                                        ),

                                        // push button to bottom without scrolling
                                        const Spacer(),
                                        const SizedBox(height: bottomSpacer), // Use the defined bottomSpacer
                                        SafeArea(
                                          bottom: true,
                                          minimum: EdgeInsets.only(bottom: bottomSafe > 20.0 ? bottomSafe : 20.0), // Define safeMinBottom inline
                                          child: _GoButton(
                                            compact: compact,
                                            accent: _goColorForDifficulty(safeDiff),
                                            onPressed: () {
                                              HapticFeedback.mediumImpact();
                                              setState(() => _showCountdown = true);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: hSpacing),

                            // Right column
                            Flexible(
                              flex: 0,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: 116, maxWidth: colW),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: toggleW,
                                      height: toggleH,
                                      child: IconToggle(
                                        system: Icons.wb_sunny_rounded,
                                        label: "Lights",
                                        isOn: settings.lightsOn,
                                        onChanged: (v) => settings.setLights(v),
                                      ),
                                    ),
                                    const SizedBox(height: 16), // Increased gap between buttons
                                    SizedBox(
                                      width: toggleW,
                                      height: toggleH,
                                      child: IconToggle(
                                        system: Icons.volume_up_rounded,
                                        label: "Sound",
                                        isOn: settings.soundOn,
                                        onChanged: (v) => settings.setSound(v),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),

        if (_showCountdown)
          _CountdownOverlay(
            onDone: () {
              setState(() => _showCountdown = false);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.of(context, rootNavigator: true).pushReplacementNamed('/test');
              });
            },
          ),
      ]),
      ),
    );
  }
}

/// ====================== Small widgets ======================

class StepperPill extends StatefulWidget {
  final String title;
  final int value;
  final RangeValues range; // lower..upper (ints)
  final ValueChanged<int> onChanged;
  const StepperPill({
    super.key,
    required this.title,
    required this.value,
    required this.range,
    required this.onChanged,
  });

  @override
  State<StepperPill> createState() => _StepperPillState();
}

class _StepperPillState extends State<StepperPill> {
  Timer? _repeatTimer;
  bool _holding = false;

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _holding = false;
  }

  void _startRepeat({required bool increment}) {
    if (_holding) return;
    _holding = true;

    // Start repeating only after a short delay so a quick tap
    // results in a single increment via onPressed. If the user
    // keeps holding beyond the delay, begin auto-repeat.
    _repeatTimer?.cancel();
    _repeatTimer = Timer(const Duration(milliseconds: 450), () {
      _repeatTimer?.cancel();
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        _step(increment: increment);
      });
    });
  }

  void _step({required bool increment}) {
    final low = widget.range.start.toInt();
    final high = widget.range.end.toInt();
    final v = widget.value;
    if (increment) {
      if (v < high) {
        HapticFeedback.heavyImpact();
        widget.onChanged(v + 1);
      } else {
        _stopRepeat();
      }
    } else {
      if (v > low) {
        HapticFeedback.heavyImpact();
        widget.onChanged(v - 1);
      } else {
        _stopRepeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final low = widget.range.start.toInt(), high = widget.range.end.toInt();
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18), // was 14
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withOpacity(0.28), Colors.white.withOpacity(0.10)],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.2),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 18, spreadRadius: 1, offset: const Offset(0, 10)),
              BoxShadow(color: Colors.white.withOpacity(0.12), blurRadius: 2, offset: const Offset(-1, -1)),
            ],
          ),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4), // was 6
              Row(
                children: [
                  Listener(
                    onPointerDown: (_) => _startRepeat(increment: false),
                    onPointerUp:   (_) => _stopRepeat(),
                    onPointerCancel: (_) => _stopRepeat(),
                    child: IconButton(
                      onPressed: widget.value > low ? () { HapticFeedback.heavyImpact(); widget.onChanged(widget.value - 1); } : null,
                      icon: const Icon(Icons.remove_circle),
                      visualDensity: VisualDensity.compact,
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${widget.value}',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28, // starting point; FittedBox will scale down
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Listener(
                    onPointerDown: (_) => _startRepeat(increment: true),
                    onPointerUp:   (_) => _stopRepeat(),
                    onPointerCancel: (_) => _stopRepeat(),
                    child: IconButton(
                      onPressed: widget.value < high ? () { HapticFeedback.heavyImpact(); widget.onChanged(widget.value + 1); } : null,
                      icon: const Icon(Icons.add_circle),
                      visualDensity: VisualDensity.compact,
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }
}

class IconToggle extends StatelessWidget {
  final IconData system;
  final String label;
  final bool isOn;
  final ValueChanged<bool> onChanged;
  const IconToggle({
    super.key,
    required this.system,
    required this.label,
    required this.isOn,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.heavyImpact(); onChanged(!isOn); },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity, height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.28), Colors.white.withOpacity(0.10)],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: (isOn ? const Color.fromARGB(255, 15, 212, 117).withOpacity(0.5) : Colors.black.withOpacity(0.28)),
                  blurRadius: isOn ? 22 : 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(color: Colors.white.withOpacity(0.12), blurRadius: 2, offset: const Offset(-1, -1)),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(system, size: 28, color: Colors.white),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoButton extends StatefulWidget {
  final bool compact;
  final VoidCallback onPressed;
  final Color? accent;
  const _GoButton({required this.compact, required this.onPressed, this.accent});

  @override
  State<_GoButton> createState() => _GoButtonState();
}

class _GoButtonState extends State<_GoButton> with SingleTickerProviderStateMixin {
  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  bool _pressing = false;

  @override
  void dispose() { _breathe.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breathe,
      builder: (_, __) {
        final s = 1.0 + 0.03 * (_breathe.value * 2 - 1);
        final scale = _pressing ? 0.95 : s;
        return Transform.scale(
          scale: scale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (widget.accent ?? Colors.white).withOpacity(0.65),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  side: BorderSide(color: (widget.accent ?? Colors.white).withOpacity(0.65), width: 1.2),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 42 : 76,
                    vertical: widget.compact ? 0 : 8,
                  ),
                  elevation: 14,
                  shadowColor: (widget.accent ?? Colors.black45).withOpacity(0.6),
                ),
                onPressed: () async {
                  setState(()=> _pressing = true);
                  await Future.delayed(const Duration(milliseconds: 200));
                  setState(()=> _pressing = false);
                  widget.onPressed();
                },
                child: const Text(
                  "GO!!!",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CountdownOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const _CountdownOverlay({required this.onDone});

  @override
  State<_CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<_CountdownOverlay> {
  int counter = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (counter > 1) {
        setState(()=> counter -= 1);
      } else {
        t.cancel();
        widget.onDone();
      }
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        alignment: Alignment.center,
        child: Text(
          "$counter",
          style: const TextStyle(color: Colors.white, fontSize: 100, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
