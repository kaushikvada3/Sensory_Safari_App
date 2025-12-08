import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'content_view.dart' show ContentView;
import 'overall_results.dart';
import '../feedback/feedback_page.dart';

class EndScreen extends StatefulWidget {
  final int totalTrials;
  final int score;
  final VoidCallback onRestart;
  final VoidCallback onViewOverallScore;
  final VoidCallback onFeedbackForm;

  const EndScreen({
    super.key,
    required this.totalTrials,
    required this.score,
    required this.onRestart,
    required this.onViewOverallScore,
    required this.onFeedbackForm,
  });

  @override
  State<EndScreen> createState() => _EndScreenState();
}

class _EndScreenState extends State<EndScreen> {
  bool showGraph = false;
  bool titleLift = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      setState(() {
        titleLift = true;
        showGraph = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final insets = MediaQuery.of(context).padding;

    final bottomPad = math.max(insets.bottom + 40.0, size.height * 0.08);
    final buttonSize = math.min(80.0, math.max(70.0, size.width * 0.18));
    final chipMaxWidth = math.min(360.0, size.width * 0.88);

    final correct = widget.score;
    final incorrect = math.max(0, widget.totalTrials - widget.score);

    return WillPopScope(
      onWillPop: () async => false, // disable swipe back
      child: Scaffold(
        body: Stack(
          children: [
            // Background
            Positioned.fill(
              child: Image.asset(
                'assets/Background.png',
                fit: BoxFit.cover,
              ),
            ),

            // Body: chart + right panel
            Align(
              alignment: Alignment.center,
              child: LayoutBuilder(builder: (context, constraints) {
                final leftTargetW = showGraph ? size.width * 0.45 : 0.0;
                final rightTargetW = showGraph
                    ? size.width * 0.55
                    : math.min(size.width * 0.8, 700.0);

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  width: size.width,
                  height: size.height,
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: Offset(size.width * 0.04, size.height * 0.16), // shift right ~4% and down ~16% of screen height
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Left: chart
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                          width: leftTargetW,
                          height: size.height * 0.7,
                          transform: Matrix4.translationValues(
                            size.width * 0.02,
                            -size.height * 0.02,
                            0,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 400),
                              opacity: showGraph ? 1 : 0,
                              child: Container(
                                width: math.min(size.width * 0.44, 520),
                                height: math.min(size.height * 0.62, 380),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.52),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.28),
                                    width: 1,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: TrialBarChart(
                                  correct: correct,
                                  incorrect: incorrect,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Right: chips + buttons
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                          width: rightTargetW,
                          height: size.height * 0.7,
                          padding: const EdgeInsets.only(left: 0),
                          transform: Matrix4.translationValues(
                            showGraph ? -size.width * 0.015 : 0,
                            0,
                            0,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Chips
                              ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: chipMaxWidth),
                                child: LayoutBuilder(
                                  builder: (context, b) {
                                    final isTight = b.maxWidth < 320;
                                    final children = [
                                      InfoChip(title: 'Score', value: '${widget.score}'),
                                      InfoChip(title: 'Trials', value: '${widget.totalTrials}'),
                                    ];
                                    return isTight
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ...children
                                                  .map((c) => Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                                bottom: 8),
                                                        child: c,
                                                      ))
                                                  ,
                                            ],
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              ...children
                                                  .map((c) => Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                                right: 12),
                                                        child: c,
                                                      ))
                                                  ,
                                            ],
                                          );
                                  },
                                ),
                              ),
                              const SizedBox(height: 40),

                              // Round buttons
                              Padding(
                                padding: EdgeInsets.only(bottom: bottomPad),
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 480),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: CircleActionButton(
                                          icon: Icons.home_rounded,
                                          size: buttonSize,
                                          bg: const Color(0xFFFFEB3B),
                                          fg: Colors.black,
                                          onPressed: () {
                                            // Go to ContentView explicitly
                                            Navigator.of(context).pushAndRemoveUntil(
                                              MaterialPageRoute(builder: (_) => const ContentView()),
                                              (route) => false,
                                            );
                                          },
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: CircleActionButton(
                                          icon: Icons.bar_chart_rounded,
                                          size: buttonSize,
                                          bg: const Color(0xFFFF9800),
                                          fg: Colors.black,
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(builder: (_) => const OverallResultsPage()),
                                            );
                                          },
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: CircleActionButton(
                                          icon: Icons.edit_square,
                                          size: buttonSize,
                                          bg: const Color(0xFF2196F3),
                                          fg: Colors.white,
                                          onPressed: () {
                                            Navigator.of(context, rootNavigator: true).push(
                                              MaterialPageRoute(builder: (_) => const FeedbackPage()),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),

            // Title overlay
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  transform: Matrix4.translationValues( // x nudge + lift
                    MediaQuery.of(context).size.width * 0.01,
                    titleLift ? -36 : 0,
                    0,
                  ),
                  alignment: Alignment.topCenter,
                  padding: EdgeInsets.only(top: insets.top + 56),
                  child: const Text(
                    'Game Over',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.25,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Color(0x59000000),
                          blurRadius: 3,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Subviews ---------------------------------------------------------------

class InfoChip extends StatelessWidget {
  final String title;
  final String value;

  const InfoChip({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 128, maxWidth: 170, minHeight: 80, maxHeight: 100),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.52),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class CircleActionButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color bg;
  final Color fg;
  final VoidCallback onPressed;

  const CircleActionButton({
    super.key,
    required this.icon,
    required this.size,
    required this.bg,
    required this.fg,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const CircleBorder(),
      color: bg,
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: fg, size: size * 0.36),
        ),
      ),
    );
  }
}

class TrialBarChart extends StatelessWidget {
  final int correct;
  final int incorrect;

  const TrialBarChart({
    super.key,
    required this.correct,
    required this.incorrect,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = [correct, incorrect, 1].reduce(math.max).toDouble();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Trial Results',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),

        // Legend
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Legend(color: Colors.teal, label: 'Correct'),
              SizedBox(width: 16),
              _Legend(color: Colors.pinkAccent, label: 'Incorrect'),
            ],
          ),
        ),

        // Bars and X-axis labels
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final barW = math.min(120.0, c.maxWidth * 0.35);
              final maxBarH = math.max(80.0, c.maxHeight * 0.65);

              Widget bar(int value, Color color) {
                final h = math.max(6.0, (value / maxValue) * maxBarH);
                return SizedBox(
                  width: barW,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('$value',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: maxBarH,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: h,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.28),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        bar(correct, Colors.teal),
                        const SizedBox(width: 28),
                        bar(incorrect, Colors.pinkAccent),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: barW,
                          child: const Text(
                            'Correct',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 28),
                        SizedBox(
                          width: barW,
                          child: const Text(
                            'Incorrect',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 10,
          decoration: BoxDecoration(
            color: color.withOpacity(0.85),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}