import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui' as ui; // for BackdropFilter and blur
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onComplete;
  const LoginPage({super.key, required this.onComplete});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  Widget _modeToggle() {
    return Center(
      child: LiquidGlass(
        borderRadius: 28,
        blurSigma: 18,
        strokeColor: Colors.white.withOpacity(0.22),
        gradient: const [
          Colors.white,
          Colors.white,
        ],
        stops: const [0.0, 1.0],
        opacity: 0.18,
        child: _SlidingToggle(
          isSignUp: _isSignUp,
          onChanged: (v) => setState(() { _isSignUp = v; _errorMessage = null; }),
        ),
      ),
    );
  }

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _errorMessage;
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _rememberMe = true;
  bool _isSignUp = false;
  final _confirmController = TextEditingController();
  late final AnimationController _bgCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat(reverse: true);

  String _emailFor(String username) {
    final base = username.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return '$base@sensorysafari.app'; // synthetic email domain
  }

  // === NEW: local timestamp formatter for createdAt (human readable) ===
  String _formatLocal(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    int hh = d.hour % 12; if (hh == 0) hh = 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.month}/${d.day}/${d.year}, $hh:${two(d.minute)}:${two(d.second)} $ampm';
  }

  @override
  void initState() {
    super.initState();
    // portrait only
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _confirmController.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  Future<void> _attemptLogin() async {
    if (_busy) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter username and password');
      return;
    }

    setState(() { _busy = true; _errorMessage = null; });

    final db = FirebaseFirestore.instance;

    try {
      // 1) Try users/{username}
      final docRef = db.collection('users').doc(username);
      final snap = await docRef.get();

      if (snap.exists) {
        final data = snap.data() ?? {};
        final savedPass = (data['password'] ?? '').toString();
        if (savedPass != password) {
          setState(() { _busy = false; _errorMessage = 'Incorrect password'; });
          return;
        }
        await _writeSessionAndFinish(
          docRef: docRef,
          name: username,
          savedPass: savedPass,
        );
        return;
      }

      // 2) Fallback: query by `name` field
      final qs = await db
          .collection('users')
          .where('name', isEqualTo: username)
          .limit(1)
          .get();

      if (qs.docs.isEmpty) {
        setState(() { _busy = false; _errorMessage = 'User not found'; });
        return;
      }

      final doc = qs.docs.first;
      final data = doc.data();
      final savedPass = (data['password'] ?? '').toString();
      if (savedPass != password) {
        setState(() { _busy = false; _errorMessage = 'Incorrect password'; });
        return;
      }

      final userRef = db.collection('users').doc(username);
      await _writeSessionAndFinish(
        docRef: userRef,
        name: username,
        savedPass: savedPass,
      );
      return;
    } catch (e) {
      setState(() { _busy = false; _errorMessage = 'Could not contact server: $e'; });
    }
  }

  Future<void> _writeSessionAndFinish({
    required DocumentReference docRef,
    required String name,
    required String savedPass,
  }) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    // Touch only the user doc; do not increment sessionCount and do not write a sessions doc on login
    batch.set(docRef, {
      'lastUpdated': FieldValue.serverTimestamp(),
      'name': name,
    }, SetOptions(merge: true));

    try {
      await batch.commit();
    } catch (_) {
      // Non-fatal
    }

    // Clean up legacy subcollection created by older builds
    try {
      await docRef.collection('app').doc('progress').delete();
    } catch (_) {}

    // Ensure there is an auth user and reflect the username on the profile (helps other screens)
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && (u.displayName ?? '') != name) {
        await u.updateDisplayName(name);
      }
    } catch (_) {}

    // Persist for the rest of the app (overall_results, test_view logger)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', name);
      await prefs.setString('loggedInUser', name);
    } catch (_) {}

    if (!mounted) return;
    setState(() { _busy = false; });
    widget.onComplete();
  }

  // === REPLACED: Firestore-only version (no email auth) ===
  Future<void> _attemptSignUp() async {
    if (_busy) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final confirm  = _confirmController.text.trim();

    // Basic validation
    if (username.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'Please fill out all fields');
      return;
    }
    if (username.length < 3) {
      setState(() => _errorMessage = 'Username must be at least 3 characters');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() { _busy = true; _errorMessage = null; });

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(username);

    try {
      // 1) Check if username already exists (like your JS snippet)
      final exists = (await userRef.get()).exists;
      if (exists) {
        setState(() { _busy = false; _errorMessage = 'Username already exists. Please choose a different one.'; });
        return;
      }

      // 2) Create user doc with password + createdAt (human readable), etc.
      final createdStr = _formatLocal(DateTime.now());
      final batch = db.batch();
      batch.set(userRef, {
        'createdAt': createdStr,                         // human-readable like web
        'createdAtTs': FieldValue.serverTimestamp(),     // machine timestamp (optional)
        'lastUpdated': FieldValue.serverTimestamp(),
        'name': username,
        'password': password,
        'sessionCount': 0,
        'rememberMe': _rememberMe,
      }, SetOptions(merge: true));

      await batch.commit();

      // 3) Cache identity locally (equivalent to loggedInUser = username)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('playerName', username);
        await prefs.setString('loggedInUser', username);
      } catch (_) {}

      if (!mounted) return;
      setState(() { _busy = false; });
      widget.onComplete(); // hide auth; go to home
    } catch (e) {
      setState(() { _busy = false; _errorMessage = 'Sign-up failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // ===== Use Image.asset directly for background =====
          Positioned.fill(
            child: Image.asset(
              "assets/portrait_background.png",
              fit: BoxFit.cover,
            ),
          ),
          // Animated "liquid" blobs behind everything
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _bgCtrl,
              builder: (context, _) {
                // t runs 0..1..0
                final t = _bgCtrl.value;
                final dx1 = (t - 0.5) * 40; // -20..20
                final dy1 = (t - 0.5) * -30; // 15..-15
                final dx2 = (0.5 - t) * 50; // -25..25
                final dy2 = (t - 0.5) * 26; // -13..13
                return Stack(children: [
                  // big teal blob top-left
                  Positioned(
                    left: -80 + dx1,
                    top: -40 + dy1,
                    child: _Blob(size: 220, color: const Color(0xFF00C2B7).withOpacity(0.18)), // reduce opacity
                  ),
                  // lime blob top-right
                  Positioned(
                    right: -60 + dx2,
                    top: 120 + dy2,
                    child: _Blob(size: 180, color: const Color(0xFF7BEA5A).withOpacity(0.14)), // reduce opacity
                  ),
                  // aqua blob bottom-left
                  Positioned(
                    left: -40 - dx2,
                    bottom: -60 - dy1,
                    child: _Blob(size: 200, color: const Color(0xFF38E7D3).withOpacity(0.12)), // reduce opacity
                  ),
                ]);
              },
            ),
          ),

          // ===== Content =====
          SafeArea(
            child: Center(
              // NOTE: fixed a tiny formatting hiccup here to keep layout intact
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + subtitle
                      const Text(
                        'Welcome to\nSensory Safari',
                        style: TextStyle(
                          fontSize: 36,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSignUp
                            ? 'Create your account to begin the adventure!'
                            : 'Log in to start your jungle adventure!',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),

                      const SizedBox(height: 14),

                      const SizedBox(height: 14),
                      _modeToggle(),
                      const SizedBox(height: 18),

                      // Card container for inputs (friendly, elevated)
                      LiquidGlass(
                        borderRadius: 20,
                        blurSigma: 18,
                        strokeColor: Colors.transparent, // no border
                        gradient: const [
                          Colors.transparent,
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                        opacity: 0.01, // almost fully transparent
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                          child: Theme(
                            data: theme.copyWith(
                              inputDecorationTheme: InputDecorationTheme(
                                filled: true,
                                fillColor: const Color(0xFFFFFFFF).withOpacity(0.24),
                                labelStyle: const TextStyle(color: Colors.white),
                                hintStyle: const TextStyle(color: Colors.white70),
                                prefixIconColor: Colors.white70,
                                suffixIconColor: Colors.white70,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(width: 2, color: Color(0xFF0BBAB4)),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Colors.redAccent),
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _usernameController,
                                  focusNode: _usernameFocus,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(color: Colors.white),
                                  cursorColor: Colors.white,
                                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                                  decoration: const InputDecoration(
                                    labelText: 'Username',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocus,
                                  obscureText: _obscure,
                                  style: const TextStyle(color: Colors.white),
                                  cursorColor: Colors.white,
                                  onSubmitted: (_) => _isSignUp ? _attemptSignUp() : _attemptLogin(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: 'Show/Hide password',
                                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                ),
                                if (_isSignUp) ...[
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _confirmController,
                                    obscureText: _obscure,
                                    style: const TextStyle(color: Colors.white),
                                    cursorColor: Colors.white,
                                    onSubmitted: (_) => _attemptSignUp(),
                                    decoration: InputDecoration(
                                      labelText: 'Confirm password',
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        tooltip: 'Show/Hide password',
                                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                        onPressed: () => setState(() => _obscure = !_obscure),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Switch(
                                      value: _rememberMe,
                                      onChanged: (v) => setState(() => _rememberMe = v),
                                      activeColor: const Color(0xFF0BBAB4),
                                    ),
                                    const Text('Remember me', style: TextStyle(color: Color.fromARGB(255, 255, 255, 255))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD6D6), // light, warm red background
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFB00020)), // deep red icon
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Color(0xFFB00020)), // deep red text
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      SizedBox(
                        height: 56,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _busy ? null : (_isSignUp ? _attemptSignUp : _attemptLogin),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0C5E59),
                            disabledBackgroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            elevation: 6,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_busy)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              if (_busy) const SizedBox(width: 12),
                              Text(_busy
                                  ? (_isSignUp ? 'Creating account…' : 'Heading into the jungle…')
                                  : (_isSignUp ? 'Create my account' : 'Start Adventure')),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),
                      const Text(
                        '',
                        style: TextStyle(color: Colors.white70),
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

/// ======= Reusable LiquidGlass and Blob widgets =======
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final List<Color> gradient;
  final List<double> stops;
  final Color strokeColor;
  final double opacity;
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blurSigma = 18,
    this.gradient = const [Colors.white, Colors.white],
    this.stops = const [0.0, 1.0],
    this.strokeColor = const Color(0x80FFFFFF),
    this.opacity = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradient.first.withOpacity(opacity + 0.10),
                gradient.last.withOpacity(opacity),
              ],
              stops: stops,
            ),
            border: Border.all(color: strokeColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
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
        size.width * 0.6,
        [color, color.withOpacity(0.0)],
        [0.0, 1.0],
      );
    canvas.drawCircle(rect.center, size.width * 0.6, paint);
  }
  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => oldDelegate.color != color;
}

class _SlidingToggle extends StatefulWidget {
  final bool isSignUp;
  final ValueChanged<bool> onChanged;
  const _SlidingToggle({required this.isSignUp, required this.onChanged});

  @override
  State<_SlidingToggle> createState() => _SlidingToggleState();
}

class _SlidingToggleState extends State<_SlidingToggle> {
  double? _dragPercent; // null when not dragging

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final itemWidth = totalWidth / 2;

        // Calculate highlight position
        double percent = _dragPercent ?? (widget.isSignUp ? 1.0 : 0.0);
        double left = percent * (totalWidth - itemWidth);

        return GestureDetector(
          onHorizontalDragStart: (details) {
            setState(() {
              _dragPercent = widget.isSignUp ? 1.0 : 0.0;
            });
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              double x = details.localPosition.dx;
              double p = (x - itemWidth / 2) / (totalWidth - itemWidth);
              _dragPercent = p.clamp(0.0, 1.0);
            });
          },
          onHorizontalDragEnd: (details) {
            if (_dragPercent != null) {
              bool newIsSignUp = _dragPercent! > 0.5;
              setState(() {
                _dragPercent = null;
              });
              if (newIsSignUp != widget.isSignUp) widget.onChanged(newIsSignUp);
            }
          },
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Sliding highlight
                Positioned(
                  left: left,
                  width: itemWidth - 8,
                  top: 5,
                  height: 38,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => widget.onChanged(false),
                        child: SizedBox(
                          height: 48,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.login, size: 18, color: Color(0xFF0C5E59)),
                                const SizedBox(width: 8),
                                Text(
                                  'Log in',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: (percent > 0.5) ? Colors.white : const Color(0xFF0C5E59),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => widget.onChanged(true),
                        child: SizedBox(
                          height: 48,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_add_alt_1, size: 18, color: (percent > 0.5) ? const Color(0xFF0C5E59) : Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  'Create account',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: (percent > 0.5) ? const Color(0xFF0C5E59) : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
