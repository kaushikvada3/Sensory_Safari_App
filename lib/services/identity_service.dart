

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// A single source of truth for the user identity used in Firestore paths.
///
/// Priority order when resolving an id:
///  1) Locally saved username (SharedPreferences: `playerName`, `loggedInUser`, ...)
///  2) FirebaseAuth user (displayName → email prefix → uid)
///  3) (Optional) guest id `anon-<base36>` if [allowGuest] is true
///
/// Use [IdentityService.resolve] anywhere you need the document id under
/// `users/<id>/...`. Keep your LoginPage responsible for saving the username
/// via [IdentityService.saveLocal] (already done in your app).
class IdentityService {
  IdentityService._();

  static const List<String> _keys = <String>[
    'playerName', 'loggedInUser', 'username', 'userName', 'displayName', 'player'
  ];

  /// Persist the chosen username locally so every screen can read it fast.
  static Future<void> saveLocal(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('playerName', name);
    await p.setString('loggedInUser', name);
  }

  /// Lightweight peek at what we already have on disk. Returns `null` if none.
  static Future<String?> currentLocal() async => _readLocal();

  /// Resolve the Firestore identity to use. See the class header for priority.
  ///
  /// If [allowGuest] is true and no local/auth identity exists, a stable
  /// anonymous id will be generated, saved, and returned (e.g. `anon-k9x…`).
  /// If [allowGuest] is false (default), the method throws a [StateError]
  /// prompting the caller to show the Login screen.
  static Future<String> resolve({bool allowGuest = false}) async {
    // 1) Prefer local name saved by the login flow.
    final local = await _readLocal();
    if (local != null) return local;

    // 2) Otherwise derive from the current Firebase user (if any) and cache it.
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      final id = _fromAuth(u);
      await saveLocal(id);
      return id;
    }

    // 3) Last resort
    if (allowGuest) {
      final anon = await _ensureGuest();
      return anon;
    }

    throw StateError('No username set. Please log in first.');
  }

  /// Update FirebaseAuth.displayName to match [name] (best-effort),
  /// and save locally so subsequent resolves are instant.
  static Future<void> setAndReflect(String name) async {
    await saveLocal(name);
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && (u.displayName ?? '') != name) {
        await u.updateDisplayName(name);
      }
    } catch (e) {
      debugPrint('[IdentityService] update displayName failed: $e');
    }
  }

  /// INTERNALS --------------------------------------------------------------

  static Future<String?> _readLocal() async {
    final p = await SharedPreferences.getInstance();
    for (final k in _keys) {
      final v = p.getString(k);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static String _fromAuth(User u, {String? local}) {
    // If a local preference was provided, it wins.
    if (local != null && local.isNotEmpty) return local;

    final dn = u.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;

    final email = u.email?.trim();
    if (email != null && email.isNotEmpty) {
      final at = email.indexOf('@');
      return at > 0 ? email.substring(0, at) : email;
    }

    return u.uid; // last resort — always available
  }

  static Future<String> _ensureGuest() async {
    final p = await SharedPreferences.getInstance();
    var anon = p.getString('playerName');
    if (anon == null || anon.trim().isEmpty || !anon.startsWith('anon-')) {
      final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      anon = 'anon-$ts';
      await saveLocal(anon);
    }
    return anon;
  }
}