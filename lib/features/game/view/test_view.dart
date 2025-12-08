import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../firebase_options.dart';
import 'package:sensory_safari_flutter/services/identity_service.dart';

import 'content_view.dart' show SensorySafariSettings;
import 'end_screen.dart';
import '../utils/difficulty_utils.dart';

class TestViewPage extends StatefulWidget {
  const TestViewPage({super.key});

  @override
  State<TestViewPage> createState() => _TestViewPageState();
}

class _TestViewPageState extends State<TestViewPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  // ===== settings (singleton you already have)
  final ss = SensorySafariSettings.I;

  // ===== constants (match Swift)
  static const double kBaseAnimalSize = 180;
  double _animalSize = kBaseAnimalSize; // dynamically scales by screen size per trial
  static const animalNames = ["turtle", "cat", "elephant", "monkey"];
  static const List<String> _petFeedbackImages = [
    'assets/Feedback_Image1.jpg',
    'assets/Feedback_Image2.jpg',
    'assets/Feedback_Image3.jpg',
    'assets/Feedback_Image4.jpg',
    'assets/Feedback_Image5.jpg',
    'assets/Feedback_Image6.jpg',
    'assets/Feedback_Image7.jpg',
    'assets/Feedback_Image8.jpg',
  ];
  final math.Random _rng = math.Random();
  int _lastPetIdx = -1;
  String? _currentPetImage;
  bool _petImagesPrecached = false;
  double _effectiveSpeedMultiplier = 1.0;
  double _loggedSpeedMultiplier = 1.0;
  String _thisTrialDifficultyKey = 'easy';

  // ===== game state
  int trial = 0;
  int score = 0;
  bool trialActive = false;
  bool movedRight = true;
  bool hasResponded = false;

  // ===== Adaptive engine state (Up-only policy by default)
  // Policy A: Up-only, promote after K consecutive correct, never demote, cap at 3, Tmin >= 15
  static const int _adaptiveK = 4;
  static const int _adaptiveTmin = 15;
  int _adaptiveLevel = 0;     // 0..3
  int _streakUp = 0;          // consecutive correct
  // Angles (deg) for Adaptive levels: Easy=0°, Medium=45°, Difficult=67.5°, Very Difficult=75°
  static const List<double> _adaptiveAnglesDeg = [0.0, 45.0, 67.5, 75.0];
  // Per-trial snapshot for logging
  int _thisTrialLevel = 0;
  double _thisTrialAngleDeg = 15.0;
  String _thisTrialCorner = 'TL-BR';
  double _thisTrialSpacingPx = 0.0;
  double _thisTrialLaneLenPx = 0.0;

  // per-session aggregates and logs
  int correctGuessRight = 0,
      inCorrectGuessRight = 0,
      correctGuessLeft = 0,
      inCorrectGuessLeft = 0,
      missedGuess = 0;
  int totalCorrectThisSession = 0;
  final List<Map<String, dynamic>> trialDetails = [];
  DateTime? _trialStart;

  // herd
  final List<_Mover> herd = [];
  Timer? _missTimer;
  Timer? _postDeadlineWatchdog; // guarantees a miss even if culling never empties

  // frame ticker
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  // spawn grid (constant spacing)
  DateTime? _deadline;      // when stimulus ends (no more animals on screen after this)
  DateTime? _spawnEnd;      // last time we are allowed to spawn; chosen so last spawn exits exactly at _deadline
  DateTime? _nextSpawn;     // next scheduled spawn on the grid
  double _vx = 0, _vy = 0;
  double _startX = 0, _startY = 0;
  double _spawnDt = 0;
  double _rotAngle = 0; // radians: rotation applied to each animal to match travel angle

  bool _pausedByLifecycle = false;

  // feedback
  _Outcome? _flash;

  // orientation pause overlay (optional; you already have RotateGate before this)
  final bool _pausedByPortrait = false;

  // ===== sound (mirrors index.html logic)
  late final AudioPlayer _beep;
  Timer? _soundStartDelay;   // ~400 ms start delay
  Timer? _soundStopPrimary;  // ~60% of stim
  Timer? _soundStopBackup;   // ~66% of stim (failsafe)
  bool _soundArmed = false;  // only start if trial still active

  // ===== lights (corner bulbs, no background cycling)
  final List<_Bulb> _bulbs = [];
  final List<Timer> _bulbTimers = [];
  Timer? _lightsStopTimer;

  // Lights visuals — scale with screen/animal size
  double get _bulbSizePx => (_animalSize * 0.16).clamp(14.0, 36.0);
  double get _bulbStepPx => _bulbSizePx * 0.93; // keep grid compact
  double get _bulbBlur    => _bulbSizePx * 0.64;
  double get _bulbSpread  => _bulbSizePx * 0.11;

  // Toggle comes from settings; fall back to false if missing
  bool get _lightsOn {
    try {
      final dynamic any = ss; // access optional settings field dynamically
      return any.lightsOn == true;
    } catch (_) {
      return false;
    }
  }

  void _precachePetImages() {
    if (_petImagesPrecached) {
      return;
    }
    for (final asset in _petFeedbackImages) {
      precacheImage(AssetImage(asset), context);
    }
    _petImagesPrecached = true;
  }

  Future<void> _ensureFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        debugPrint('[TestView] Firebase.initializeApp() done');
      }
    } catch (e) {
      debugPrint('[TestView] Firebase init error: $e');
    }
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
        debugPrint('[TestView] Anonymous auth OK: ${auth.currentUser?.uid}');
      }
    } catch (e) {
      debugPrint('[TestView] Anonymous auth failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
    _beep = AudioPlayer();
    _beep.setReleaseMode(ReleaseMode.loop);
    // start after first layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precachePetImages();
      _startNextTrial();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _missTimer?.cancel();
    _cancelSoundTimers();

    _lightsStopTimer?.cancel();
    for (final t in _bulbTimers) { t.cancel(); }
    _bulbTimers.clear();
    _bulbs.clear();

    _beep.stop();
    _beep.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _pausedByLifecycle = state != AppLifecycleState.resumed;
  }

  // ===== per-frame update
  void _onTick(Duration now) {
    if (_last == Duration.zero) { _last = now; return; }
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;

    if (_pausedByLifecycle || _pausedByPortrait) {
      return;
    }
    if (herd.isEmpty && !(trialActive && _deadline != null)) {
      return;
    }

    final size = MediaQuery.of(context).size;
    final w = size.width, h = size.height;

    // move
    for (final m in herd) { m.x += m.vx * dt; m.y += m.vy * dt; }
    // cull
    final double margin = _animalSize * 1.2;
    herd.removeWhere((m) => m.x < -margin || m.x > w + margin || m.y < -margin || m.y > h + margin);

    // frame-driven spawns (strict grid) until last-allowed spawn time
    if (trialActive && !hasResponded && _spawnEnd != null && _spawnDt > 0 && _nextSpawn != null && DateTime.now().isBefore(_spawnEnd!)) {
      final nowTime = DateTime.now();
      // We only spawn while we are BEFORE _spawnEnd
      if (nowTime.isBefore(_spawnEnd!)) {
        // Emit all due spawns up to min(now, _spawnEnd)
        final cap = nowTime.isBefore(_spawnEnd!) ? nowTime : _spawnEnd!;
        while (_nextSpawn!.isBefore(cap)) {
          _spawnOne(distractor: false);
          _nextSpawn = _nextSpawn!.add(Duration(milliseconds: (_spawnDt * 1000).round()));
        }
      }
    }
    // Grace period after animals leave screen post-stimulus
    else if (trialActive && !hasResponded && _deadline != null) {
      final afterDeadline = DateTime.now().isAfter(_deadline!);
      if (afterDeadline && herd.isEmpty) {
        _missTimer ??= Timer(const Duration(milliseconds: 1000), () {
          if (!mounted) return;
          if (trialActive && !hasResponded && herd.isEmpty) {
            _finishTrial(_Outcome.miss);
          }
        });
      } else {
        _missTimer?.cancel();
        _missTimer = null;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  // Returns the path/tilt angle (radians) for the current difficulty.
  double _angleForDifficultyRad() {
    final idx = ss.selectedDifficulty.clamp(0, 3);
    // Fixed difficulties: Easy=0°, Medium=45°, Difficult=67.5°, Very Difficult=75°
    const deg = [0.0, 45.0, 67.5, 75.0];
    return deg[idx] * math.pi / 180.0;
  }

  String _difficultyName() {
    return displayDifficultyName(_thisTrialDifficultyKey);
  }

  // NEW: constant along-path speed based on Medium (45° crossing in ~5s)
  // Constant along-path speed used for every level and any stimulus duration.
  // Calibrated to: at 45° (medium), the stream takes ~5s to cross the screen.
  static const double _kMediumCrossSec = 5.0;
  double _constantPathSpeed(Size size) {
    final w = size.width;
    final travelX = w + 2 * _animalSize; // include offscreen margin so entry/exit look identical
    const angleMediumRad = 45 * math.pi / 180.0;
    final pathLenMedium = travelX / math.cos(angleMediumRad).abs().clamp(0.001, 1.0);
    return pathLenMedium / _kMediumCrossSec; // px/sec
  }

  // NEW: resolve user-selected animal name
  String _selectedAnimalName() {
    final idx = ss.selectedAnimal % animalNames.length;
    return animalNames[idx];
  }

  // ===== trial flow
  void _startNextTrial() {
    // Ensure no timers/state leak from previous trial
    _missTimer?.cancel();
    _missTimer = null;
    _postDeadlineWatchdog?.cancel();
    _postDeadlineWatchdog = null;
    _cancelSoundTimers();
    _deadline = null;
    _spawnEnd = null;
    _nextSpawn = null;
    _currentPetImage = null;
    _flash = null;
    _effectiveSpeedMultiplier = 1.0;
    _loggedSpeedMultiplier = 1.0;
    _thisTrialDifficultyKey = 'easy';

    final bool adaptive = ss.adaptiveEnabled == true;
    final total = adaptive ? math.max(ss.numTries.toInt(), _adaptiveTmin) : ss.numTries.toInt();
    if (trial >= total) {
      _endAll();
      return;
    }
    trialActive = true;
    hasResponded = false;
    movedRight = math.Random().nextBool(); // randomize L->R or R->L each trial
    herd.clear();
    if (trial == 0) {
      // reset counters at the start of a session
      correctGuessRight = 0;
      inCorrectGuessRight = 0;
      correctGuessLeft = 0;
      inCorrectGuessLeft = 0;
      missedGuess = 0;
      totalCorrectThisSession = 0;
      trialDetails.clear();
      // reset adaptive state
      _adaptiveLevel = 0;
      _streakUp = 0;
    }

    // kinematics from difficulty (0/45/67.5/75 degrees), cross full screen in stim seconds
    final baseAngle = adaptive
        ? (_adaptiveAnglesDeg[_adaptiveLevel.clamp(0, 3)] * math.pi / 180.0)
        : _angleForDifficultyRad();

    // If the base angle is ~0°, force pure horizontal motion with no tilt.
    final bool isHorizontal = baseAngle.abs() < 1e-6;
    final double tiltSign = isHorizontal ? 1.0 : (math.Random().nextBool() ? 1.0 : -1.0);
    final double angle = baseAngle * tiltSign;

    _thisTrialAngleDeg = (baseAngle * 180.0 / math.pi).abs();
    _thisTrialLevel = adaptive ? _adaptiveLevel : ss.selectedDifficulty.clamp(0, 3);
    _thisTrialDifficultyKey = adaptive
        ? adaptiveKeyForLevel(_thisTrialLevel)
        : difficultyKeyForIndex(_thisTrialLevel);
    _thisTrialCorner = isHorizontal
        ? (movedRight ? 'L-R' : 'R-L')
        : (tiltSign > 0 ? 'TL-BR' : 'TR-BL');

    // Declare dir before any use (for logs and kinematics)
    final dir = movedRight ? 1.0 : -1.0;
    debugPrint('[Lane] angle=${(angle * 180 / math.pi).toStringAsFixed(1)}°, dir=${dir > 0 ? 'L→R' : 'R→L'}');

    final size = MediaQuery.of(context).size;
    final w = size.width, h = size.height;
    // Dynamic sprite size based on short side, with a higher cap on tablets
    final shortSide = math.min(w, h);
    final bool isTablet = shortSide >= 700; // rough heuristic (iPad mini short side is 744)
    final double maxCap = isTablet ? 320.0 : 220.0;
    _animalSize = (shortSide * 0.46).clamp(120.0, maxCap);

    final stimSec = ss.stimDuration.clamp(0.01, 60).toDouble();

    // Geometry for the current angle
    final double angleCurrent = angle;

    // Horizontal span including offscreen margins
    final double kEdgeMargin = _animalSize; // start fully offscreen
    final double travelX = w + 2 * kEdgeMargin;

    // Path length terms
    final double cosAabs = math.cos(angleCurrent).abs().clamp(0.001, 1.0);
    // Visible on-screen diagonal length (do not include offscreen margins)
    final double pathLenVisible = w / cosAabs;
    // Full path including offscreen margins (for logs/diagnostics)
    final double pathLenCurrent = travelX / cosAabs;
    _thisTrialLaneLenPx = pathLenVisible;

    // Base speed tuned for medium difficulty (~5s cross time on iPad), scaled by difficulty & adaptive slider
    final double basePathSpeed = _constantPathSpeed(size);
    double effectiveMultiplier = getDifficultySpeedMultiplier(_thisTrialDifficultyKey);
    if (adaptive) {
      final double rawSlider = (ss.adaptiveSpeedMultiplier.isFinite && !ss.adaptiveSpeedMultiplier.isNaN)
          ? ss.adaptiveSpeedMultiplier
          : 1.0;
      effectiveMultiplier = composeAdaptiveMultiplier(
        level: _thisTrialLevel,
        sliderMultiplier: rawSlider,
      );
    }
    _effectiveSpeedMultiplier = effectiveMultiplier;
    _loggedSpeedMultiplier = (_effectiveSpeedMultiplier * 100).roundToDouble() / 100.0;
    final double speed = basePathSpeed * _effectiveSpeedMultiplier;

    // Velocity components for the current lane
    _vx = speed * math.cos(angleCurrent) * dir;
    _vy = speed * math.sin(angleCurrent) * dir;

    // Actual time to traverse the current diagonal across the screen
    final double crossSec = pathLenVisible / speed; // equals stimSec in fixed mode

    // Sprite orientation: keep upright for all modes (do not rotate the animal sprite)
    _rotAngle = 0.0;

    // Force lane through screen center (identical feel both ways)
    final centerX = w / 2, centerY = h / 2;
    final edgeMargin = _animalSize;
    _startX = dir > 0 ? (-edgeMargin) : (w + edgeMargin);
    final slope = math.tan(angle);
    _startY = centerY - slope * (centerX - _startX);

    // constant spacing (along path); do not tighten for adaptive levels
    final bool isDifficult = _thisTrialDifficultyKey == 'hard';
    final spacingBase = adaptive ? 0.75 : (isDifficult ? 0.70 : 0.75);
    final spacing = (_animalSize * spacingBase).clamp(40, w * 0.18);
    // Spawn cadence depends only on path speed & spacing (never tie to stimSec)
    _spawnDt = spacing / speed;
    _thisTrialSpacingPx = spacing.toDouble();

    // seed visible animals at t=now on one global grid
    final cosA = math.cos(angle).abs().clamp(0.0001, 1.0);
    final visibleEdgeX = dir > 0 ? (0 + _animalSize / 2) : (w - _animalSize / 2);
    final dRef = (visibleEdgeX - _startX).abs() / cosA;

    // declare `now` before any use and reuse it
    final now = DateTime.now();
    _trialStart = now;

    // align the global spawn grid (cadence matches both directions)
    var base = now.subtract(Duration(milliseconds: (dRef / speed * 1000).round()));
    while (base.isBefore(now)) {
      base = base.add(Duration(milliseconds: (_spawnDt * 1000).round()));
    }
    _nextSpawn = base;

    // precompute range for initial visible herd
    final minX = -edgeMargin, maxX = w + edgeMargin;
    final dMin = ((minX - _startX) / (dir * cosA)).abs();
    final dMax = ((maxX - _startX) / (dir * cosA)).abs();
    final lo = math.min(dMin, dMax), hi = math.max(dMin, dMax);

    // indices for initial visible herd
    final iMin = ((dRef - hi) / spacing).ceil();
    final iMax = ((dRef - lo) / spacing).floor();

    for (int i = iMin; i <= iMax; i++) {
      final d = dRef - i * spacing;
      if (d < 0) continue;
      herd.add(_Mover(
        name: _pickAnimal(),
        x: _startX + dir * d * math.cos(angle),
        y: _startY + dir * d * math.sin(angle),
        vx: _vx, vy: _vy,
      ));
    }

    // Arm deadline for the stimulus window
    _deadline = now.add(Duration(milliseconds: (stimSec * 1000).round()));

    // Spawn policy: allow spawns until the stimulus window ends.
    // Animals spawned near the end may finish after the deadline; watchdog handles timeout feedback.
    _spawnEnd = _deadline;

    _missTimer?.cancel();
    // Post-deadline watchdog: guarantees a miss feedback even if herd never fully clears
    _postDeadlineWatchdog?.cancel();
    _postDeadlineWatchdog = Timer(
      Duration(milliseconds: (stimSec * 1000).round() + 1800), // ~1.8s after stimulus end
      () {
        if (!mounted) return;
        if (trialActive && !hasResponded) {
          _finishTrial(_Outcome.miss);
        }
      },
    );

    // Sound: start after ~400ms; auto-stop ~60–66% of stimulus
    _armSoundForTrial();
    _armLightsForTrial();

    setState(() {});
  }

  void _applyAdaptiveAfterTrial({required bool correct}) {
    if (ss.adaptiveEnabled != true) return;
    if (correct) {
      _streakUp += 1;
      if (_streakUp >= _adaptiveK) {
        _adaptiveLevel = (_adaptiveLevel + 1).clamp(0, 3);
        _streakUp = 0; // reset after promotion
      }
    } else {
      _streakUp = 0; // Up-only policy: just reset upward streak
    }
  }

  void _spawnOne({bool distractor = false}) {
    final a = _Mover(
      name: _pickAnimal(distractor: distractor),
      x: _startX, y: _startY, vx: _vx, vy: _vy,
    );
    herd.add(a);
  }

  void _showNegativeFeedback() {
    missedGuess++;
    trialDetails.add({
      'trial': trial + 1,
      'timestamp': DateTime.now().toIso8601String(),
      'difficulty': displayDifficultyName(_thisTrialDifficultyKey),
      'mode': ss.adaptiveEnabled ? 'adaptive' : 'fixed',
      'level': ss.adaptiveEnabled ? _thisTrialLevel : ss.selectedDifficulty.clamp(0, 3),
      'angleDeg': _thisTrialAngleDeg,
      'corner': _thisTrialCorner,
      'goesRight': movedRight,
      'stimulusType': 'visual',
      'indicatorLightOn': _lightsOn,
      'indicatorSoundOn': ss.soundOn,
      'selectedAnimal': _selectedAnimalName(),
      'expectedSide': movedRight ? 'right' : 'left',
      'responseSide': null,
      'correct': false,
      'latency': null,
      'speedMultiplier': _loggedSpeedMultiplier,
      'spacingPx': _thisTrialSpacingPx,
      'laneLengthPx': _thisTrialLaneLenPx,
      'spriteW': _animalSize,
      'spriteH': _animalSize,
    });
    _applyAdaptiveAfterTrial(correct: false);
    _currentPetImage = null;
    _flash = _Outcome.miss;
    HapticFeedback.heavyImpact();
    setState(() {});
  }

  String? _pickPetFeedbackImage() {
    if (_petFeedbackImages.isEmpty) {
      return null;
    }
    var idx = _rng.nextInt(_petFeedbackImages.length);
    if (_petFeedbackImages.length > 1 && idx == _lastPetIdx) {
      idx = (idx + 1) % _petFeedbackImages.length;
    }
    _lastPetIdx = idx;
    return _petFeedbackImages[idx];
  }

  void _showPositiveFeedbackImage(String asset) {
    _currentPetImage = asset;
    _flash = _Outcome.correct;
  }

  void _finishTrial(_Outcome outcome) {
    _stopSoundImmediate();
    if (!trialActive) return;
    final bool wasResponded = hasResponded;
    trialActive = false;
    hasResponded = true;
    _missTimer?.cancel();
    _missTimer = null;
    _postDeadlineWatchdog?.cancel();
    _postDeadlineWatchdog = null;
    _deadline = null;
    _nextSpawn = null;

    bool handledMiss = false;
    if (outcome == _Outcome.miss && !wasResponded) {
      handledMiss = true;
      _showNegativeFeedback();
    }

    if (outcome == _Outcome.correct) {
      score += 1;
      HapticFeedback.mediumImpact();
      final petSrc = _pickPetFeedbackImage();
      if (petSrc != null) {
        _showPositiveFeedbackImage(petSrc);
      } else {
        _currentPetImage = null;
        _flash = _Outcome.correct;
      }
    } else if (outcome != _Outcome.miss) {
      HapticFeedback.heavyImpact();
      _currentPetImage = null;
      _flash = outcome;
    }

    if (!handledMiss) {
      setState(() {});
    }

    // dwell then advance (guard against invalid/negative values)
    final double rawDwell = ss.outcomeDuration;
    final double safeDwellSec = (rawDwell.isFinite && rawDwell >= 0) ? rawDwell : 1.5;
    final Duration dwell = Duration(milliseconds: (safeDwellSec * 1000).round());
    Future.delayed(dwell, () {
      if (!mounted) {
        return;
      }
      _flash = null;
      herd.clear();
      trial += 1;
      _startNextTrial();
    });
  }

  Future<void> _endAll() async {
    _missTimer?.cancel();
    _deadline = null;
    _nextSpawn = null;
    _ticker.stop();
    await _stopSoundImmediate();

    try {
      _logSessionToFirestore()
          .timeout(const Duration(seconds: 3))
          .then((_) => debugPrint('[TestView] Session logged'))
          .catchError((e) => debugPrint('[TestView] Session logging failed or timed out: $e'));
    } catch (e) {
      debugPrint('[TestView] Session logging threw synchronously: $e');
    }

    final int total = ss.numTries.toInt();
    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EndScreen(
            totalTrials: total,
            score: score,
            onRestart: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const TestViewPage()),
              );
            },
            onViewOverallScore: () {
              Navigator.of(context).pushNamed('/overall-score');
            },
            onFeedbackForm: () {
              Navigator.of(context).pushNamed('/feedback');
            },
          ),
        ),
      );
    });
  }

  double _normInv(double p) {
    // Port of the JS norminv() the app uses for the final metric.
    // Note: this is NOT a true inverse normal; it mirrors the provided JS exactly.
    if (p == 0) p = 0.1; // Prevent zero input
    const a1 = -39.69683028665376;
    const a2 = 220.9460984245205;
    const a3 = -275.9285104469687;
    const a4 = 138.357751867269;
    const a5 = -30.66479806614716;
    final t = 1.0 / (1.0 + 0.2316419 * p.abs());
    final d = 0.3989422804014337 * math.exp(-(p * p) / 2.0);
    final x = ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t;
    return 1 - d * x;
  }

  Future<void> _logSessionToFirestore() async {
    await _ensureFirebase();

    // Ensure we have a user id (login name or persistent anonymous id)
    final String userId = await IdentityService.resolve();
    debugPrint('[TestView] Target collection: users/$userId/sessions');

    final int totalTrials = ss.numTries.toInt();
    final int totalCorrect = score; // store exactly what the UI showed

    // FracHit and FracCR
    final double denomHit = (correctGuessRight + inCorrectGuessRight + missedGuess / 2.0).toDouble();
    final double denomCR  = (inCorrectGuessLeft + correctGuessLeft + missedGuess / 2.0).toDouble();
    final double fractHit = denomHit > 0 ? (correctGuessRight / denomHit) : 0.0;
    final double fractCR  = denomCR  > 0 ? (inCorrectGuessLeft / denomCR)  : 0.0;

    // JS-equivalent metric calculation
    final dp1 = _normInv(fractHit);
    final dp2 = _normInv(fractCR);
    final String metricScore = (dp1 - dp2).toStringAsFixed(3);

    final sessionData = <String, dynamic>{
      'playerName': userId,
      'timestamp': DateTime.now().toIso8601String(),
      'difficulty': _difficultyName(),
      'stimulusDuration': ss.stimDuration.round(),
      'outcomeDuration': ss.outcomeDuration.round(),
      'numTrials': totalTrials,
      'score': '$totalCorrect / $totalTrials',
      'selectedAnimal': _selectedAnimalName(),
      'stimulusType': 'visual',
      'indicatorLightOn': _lightsOn,
      'lightsOn': _lightsOn,
      'indicatorSoundOn': ss.soundOn,
      'soundOn': ss.soundOn,
      'trialDetails': trialDetails,
      // explicit aggregates
      'correctGuessLeft': correctGuessLeft,
      'correctGuessRight': correctGuessRight,
      'inCorrectGuessLeft': inCorrectGuessLeft,
      'inCorrectGuessRight': inCorrectGuessRight,
      'leftCorrect': correctGuessLeft,
      'rightCorrect': correctGuessRight,
      'leftIncorrect': inCorrectGuessLeft,
      'rightIncorrect': inCorrectGuessRight,
      'missed': missedGuess,
      'missedGuess': missedGuess,
      'metricScore': metricScore,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);

    // Make these visible to both transaction and fallback so the debugPrint can reference them
    String? lastDocId;
    String? docId;

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        int current = 0;
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>;
          final v = data['sessionCount'];
          if (v is int) {
            current = v;
          } else if (v is num) {
            current = v.toInt();
          }
        }
        final newCount = current + 1;
        final docId = 'Game #$newCount';

        final Map<String, dynamic> toWrite = Map<String, dynamic>.from(sessionData)
          ..addAll({'gameId': docId, 'gameNumber': newCount});

        // write session doc once
        tx.set(userRef.collection('sessions').doc(docId), toWrite);

        // fix: proper map with keys; update user doc
        tx.set(userRef, {
          'sessionCount': newCount,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        lastDocId = docId;
      });

      if (lastDocId != null) {
        debugPrint('[TestView] Stored session at users/$userId/sessions/$lastDocId (trials=${trialDetails.length})');
      }
      // Requested log
      debugPrint('[TestView] WROTE session doc under users/$userId/sessions: ${lastDocId ?? docId}');
    } catch (e) {
      debugPrint('[TestView] Firestore write failed: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission') || msg.contains('insufficient')) {
        debugPrint('[TestView] Hint: enable Anonymous Auth or sign in; and allow writes to users/{userId}/sessions in rules.');
      }
      try {
        int current = 0;
        final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
        final userSnap = await userRef.get();
        if (userSnap.exists) {
          final data = userSnap.data() as Map<String, dynamic>;
          final v = data['sessionCount'];
          if (v is int) {
            current = v;
          } else if (v is num) {
            current = v.toInt();
          }
        }
        final newCount = current + 1;
        final String docId = 'Game #$newCount';
        final Map<String, dynamic> toWrite = Map<String, dynamic>.from(sessionData)
          ..addAll({'gameId': docId, 'gameNumber': newCount});
        await userRef.collection('sessions').doc(docId).set(toWrite);
        await userRef.set({
          'sessionCount': newCount,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[TestView] Fallback session stored at users/$userId/sessions/$docId');
        // Requested log
        debugPrint('[TestView] WROTE session doc under users/$userId/sessions: ${lastDocId ?? docId}');
      } catch (e2) {
        debugPrint('[TestView] Fallback write also failed: $e2');
      }
    }
  }

  String _pickAnimal({bool distractor = false}) {
    final base = ss.selectedAnimal % animalNames.length;
    return distractor ? animalNames[(base + 1) % animalNames.length] : animalNames[base];
  }

  void _cancelSoundTimers() {
    _soundStartDelay?.cancel();  _soundStartDelay = null;
    _soundStopPrimary?.cancel(); _soundStopPrimary = null;
    _soundStopBackup?.cancel();  _soundStopBackup = null;
  }

  Future<void> _stopSoundImmediate() async {
    _soundArmed = false;
    _cancelSoundTimers();
    try {
      await _beep.stop();
    } catch (e) {
      debugPrint('[Sound] stop error: $e');
    }
  }

  void _armSoundForTrial() {
    if (!ss.soundOn) {
      return;
    }
    _soundArmed = true;
    _cancelSoundTimers();

    // 1) Prep + delayed start (~400 ms)
    _soundStartDelay = Timer(const Duration(milliseconds: 400), () async {
      if (!_soundArmed || !trialActive) {
        return;
      }
      try {
        await _beep.setVolume(1.0);
        await _beep.stop(); // fresh start
        await _beep.play(AssetSource('beep.wav'));
      } catch (e) {
        debugPrint('[Sound] start error: $e');
      }
    });

    // 2) Auto-stops at 60% and 66% of stimulus window
    final int stimMs = (ss.stimDuration * 1000).round();
    _soundStopPrimary = Timer(Duration(milliseconds: (stimMs * 0.6).round() + 400), _stopSoundImmediate);
    _soundStopBackup  = Timer(Duration(milliseconds: (stimMs * 0.66).round() + 400), _stopSoundImmediate);
  }

  // ===== lights helpers =====
  void _clearLights() {
    _lightsStopTimer?.cancel();
    _lightsStopTimer = null;
    for (final t in _bulbTimers) { t.cancel(); }
    _bulbTimers.clear();
    if (_bulbs.isNotEmpty) {
      _bulbs.clear();
      if (mounted) setState(() {});
    }
  }

  void _flickerBulb(_Bulb b, List<Color> palette) {
    final ms = 500 + math.Random().nextInt(200);
    final timer = Timer(Duration(milliseconds: ms), () {
      if (!mounted || !_bulbs.contains(b)) {
        return;
      }
      final color = palette[math.Random().nextInt(palette.length)];
      b.color = color;
      setState(() {});
      _flickerBulb(b, palette); // reschedule next random change
    });
    _bulbTimers.add(timer);
  }

  void _armLightsForTrial() {
    _clearLights();
    if (!_lightsOn) return;

    // 4 corners × 2×2 bulbs
    const corners = <_Corner>[
      _Corner(top: 10, left: 10),
      _Corner(top: 10, right: 10),
      _Corner(bottom: 10, left: 10),
      _Corner(bottom: 10, right: 10),
    ];
    const palettes = <List<Color>>[
      [Colors.red, Colors.yellow, Colors.orange],
      [Colors.blue, Colors.cyan, Colors.lightBlueAccent],
      [Colors.green, Colors.lime, Colors.lightGreenAccent],
      [Colors.purple, Colors.pinkAccent, Colors.deepPurpleAccent],
    ];

    for (var i = 0; i < corners.length; i++) {
      final corner = corners[i];
      final palette = palettes[i];
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 2; col++) {
          final b = _Bulb(
            top: corner.top != null ? (corner.top! + row * _bulbStepPx).toDouble() : null,
            bottom: corner.bottom != null ? (corner.bottom! + row * _bulbStepPx).toDouble() : null,
            left: corner.left != null ? (corner.left! + col * _bulbStepPx).toDouble() : null,
            right: corner.right != null ? (corner.right! + col * _bulbStepPx).toDouble() : null,
            color: Colors.yellow,
          );
          _bulbs.add(b);
          _flickerBulb(b, palette);
        }
      }
    }

    // --- Extra: bottom edge marquee bulbs (avoid corner clusters) ---
    try {
      final double screenW = MediaQuery.of(context).size.width;
      const double margin = 10; // same as corner offsets
      final double step = (_bulbStepPx * 1.4);
      final double cornerReserve = _bulbStepPx * 2;
      final double startX = margin + cornerReserve;
      final double endX   = screenW - margin - _bulbSizePx - cornerReserve;

      const List<Color> bottomPalette = [
        Colors.amber,
        Colors.orangeAccent,
        Colors.yellow,
      ];

      if (endX > startX) {
        for (double x = startX; x <= endX; x += step) {
          final b = _Bulb(
            top: null,
            bottom: margin.toDouble(),
            left: x,
            right: null,
            color: Colors.yellow,
          );
          _bulbs.add(b);
          _flickerBulb(b, bottomPalette);
        }
      }
    } catch (_) {}

    // --- Extra: LEFT edge marquee bulbs (avoid corner clusters) ---
    try {
      final double screenH = MediaQuery.of(context).size.height;
      const double margin = 10; // same as corner offsets
      final double stepY = (_bulbStepPx * 1.4);
      final double cornerReserve = _bulbStepPx * 2;
      final double startY = margin + cornerReserve;
      final double endY   = screenH - margin - _bulbSizePx - cornerReserve;

      const List<Color> leftPalette = [
        Colors.cyan,
        Colors.lightBlueAccent,
        Colors.blueAccent,
      ];

      if (endY > startY) {
        for (double y = startY; y <= endY; y += stepY) {
          final b = _Bulb(
            top: y,
            bottom: null,
            left: margin.toDouble(),
            right: null,
            color: Colors.lightBlueAccent,
          );
          _bulbs.add(b);
          _flickerBulb(b, leftPalette);
        }
      }
    } catch (_) {}

    // --- Extra: RIGHT edge marquee bulbs (avoid corner clusters) ---
    try {
      final double screenH = MediaQuery.of(context).size.height;
      const double margin = 10; // same as corner offsets
      final double stepY = (_bulbStepPx * 1.4);
      final double cornerReserve = _bulbStepPx * 2;
      final double startY = margin + cornerReserve;
      final double endY   = screenH - margin - _bulbSizePx - cornerReserve;

      const List<Color> rightPalette = [
        Colors.pinkAccent,
        Colors.deepPurpleAccent,
        Colors.purpleAccent,
      ];

      if (endY > startY) {
        for (double y = startY; y <= endY; y += stepY) {
          final b = _Bulb(
            top: y,
            bottom: null,
            left: null,
            right: margin.toDouble(),
            color: Colors.pinkAccent,
          );
          _bulbs.add(b);
          _flickerBulb(b, rightPalette);
        }
      }
    } catch (_) {}

    // Stop bulbs at 60% of the stimulus window
    final stimMs = (ss.stimDuration * 1000).round();
    _lightsStopTimer = Timer(
      Duration(milliseconds: (stimMs * 0.6).round()),
      _clearLights,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;

    final safeTop = MediaQuery.of(context).padding.top;
    final shortSideForHud = math.min(size.width, size.height);
    final double hudScale = (shortSideForHud / 700.0).clamp(0.75, 1.25);
    final double hudPadTop = 16.0 * hudScale;        // from the HUD Padding(top)
    final double hudApproxHeight = 48.0 * hudScale;  // chip capsule approx height (scaled)
    final double hudBuffer = 8.0 * hudScale;         // cushion so sprites don't touch the HUD
    final double clipTop = safeTop + hudPadTop + hudApproxHeight + hudBuffer;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/Background.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // tap gesture (left/right) — placed below HUD so it doesn't block buttons
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                if (!trialActive || hasResponded) {
                  return;
                }
                HapticFeedback.lightImpact();
              },
              onTapUp: (d) {
                if (!trialActive || hasResponded) {
                  return;
                }
                hasResponded = true;
                final tappedRight = d.localPosition.dx > w / 2; // right half vs left half
                final correct = (tappedRight == movedRight);

                // latency in seconds from trial start
                final double latencySec = _trialStart != null
                    ? DateTime.now().difference(_trialStart!).inMilliseconds / 1000.0
                    : 0.0;

                // Rich per-trial logging
                trialDetails.add({
                  'trial': trial + 1,
                  'timestamp': DateTime.now().toIso8601String(),
                  'difficulty': _difficultyName(),
                  'mode': ss.adaptiveEnabled ? 'adaptive' : 'fixed',
                  'level': ss.adaptiveEnabled ? _thisTrialLevel : ss.selectedDifficulty.clamp(0, 3),
                  'angleDeg': _thisTrialAngleDeg,
                  'corner': _thisTrialCorner,
                  'goesRight': movedRight,
                  'stimulusType': 'visual',
                  'indicatorLightOn': _lightsOn,
                  'indicatorSoundOn': ss.soundOn,
                  'selectedAnimal': _selectedAnimalName(),
                  'expectedSide': movedRight ? 'right' : 'left',
                  'responseSide': tappedRight ? 'right' : 'left',
                  'correct': correct,
                  'latency': latencySec,
                  'speedMultiplier': _loggedSpeedMultiplier,
                  'spacingPx': _thisTrialSpacingPx,
                  'laneLengthPx': _thisTrialLaneLenPx,
                  'spriteW': _animalSize,
                  'spriteH': _animalSize,
                });

                // Update aggregates
                if (movedRight) {
                  if (correct) {
                    correctGuessRight++;
                  } else {
                    inCorrectGuessRight++;
                  }
                } else {
                  if (correct) {
                    correctGuessLeft++;
                  } else {
                    inCorrectGuessLeft++;
                  }
                }
                if (correct) totalCorrectThisSession++;
                _applyAdaptiveAfterTrial(correct: correct);
                _finishTrial(correct ? _Outcome.correct : _Outcome.wrong);
              },
            ),
          ),

          // HUD (top anchored)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, hudPadTop, 16, 0),
                child: Row(
                  children: [
                    // In adaptive mode, denominator is at least 15
                    (() {
                      final int denom = (ss.adaptiveEnabled == true && ss.numTries < 15)
                          ? 15
                          : ss.numTries.toInt();
                      final int num = math.min(trial + 1, denom);
                      return _chip('Trial', '$num/$denom', Colors.yellow);
                    })(),
                    const SizedBox(width: 10),
                    _chip('Score', '$score', Colors.orange),
                    const Spacer(),
                    _exitButton(),
                  ],
                ),
              ),
            ),
          ),

          // animals (hidden while feedback is visible) — clipped below HUD
          if (_flash == null)
            ClipPath(
              clipper: _TopRectClipper(clipTop),
              child: Stack(
                children: [
                  for (final m in herd)
                    Positioned(
                      left: m.x - _animalSize / 2,
                      top: m.y - _animalSize / 2,
                      width: _animalSize,
                      height: _animalSize,
                      child: IgnorePointer(
                        child: Transform.rotate(
                          angle: _rotAngle, // orientation stays constant; do not multiply by dir or add pi
                          child: Image.asset('assets/${m.name}.png', fit: BoxFit.contain),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // lights bulbs overlay (corner distractor; no background cycling)
          ..._bulbs.map((b) => Positioned(
                top: b.top,
                bottom: b.bottom,
                left: b.left,
                right: b.right,
                width: _bulbSizePx,
                height: _bulbSizePx,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: b.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: b.color.withOpacity(1.0),
                          blurRadius: _bulbBlur,
                          spreadRadius: _bulbSpread,
                          offset: const Offset(0, 0),
                        ),
                        BoxShadow(
                          color: b.color.withOpacity(0.7),
                          blurRadius: _bulbBlur * 1.8,
                          spreadRadius: _bulbSpread * 1.5,
                          offset: const Offset(0, 0),
                        ),
                      ],
                    ),
                  ),
                ),
              )),

          // feedback
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            reverseDuration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: _flash != null
                ? SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _buildFeedbackOverlay(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
    );
  }

  // ===== UI bits
  Widget _chip(String title, String value, Color valueColor) {
    final size = MediaQuery.of(context).size;
    final shortSide = math.min(size.width, size.height);
    final s = (shortSide / 700.0).clamp(0.75, 1.25);
    final padH = 14.0 * s, padV = 10.0 * s;
    final radius = 16.0 * s;
    final blur = 6.0 * s;
    final gap = 8.0 * s;
    final titleSize = 12.0 * s;
    final valueSize = 14.0 * s;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: blur, offset: const Offset(0,3))],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title, style: TextStyle(color: Colors.white70, fontSize: titleSize)),
            ),
            SizedBox(width: gap),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(color: valueColor, fontWeight: FontWeight.w700, fontSize: valueSize),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Feedback visuals =====
  Widget _buildFeedbackOverlay() {
    final bool isCorrect = _flash == _Outcome.correct;
    final double size = (_animalSize * 1.15).clamp(140.0, 360.0);
    if (isCorrect) {
      final String asset = _currentPetImage ?? 'assets/${_selectedAnimalName()}.png';
      final Widget image = ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.12),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset('assets/${_selectedAnimalName()}.png', fit: BoxFit.contain),
        ),
      );
      return TweenAnimationBuilder<double>(
        key: ValueKey(asset),
        tween: Tween<double>(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.greenAccent.withOpacity(0.10),
                boxShadow: [
                  BoxShadow(color: Colors.greenAccent.withOpacity(0.55), blurRadius: size * 0.45, spreadRadius: size * 0.06),
                  BoxShadow(color: Colors.greenAccent.withOpacity(0.32), blurRadius: size * 0.25, spreadRadius: size * 0.03),
                ],
              ),
            ),
            SizedBox(width: size, height: size, child: image),
          ],
        ),
      );
    } else {
      return TweenAnimationBuilder<double>(
        key: const ValueKey('negative'),
        tween: Tween<double>(begin: 0.9, end: 1.0),
        duration: const Duration(milliseconds: 180),
        builder: (context, value, child) => Transform.scale(scale: value, child: child),
        child: Icon(
          Icons.cancel,
          size: size,
          color: Colors.redAccent,
        ),
      );
    }
  }

  Widget _exitButton() {
    return ElevatedButton(
      onPressed: () {
        // Replace TestView with ContentView
        Navigator.pushReplacementNamed(context, '/home');
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.withOpacity(0.8),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 6,
      ),
      child: const Text('Exit'),
    );
  }
}

enum _Outcome { correct, wrong, miss }

class _TopRectClipper extends CustomClipper<Path> {
  const _TopRectClipper(this.top);
  final double top;
  @override
  Path getClip(Size size) {
    return Path()..addRect(Rect.fromLTWH(0, top, size.width, math.max(0, size.height - top)));
  }
  @override
  bool shouldReclip(covariant _TopRectClipper oldClipper) => oldClipper.top != top;
}

class _Mover {
  _Mover({required this.name, required this.x, required this.y, required this.vx, required this.vy});
  final String name;
  double x, y, vx, vy;
}

class _Bulb {
  _Bulb({this.top, this.bottom, this.left, this.right, required this.color});
  final double? top, bottom, left, right;
  Color color;
}

class _Corner {
  const _Corner({this.top, this.bottom, this.left, this.right});
  final double? top, bottom, left, right;
}
