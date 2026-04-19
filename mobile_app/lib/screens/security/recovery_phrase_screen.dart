// lib/screens/security/recovery_phrase_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class RecoveryPhraseScreen extends StatefulWidget {
  const RecoveryPhraseScreen({super.key});
  @override
  State<RecoveryPhraseScreen> createState() => _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends State<RecoveryPhraseScreen>
    with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  List<String>? _words;
  bool _loading  = true;
  bool _blurred  = false;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Blur when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      setState(() => _blurred = true);
    } else if (state == AppLifecycleState.resumed && _verified) {
      _reAuthenticate();
    }
  }

  Future<void> _authenticate() async {
    setState(() => _loading = true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Authenticate to view your recovery phrase',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok && mounted) {
        final words = await apiService.getMnemonic();
        setState(() { _words = words; _verified = true; _blurred = false; });
      } else {
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reAuthenticate() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Authenticate to view your recovery phrase',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok && mounted) setState(() => _blurred = false);
      else if (mounted) context.pop();
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  Future<void> _markBackedUp() async {
    try {
      await apiService.markBackedUp();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wallet backed up ✓'),
            backgroundColor: DayFiColors.green,
          ),
        );
        context.pop();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recovery Phrase'),
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: DayFiColors.redDim,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: DayFiColors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Never share these words with anyone. DayFi will never ask for them.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: DayFiColors.red),
                              ),
                            ),
                          ]),
                        ).animate().fadeIn(),

                        const SizedBox(height: 28),

                        // 12 word grid
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _words?.length ?? 12,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 3.2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemBuilder: (ctx, i) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.08),
                              ),
                            ),
                            child: Row(children: [
                              Text('${i + 1}.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.4),
                                      )),
                              const SizedBox(width: 6),
                              Text(_words?[i] ?? '',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ).animate().fadeIn(delay: 100.ms),

                        const SizedBox(height: 28),

                        // Copy button
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _words?.join(' ') ?? ''));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Copied to clipboard')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy all words'),
                        ).animate().fadeIn(delay: 200.ms),

                        const SizedBox(height: 16),

                        ElevatedButton(
                          onPressed: _markBackedUp,
                          child: const Text("I've saved my recovery phrase"),
                        ).animate().fadeIn(delay: 300.ms),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),

                  // Blur overlay when backgrounded
                  if (_blurred)
                    GestureDetector(
                      onTap: _reAuthenticate,
                      child: Container(
                        color: Theme.of(context)
                            .scaffoldBackgroundColor
                            .withOpacity(0.95),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline, size: 48),
                              const SizedBox(height: 16),
                              Text('Tap to authenticate',
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ],
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