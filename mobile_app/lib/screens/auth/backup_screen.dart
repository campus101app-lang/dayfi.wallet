// lib/screens/auth/backup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _loading = false;

  Future<void> _markBackedUp() async {
    setState(() => _loading = true);
    try {
      await apiService.markBackedUp();
    } catch (_) {}
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: DayFiColors.greenDim,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.cloud_upload_outlined,
                    size: 40, color: DayFiColors.green),
              ).animate().scale(delay: 100.ms),
              const SizedBox(height: 28),
              Text('Back up your wallet',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 12),
              Text(
                'Save your 12-word recovery phrase.\nWithout it, you cannot recover your wallet if you lose your phone.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms),
              const Spacer(flex: 2),
              ElevatedButton(
                onPressed: _loading ? null : () => context.push('/security/phrase'),
                child: const Text('Back Up Now'),
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go('/home'),
                child: Text('Later',
                    style: Theme.of(context).textTheme.bodySmall),
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}