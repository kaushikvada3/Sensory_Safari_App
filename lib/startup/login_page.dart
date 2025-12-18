import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui' as ui; // for BackdropFilter and blur
import 'package:shared_preferences/shared_preferences.dart';
import 'liquid_glass_components.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onComplete;
  const LoginPage({super.key, required this.onComplete});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  Widget _modeToggle() {
    return Center(
      child: LiquidGlassContainer(
        borderRadius: 28,
        blurSigma: 18,
        borderColor: Colors.white.withOpacity(0.22),
        gradientColors: const [
          Colors.white,
          Colors.white,
        ],
        gradientStops: const [0.0, 1.0],
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

  Future<void> _enterDemoMode() async {
    if (_busy) return;
    setState(() { _busy = true; _errorMessage = null; });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', 'Demo User');
      await prefs.setString('loggedInUser', 'Demo User');
    } catch (_) {
      // ignore errors if prefs fail, we still want to let them in
    }

    if (!mounted) return;
    setState(() { _busy = false; });
    widget.onComplete();
  }

  Future<void> _showAccountHelpDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: LiquidGlassContainer(
            borderRadius: 24,
            blurSigma: 20,
            opacity: 0.15,
            borderColor: Colors.white.withOpacity(0.4),
            solidColor: Colors.white.withOpacity(0.2),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Account Help',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'What would you like to do?',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                LiquidGlassButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showPasswordResetDialog(); // The old "Overwrite" flow
                  },
                  child: const Text('Reset Password'),
                ),
                const SizedBox(height: 16),
                LiquidGlassButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showChangeUsernameDialog(); // The new "Migration" flow
                  },
                  child: const Text('Change Username'),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPasswordResetDialog() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String? localError;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: LiquidGlassContainer(
                borderRadius: 24,
                blurSigma: 20,
                opacity: 0.15,
                borderColor: Colors.white.withOpacity(0.4),
                solidColor: Colors.white.withOpacity(0.2),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Reset Password',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Enter your username to set a new password.',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    LiquidGlassTextField(
                      controller: userCtrl, 
                      label: 'Username', 
                      prefixIcon: Icons.person_outline,
                    ),
                    const SizedBox(height: 16),
                    LiquidGlassTextField(
                      controller: passCtrl, 
                      label: 'New Password', 
                      prefixIcon: Icons.lock_outline,
                    ),
                    if (localError != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBox(message: localError!),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0BBAB4)),
                          onPressed: () async {
                            final u = userCtrl.text.trim();
                            final p = passCtrl.text.trim();
                            if (u.isEmpty || p.isEmpty) {
                              setState(() => localError = 'Please fill all fields');
                              return;
                            }
                            try {
                              final docRef = FirebaseFirestore.instance.collection('users').doc(u);
                              final doc = await docRef.get();
                              if (!doc.exists) {
                                setState(() => localError = 'User not found');
                                return;
                              }
                              await docRef.update({'password': p});
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Password updated! You can now log in.')),
                                );
                              }
                            } catch (e) {
                              setState(() => localError = 'Error: $e');
                            }
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showChangeUsernameDialog() async {
    final oldUserCtrl = TextEditingController();
    final oldPassCtrl = TextEditingController();
    final newUserCtrl = TextEditingController();
    String? localError;
    bool busy = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: LiquidGlassContainer(
                borderRadius: 24,
                blurSigma: 20,
                opacity: 0.15,
                borderColor: Colors.white.withOpacity(0.4),
                solidColor: Colors.white.withOpacity(0.2),
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Change Username',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Move all your data to a new username.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      LiquidGlassTextField(
                        controller: oldUserCtrl, 
                        label: 'Old Username', 
                        prefixIcon: Icons.person,
                      ),
                      const SizedBox(height: 12),
                      LiquidGlassTextField(
                        controller: oldPassCtrl, 
                        label: 'Old Password', 
                        obscureText: true,
                        prefixIcon: Icons.lock,
                      ),
                      const SizedBox(height: 12),
                      LiquidGlassTextField(
                        controller: newUserCtrl, 
                        label: 'New Username', 
                        prefixIcon: Icons.person_add,
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 12),
                        _ErrorBox(message: localError!),
                      ],
                      const SizedBox(height: 24),
                      if (busy)
                        const Center(child: CircularProgressIndicator(color: Colors.white))
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0BBAB4)),
                              onPressed: () async {
                                final oldU = oldUserCtrl.text.trim();
                                final oldP = oldPassCtrl.text.trim();
                                final newU = newUserCtrl.text.trim();
                  
                                if (oldU.isEmpty || oldP.isEmpty || newU.isEmpty) {
                                  setState(() => localError = 'Fill all fields');
                                  return;
                                }
                                if (newU.length < 3) {
                                  setState(() => localError = 'New username too short');
                                  return;
                                }
                                setState(() => busy = true);
                                final err = await _performMigration(oldU, oldP, newU);
                                if (context.mounted) {
                                  if (err == null) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Success! Moved $oldU to $newU.')),
                                    );
                                  } else {
                                    setState(() {
                                      localError = err;
                                      busy = false;
                                    });
                                  }
                                }
                              },
                              child: const Text('Move Data'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _performMigration(String oldU, String oldP, String newU) async {
    final db = FirebaseFirestore.instance;
    final oldRef = db.collection('users').doc(oldU);
    final newRef = db.collection('users').doc(newU);

    try {
      // 1. Verify Old
      final oldSnap = await oldRef.get();
      if (!oldSnap.exists) return 'Old user not found';
      final data = oldSnap.data()!;
      if ((data['password'] ?? '').toString() != oldP) return 'Incorrect password for old user';

      // 2. Verify New
      final newSnap = await newRef.get();
      if (newSnap.exists) return 'Username "$newU" is already taken';

      // 3. Create New User Doc (Copy + update name)
      final newData = Map<String, dynamic>.from(data);
      newData['name'] = newU;
      newData['createdAt'] = _formatLocal(DateTime.now()); 
      await newRef.set(newData);

      // 4. Migrate Subcollection "sessions"
      // Note: This needs to scan & copy.
      // We will do a simple batch copy.
      final sessions = await oldRef.collection('sessions').get();
      final batch = db.batch();
      
      for (final doc in sessions.docs) {
        final newSubRef = newRef.collection('sessions').doc(doc.id);
        batch.set(newSubRef, doc.data());
        batch.delete(doc.reference); // Delete old session
      }
      
      // Delete old user parent doc
      batch.delete(oldRef);

      await batch.commit();
      return null; // Success
    } catch (e) {
      return 'Migration failed: $e';
    }
  }

  Future<void> _resetLoginFields() async {
    _usernameController.clear();
    _passwordController.clear();
    _confirmController.clear();
    
    // Also clear session data to be safe
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('playerName');
      await prefs.remove('loggedInUser');
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    setState(() {
      _errorMessage = null;
      _isSignUp = false; 
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LiquidGlassScaffold(
      // Static background asset
      backgroundAsset: "assets/portrait_background.jpg",
      body: Stack(
        children: [
          // (No manual background needed here, handled by Scaffold)

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

                      // Card container for inputs
                      LiquidGlassContainer(
                        borderRadius: 20,
                        blurSigma: 24, // High blur per iOS 26 spec
                        borderColor: Colors.white.withOpacity(0.15),
                        gradientColors: const [
                          Colors.white,
                          Colors.white,
                        ],
                        gradientStops: const [0.0, 1.0],
                        opacity: 0.08, // Very subtle fill
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LiquidGlassTextField(
                                controller: _usernameController,
                                focusNode: _usernameFocus,
                                textInputAction: TextInputAction.next,
                                label: 'Username',
                                prefixIcon: Icons.person_outline,
                                onSubmitted: (_) => _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: 16),
                              LiquidGlassTextField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                obscureText: _obscure,
                                label: 'Password',
                                prefixIcon: Icons.lock_outline,
                                suffixIcon: IconButton(
                                  tooltip: 'Show/Hide password',
                                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: Colors.white70),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                                onSubmitted: (_) => _isSignUp ? _attemptSignUp() : _attemptLogin(),
                              ),
                              if (_isSignUp) ...[
                                const SizedBox(height: 16),
                                LiquidGlassTextField(
                                  controller: _confirmController,
                                  obscureText: _obscure,
                                  label: 'Confirm password',
                                  prefixIcon: Icons.lock_outline,
                                  suffixIcon: IconButton(
                                    tooltip: 'Show/Hide password',
                                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: Colors.white70),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                  onSubmitted: (_) => _attemptSignUp(),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Switch(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(() => _rememberMe = v),
                                    activeColor: const Color(0xFF0BBAB4),
                                  ),
                                  const Text('Remember me', style: TextStyle(color: Colors.white)),
                                  const Spacer(),
                                  if (!_isSignUp)
                                    TextButton(
                                      onPressed: _showAccountHelpDialog,
                                      child: const Text(
                                        'Reset',
                                        style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline, decorationColor: Colors.white30),
                                      ),
                                    ),
                                ],
                              ),
                            ],
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

                      const SizedBox(height: 16),
                      
                      LiquidGlassButton(
                        onPressed: _busy ? null : (_isSignUp ? _attemptSignUp : _attemptLogin),
                        child: _busy
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(_isSignUp ? 'Create my account' : 'Start Adventure'),
                      ),

                      const SizedBox(height: 20),

                      // Demo Mode Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _enterDemoMode,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          ),
                          child: const Text('Enter Demo Mode (No Login)'),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Reset Fields Button

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





class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFB00020).withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB00020).withOpacity(0.4)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
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
                                const Icon(Icons.login, size: 16, color: Color(0xFF0C5E59)),
                                const SizedBox(width: 6),
                                Text(
                                  'Log in',
                                  style: TextStyle(
                                    fontSize: 15,
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
                                Icon(Icons.person_add_alt_1, size: 16, color: (percent > 0.5) ? const Color(0xFF0C5E59) : Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  'Create account',
                                  style: TextStyle(
                                    fontSize: 15,
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
