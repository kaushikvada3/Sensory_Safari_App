import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sensory_safari_flutter/firebase_options.dart';
import 'package:sensory_safari_flutter/services/identity_service.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _message = TextEditingController();
  final _contact = TextEditingController();

  String _category = 'Bug';
  int _rating = 0; // 0..5
  bool _consentContact = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Lock to portrait while this page is visible
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _ensureFirebase();
  }

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    // Restore landscape for the game
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _ensureFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
    } catch (_) {}
  }

  String _formatLocal(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    int hh = d.hour % 12; if (hh == 0) hh = 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.month}/${d.day}/${d.year}, $hh:${two(d.minute)}:${two(d.second)} $ampm';
  }

  Future<void> _submit() async {
    if (_rating == 0 && _message.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give a rating or a short note.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final userId = await IdentityService.resolve();
      final payload = <String, dynamic>{
        'userId': userId,
        'message': _message.text.trim(),
        'rating': _rating,
        'category': _category,
        'contact': _contact.text.trim(),
        'consentContact': _consentContact,
        'platform': Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Other'),
        'createdAt': _formatLocal(DateTime.now()),
        'createdAtTs': FieldValue.serverTimestamp(),
      };
      final db = FirebaseFirestore.instance;
      // Parent: users/{userId}
      final parentDoc = db
          .collection('users')
          .doc(userId);

      await db.runTransaction((txn) async {
        final snap = await txn.get(parentDoc);
        final current = (snap.data()?['feedbackCount'] as int?) ?? 0;
        final next = current + 1;

        // Ensure parent doc exists and bump feedbackCount on users/{userId}
        txn.set(
          parentDoc,
          {
            'feedbackCount': next,
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // New feedback lives under users/{userId}/feedback/Feedback #<n>
        final itemRef = parentDoc.collection('feedback').doc('Feedback #$next');
        txn.set(itemRef, payload);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Feedback sent.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send feedback: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Feedback'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: Stack(
          children: [
            // Background image
            Positioned.fill(
              child: Image.asset(
                'assets/portrait_background.png',
                fit: BoxFit.cover,
              ),
            ),

            // Content with glossy / liquid-glass panel
            SafeArea(
              child: AbsorbPointer(
                absorbing: _busy,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: _LiquidGlass(
                        padding: const EdgeInsets.all(16),
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(color: Colors.white),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'How was it?',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(5, (i) {
                                  final on = i < _rating;
                                  return IconButton(
                                    iconSize: 32,
                                    onPressed: () => setState(() => _rating = i + 1),
                                    icon: Icon(on ? Icons.star : Icons.star_border,
                                        color: on ? Colors.amber : Colors.grey),
                                  );
                                }),
                              ),
                              const SizedBox(height: 8),

                              DropdownButtonFormField<String>(
                                value: _category,
                                style: const TextStyle(color: Colors.white),
                                items: const [
                                  DropdownMenuItem(value: 'Bug', child: Text('Bug', style: TextStyle(color: Colors.white))),
                                  DropdownMenuItem(value: 'Idea', child: Text('Idea', style: TextStyle(color: Colors.white))),
                                  DropdownMenuItem(value: 'Confusing', child: Text('Confusing', style: TextStyle(color: Colors.white))),
                                  DropdownMenuItem(value: 'Other', child: Text('Other', style: TextStyle(color: Colors.white))),
                                ],
                                onChanged: (v) => setState(() => _category = v ?? 'Bug'),
                                dropdownColor: const Color(0xFF1E1E1E),
                                iconEnabledColor: Colors.white,
                                decoration: InputDecoration(
                                  labelText: 'Category',
                                  labelStyle: const TextStyle(color: Colors.white),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.18),
                                  border: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.28))),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.28))),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.55))),
                                ),
                              ),
                              const SizedBox(height: 12),

                              TextField(
                                controller: _message,
                                minLines: 4,
                                maxLines: 8,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Tell us more (optional)',
                                  labelStyle: const TextStyle(color: Colors.white),
                                  hintText: 'What worked? What didn’t? Any ideas?',
                                  hintStyle: const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.18),
                                  border: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.28))),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.28))),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.55))),
                                ),
                              ),
                              const SizedBox(height: 12),

                              TextField(
                                controller: _contact,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Contact (optional)',
                                  labelStyle: const TextStyle(color: Colors.white),
                                  hintText: 'Email or phone if you want follow-up',
                                  hintStyle: const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.18),
                                  border: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.28))),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.28))),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.55))),
                                ),
                              ),
                              const SizedBox(height: 4),

                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _consentContact,
                                onChanged: (v) => setState(() => _consentContact = v),
                                title: const Text('Okay to contact me about this'),
                              ),
                              const SizedBox(height: 16),

                              FilledButton.icon(
                                style: FilledButton.styleFrom(foregroundColor: Colors.white),
                                onPressed: _busy ? null : _submit,
                                icon: const Icon(Icons.send),
                                label: const Text('Submit'),
                              ),
                              const SizedBox(height: 8),

                              Text(
                                '',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
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

            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiquidGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _LiquidGlass({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container
          (
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // Soft glossy gradient + translucent fill
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.22),
                Colors.white.withOpacity(0.06),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.28),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}