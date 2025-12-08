import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensory_safari_flutter/services/identity_service.dart';

import '../utils/difficulty_utils.dart';

// Helper: Extract numeric game index from doc id
int _extractGameNum(String docId) {
  final m = RegExp(r'Game #(\d+)').firstMatch(docId);
  return m != null ? int.parse(m.group(1)!) : 0;
}

/// Mirrors the web page’s overall results:
/// - Reads users/{<playerName or loggedInUser or username or Firebase UID>}/sessions
/// - Sorts by numeric gameNumber / doc id
/// - Shows a chart + table
class OverallResultsPage extends StatefulWidget {
  const OverallResultsPage({super.key});

  @override
  State<OverallResultsPage> createState() => _OverallResultsPageState();
}

class _OverallResultsPageState extends State<OverallResultsPage> {
  late Future<String> _userIdFuture;
  Stream<List<_SessionRow>>? _stream;
  String? _uidForDebug;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _ensureAuth(); // fire-and-forget
    _userIdFuture = _resolveUserId();
    // If the user logs in while this page is open, switch to that identity fast.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) async {
      if (u == null) return;
      // Pull any locally stored username for precedence, then derive best id from auth
      final p = await SharedPreferences.getInstance();
      final local = p.getString('playerName') ?? p.getString('loggedInUser');
      final userId = _bestUserIdFromAuth(u, localPrefName: local);
      if (!mounted) return;
      setState(() {
        _uidForDebug = u.uid;
        _stream = _sessionStream(userId);
        _userIdFuture = Future.value(userId);
      });
    });
  }

  String _bestUserIdFromAuth(User u, {String? localPrefName}) {
    // Preference order: explicit local username > Firebase displayName > email prefix > UID
    final fromPrefs = (localPrefName != null && localPrefName.trim().isNotEmpty)
        ? localPrefName.trim()
        : null;
    if (fromPrefs != null) return fromPrefs;

    final dn = u.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;

    final email = u.email?.trim();
    if (email != null && email.isNotEmpty) {
      final at = email.indexOf('@');
      if (at > 0) return email.substring(0, at);
      return email; // fallback to whole email if no '@'
    }

    return u.uid; // last resort, always present
  }

  // ---- USER RESOLUTION ----

  Future<String?> _guessLocalUsername() async {
    final p = await SharedPreferences.getInstance();
    final candidates = <String?>[
      p.getString('playerName'),
      p.getString('loggedInUser'),
      p.getString('username'),
      p.getString('userName'),
      p.getString('displayName'),
      p.getString('player'),
    ];
    // Also try Firebase displayName if present
    final fbName = FirebaseAuth.instance.currentUser?.displayName;
    if (fbName != null && fbName.trim().isNotEmpty) candidates.add(fbName);
    final first = candidates.firstWhere(
      (s) => s != null && s.trim().isNotEmpty,
      orElse: () => null,
    );
    return first?.trim();
  }

  Future<void> _ensureAuth() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return;
    try {
      await auth.signInAnonymously();
    } catch (e) {
      debugPrint('[Auth] Anonymous sign-in failed: $e');
    }
  }

  Future<String> _resolveUserId() async {
    await _ensureAuth();
    final id = await IdentityService.resolve();
    _stream = _sessionStream(id);
    _uidForDebug = FirebaseAuth.instance.currentUser?.uid;
    return id;
  }

  Future<void> _setUsernameAndReload(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('playerName', trimmed);
    await p.setString('loggedInUser', trimmed); // keep both for compatibility
    setState(() {
      _stream = _sessionStream(trimmed);
      _userIdFuture = Future.value(trimmed);
    });
  }

  Future<void> _promptForUsername() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Username'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Exactly as used on the web (e.g., Ava)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null) {
      await _setUsernameAndReload(result);
    }
  }

  // ---- DATA ----

  Stream<List<_SessionRow>> _sessionStream(String userId) {
    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('sessions')
        .orderBy('gameNumber', descending: false)
        .limit(120); // cap initial load for speed; older sessions can be paged later

    return q.snapshots().map((qs) {
      final list = qs.docs.map((d) => _SessionRow.fromDoc(d)).toList();
      // Safety sort by numeric doc id if needed
      list.sort((a, b) {
        final ga = a.gameNumber ?? _extractGameNum(a.docId);
        final gb = b.gameNumber ?? _extractGameNum(b.docId);
        return ga.compareTo(gb);
      });
      return list;
    });
  }

  Future<int> _nextGameNumber(String userId) async {
    final sessionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('sessions');

    try {
      final snap = await sessionsRef.orderBy('gameNumber', descending: true).limit(1).get();
      if (snap.docs.isNotEmpty) {
        final dn = snap.docs.first.data()['gameNumber'];
        if (dn is num) return dn.toInt() + 1;
      }
    } catch (e) {
      debugPrint('gameNumber query failed: $e');
    }

    final all = await sessionsRef.get();
    int maxNum = 0;
    for (final d in all.docs) {
      final data = d.data();
      if (data['gameNumber'] is num) {
        maxNum = math.max(maxNum, (data['gameNumber'] as num).toInt());
      } else {
        maxNum = math.max(maxNum, _extractGameNum(d.id));
      }
    }
    return maxNum + 1;
  }

  Future<void> saveGameSession(String userId, Map<String, dynamic> sessionData) async {
    final sessionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('sessions');

    final nextGameNumber = await _nextGameNumber(userId);
    final documentId = 'Game #$nextGameNumber';

    final completeSessionData = {
      'animal': sessionData['animal'] ?? 'unknown',
      'correctGuessLeft': sessionData['correctGuessLeft'] ?? 0,
      'correctGuessRight': sessionData['correctGuessRight'] ?? 0,
      'difficulty': displayDifficultyFromRaw(sessionData['difficulty'] as String?),
      'inCorrectGuessLeft': sessionData['inCorrectGuessLeft'] ?? 0,
      'inCorrectGuessRight': sessionData['inCorrectGuessRight'] ?? 0,
      'lightsOn': sessionData['lightsOn'] ?? false,
      'metricScore': sessionData['metricScore'] ?? 'unknown',
      'missedGuess': sessionData['missedGuess'] ?? 0,
      'numTrials': sessionData['numTrials'] ?? 0,
      'outcomeDuration': sessionData['outcomeDuration'] ?? 0,
      'playerName': sessionData['playerName'] ?? 'unknown',
      'score': sessionData['score'] ?? '0 / 0',
      'soundOn': sessionData['soundOn'] ?? false,
      'stimulusDuration': sessionData['stimulusDuration'] ?? 0,
      'timestamp': sessionData['timestamp'] ?? DateTime.now().toIso8601String(),
      'trialDetails': sessionData['trialDetails'] ?? [],
      'gameNumber': sessionData['gameNumber'] ?? nextGameNumber,
      'gameId': sessionData['gameId'] ?? documentId,
    };

    await sessionsRef.doc(documentId).set(completeSessionData);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overall Session History'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Enter username',
            onPressed: _promptForUsername,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/Background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 80.0),
          child: FutureBuilder<String>(
            future: _userIdFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        const Text('Loading sessions…'),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _promptForUsername,
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Enter username now'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snap.hasError) {
                return _ErrorPane(
                  message: "Can't determine user. Use the same username as the web or enable Anonymous Auth.",
                  detail: snap.error.toString(),
                  onRetry: () => setState(() => _userIdFuture = _resolveUserId()),
                  onEnterName: _promptForUsername,
                );
              }

              final userId = snap.data!;
              final usingUid = _uidForDebug != null && userId == _uidForDebug;

              final stream = _stream ?? _sessionStream(userId);
              return StreamBuilder<List<_SessionRow>>(
                stream: stream,
                initialData: const <_SessionRow>[],
                builder: (context, s) {
                  if (s.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (s.hasError) {
                    final msg = s.error.toString();
                    final isPerm = msg.toLowerCase().contains('permission') ||
                        msg.toLowerCase().contains('missing or insufficient');
                    return _ErrorPane(
                      message: isPerm
                          ? 'Firestore says permission-denied.'
                          : 'Failed to load sessions.',
                      detail: msg,
                      onRetry: () => setState(() {}),
                      onEnterName: _promptForUsername,
                    );
                  }

                  final rows = s.data ?? const <_SessionRow>[];
                  if (rows.isEmpty) {
                    return _EmptyPane(
                      userId: userId,
                      usingUidWarning: usingUid,
                      onEnterName: usingUid ? _promptForUsername : null,
                    );
                  }

                  return SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (usingUid)
                            _InfoBanner(
                              text:
                                  'Reading at users/$userId — this is your Firebase UID. If your web app saved under a custom username, enter it (menu button) to switch.',
                            ),
                          _AnimatedChartCard(rows: rows),
                          const SizedBox(height: 16),
                          _AnimatedTableCard(rows: rows),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

// ------ Glass card wrapper ------
class _LiquidGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double opacity;
  final double borderOpacity;
  final double blurSigma;
  const _LiquidGlass({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 12,
    this.opacity = 0.22,
    this.borderOpacity = 0.35,
    this.blurSigma = 18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(opacity),
                Colors.white.withOpacity(opacity * 0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withOpacity(borderOpacity),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ------ Chart ------
class _AnimatedChartCard extends StatelessWidget {
  final List<_SessionRow> rows;
  const _AnimatedChartCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final sortedRows = [...rows]..sort((a, b) {
      final ga = a.gameNumber ?? _extractGameNum(a.docId);
      final gb = b.gameNumber ?? _extractGameNum(b.docId);
      return ga.compareTo(gb);
    });

    final groups = <BarChartGroupData>[];
    double maxY = 0;
    const double barWidth = 16.0;

    for (int i = 0; i < sortedRows.length; i++) {
      final r = sortedRows[i];
      maxY = math.max(maxY, r.total.toDouble());
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 0,
          barRods: [
            BarChartRodData(
              toY: r.correct.toDouble(),
              width: barWidth,
              gradient: const LinearGradient(colors: [Colors.blue, Colors.lightBlueAccent]),
              borderRadius: BorderRadius.circular(8),
            ),
          ],
        ),
      );
    }

    final double yMax = (maxY <= 0 ? 1 : maxY).ceilToDouble();
    double yStep;
    if (yMax <= 10) {
      yStep = 1;
    } else if (yMax <= 20) yStep = 2;
    else if (yMax <= 50) yStep = 5;
    else if (yMax <= 100) yStep = 10;
    else                 yStep = (yMax / 10).ceilToDouble();

    return _LiquidGlass(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Session Performance (Correct per Session)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              const double groupPixel = 64.0;
              final double contentWidth =
                  math.max(c.maxWidth, sortedRows.length * groupPixel + 24);

              return SizedBox(
                height: 280,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: contentWidth,
                    child: BarChart(
                      BarChartData(
                        barGroups: groups,
                        minY: 0,
                        maxY: yMax,
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: true),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: yStep,
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 48,
                              getTitlesWidget: (value, _) {
                                final i = value.toInt();
                                if (i < 0 || i >= sortedRows.length) {
                                  return const SizedBox.shrink();
                                }
                                final label = sortedRows[i].docId;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(label, style: const TextStyle(fontSize: 10)),
                                );
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final session = sortedRows[groupIndex];
                              return BarTooltipItem(
                                'Game #${session.gameNumber ?? groupIndex + 1} (${displayDifficultyFromRaw(session.difficulty)})\n'
                                'Stimulus: ${session.stimulusUnified}\n'
                                'Correct Answers: ${session.correct}\n'
                                'Stimulus Duration: ${session.stimulusDuration ?? 'N/A'}s\n'
                                'Outcome Duration: ${session.outcomeDuration ?? 'N/A'}s\n'
                                'Total Trials: ${session.total}\n'
                                'Accuracy: ${session.accuracyPercentage?.toStringAsFixed(2) ?? 'N/A'}%',
                                const TextStyle(color: Colors.white, fontSize: 12),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ------ Table ------
class _AnimatedTableCard extends StatelessWidget {
  final List<_SessionRow> rows;
  const _AnimatedTableCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return _LiquidGlass(
      padding: const EdgeInsets.all(12.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Session')),
            DataColumn(label: Text('Difficulty')),
            DataColumn(label: Text('Correct')),
            DataColumn(label: Text('Trials')),
            DataColumn(label: Text('Stim Dur')),
            DataColumn(label: Text('Stimulus')),
            DataColumn(label: Text('Outcome Dur')),
            DataColumn(label: Text('Correct →')),
            DataColumn(label: Text('Incorrect →')),
            DataColumn(label: Text('Correct ←')),
            DataColumn(label: Text('Incorrect ←')),
            DataColumn(label: Text('Missed')),
            DataColumn(label: Text('Metric Score')),
            DataColumn(label: Text('Accuracy (%)')),
          ],
          rows: [
            for (int i = 0; i < rows.length; i++)
              DataRow(cells: [
                DataCell(Text('${rows[i].gameNumber ?? i + 1}')),
                DataCell(Text(displayDifficultyFromRaw(rows[i].difficulty))),
                DataCell(Text(rows[i].correct.toString())),
                DataCell(Text(rows[i].total.toString())),
                DataCell(Text(rows[i].stimulusDuration?.toString() ?? '')),
                DataCell(Text(rows[i].stimulusUnified)),
                DataCell(Text(rows[i].outcomeDuration?.toString() ?? '')),
                DataCell(Text(rows[i].correctGuessRight?.toString() ?? '')),
                DataCell(Text(rows[i].inCorrectGuessRight?.toString() ?? '')),
                DataCell(Text(rows[i].correctGuessLeft?.toString() ?? '')),
                DataCell(Text(rows[i].inCorrectGuessLeft?.toString() ?? '')),
                DataCell(Text(rows[i].missedGuess?.toString() ?? '')),
                DataCell(Text(rows[i].metricScore?.toString() ?? '')),
                DataCell(Text(rows[i].accuracyPercentage?.toStringAsFixed(2) ?? '')),
              ]),
          ],
        ),
      ),
    );
  }
}

// ------ Empty / Error / Info ------
class _EmptyPane extends StatelessWidget {
  final String userId;
  final bool usingUidWarning;
  final VoidCallback? onEnterName;
  const _EmptyPane({required this.userId, required this.usingUidWarning, this.onEnterName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('No sessions yet for this user.'),
            const SizedBox(height: 8),
            Text('Path: users/$userId/sessions', style: const TextStyle(fontSize: 12)),
            if (usingUidWarning) ...[
              const SizedBox(height: 12),
              const Text(
                'Looks like we’re using your Firebase UID. If your web data saved under a custom username, enter it to switch.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
              const SizedBox(height: 8),
            ],
            if (onEnterName != null)
              ElevatedButton.icon(
                onPressed: onEnterName,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Enter username'),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final String detail;
  final VoidCallback onRetry;
  final VoidCallback? onEnterName;

  const _ErrorPane({
    required this.message,
    required this.detail,
    required this.onRetry,
    this.onEnterName,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                if (onEnterName != null)
                  OutlinedButton.icon(
                    onPressed: onEnterName,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Enter username'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------ helpers ------
bool? _asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.toLowerCase().trim();
    if (t == 'true' || t == '1' || t == 'yes' || t == 'on') return true;
    if (t == 'false' || t == '0' || t == 'no'  || t == 'off') return false;
  }
  return null;
}

class _SessionRow {
  final String? difficulty;
  final int correct;
  final int total;
  final String docId;
  final int? gameNumber;
  final num? stimulusDuration;
  final num? outcomeDuration;
  final Timestamp? timestamp;
  final int? correctGuessRight;
  final int? inCorrectGuessRight;
  final int? correctGuessLeft;
  final int? inCorrectGuessLeft;
  final int? missedGuess;
  final String? metricScore;
  final double? accuracyPercentage;
  final bool? lightsOn;
  final bool? soundOn;

  _SessionRow({
    required this.difficulty,
    required this.correct,
    required this.total,
    required this.docId,
    this.gameNumber,
    this.lightsOn,
    this.soundOn,
    this.stimulusDuration,
    this.outcomeDuration,
    this.timestamp,
    this.correctGuessRight,
    this.inCorrectGuessRight,
    this.correctGuessLeft,
    this.inCorrectGuessLeft,
    this.missedGuess,
    this.metricScore,
    this.accuracyPercentage,
  });

  factory _SessionRow.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    int correct = 0, total = 0;

    final score = data['score'];
    if (score is String && score.contains('/')) {
      final parts = score.split('/');
      correct = int.tryParse(parts[0].trim()) ?? 0;
      total = int.tryParse(parts[1].trim()) ?? 0;
    } else {
      total = (data['numTrials'] is num) ? (data['numTrials'] as num).toInt() : 0;
    }

    Timestamp? timestamp;
    final rawTimestamp = data['timestamp'];
    if (rawTimestamp is String) {
      try { timestamp = Timestamp.fromDate(DateTime.parse(rawTimestamp)); } catch (e) { debugPrint('Failed to parse timestamp: $e'); }
    } else if (rawTimestamp is Timestamp) {
      timestamp = rawTimestamp;
    }

    final accuracyPercentage = total > 0 ? (correct / total) * 100 : null;
    final bool? lightsOn = _asBool(data['lightsOn'] ?? data['indicatorLightOn']);
    final bool? soundOn  = _asBool(data['soundOn']  ?? data['indicatorSoundOn']);
    final int? gameNumber = (data['gameNumber'] is num) ? (data['gameNumber'] as num).toInt() : null;

    return _SessionRow(
      difficulty: displayDifficultyFromRaw(data['difficulty'] as String?),
      correct: correct,
      total: total,
      docId: d.id,
      gameNumber: gameNumber ?? _extractGameNum(d.id),
      stimulusDuration: data['stimulusDuration'] as num?,
      outcomeDuration: data['outcomeDuration'] as num?,
      timestamp: timestamp,
      correctGuessRight: data['correctGuessRight'] as int?,
      inCorrectGuessRight: data['inCorrectGuessRight'] as int?,
      correctGuessLeft: data['correctGuessLeft'] as int?,
      inCorrectGuessLeft: data['inCorrectGuessLeft'] as int?,
      missedGuess: data['missedGuess'] as int?,
      metricScore: data['metricScore'] as String?,
      accuracyPercentage: accuracyPercentage,
      lightsOn: lightsOn,
      soundOn: soundOn,
    );
  }

  String get stimulusUnified {
    final l = lightsOn == true;
    final s = soundOn == true;
    if (l && s) return 'both';
    if (l) return 'visual';
    if (s) return 'audio';
    return 'none';
  }
}
