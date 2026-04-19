// lib/screens/auth/biometric_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';

class BiometricScreen extends StatefulWidget {
  const BiometricScreen({super.key});

  @override
  State<BiometricScreen> createState() => _BiometricScreenState();
}

class _BiometricScreenState extends State<BiometricScreen> {
  final _auth = LocalAuthentication();
  bool _loading = false;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final can = await _auth.canCheckBiometrics;
      final sup = await _auth.isDeviceSupported();
      setState(() => _available = can && sup);
    } catch (_) {}
  }

  Future<void> _enable() async {
    setState(() => _loading = true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Enable Face ID to secure your wallet',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('faceIdEnabled', true);
        // Go to backup sheet
        context.go('/auth/backup');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Face ID setup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('faceIdEnabled', false);
    if (mounted) context.go('/auth/backup');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                  ),
                ),
                child: Icon(Icons.face_retouching_natural, size: 48,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              ).animate().scale(delay: 100.ms),
              const SizedBox(height: 32),
              Text('Enable Face ID',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 12),
              Text('Use Face ID every time you open\nthe app to keep your wallet secure.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center).animate().fadeIn(delay: 300.ms),
              const Spacer(flex: 3),
              if (_available)
                ElevatedButton(
                  onPressed: _loading ? null : _enable,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Enable Face ID'),
                ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _skip,
                child: const Text('Not now'),
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}