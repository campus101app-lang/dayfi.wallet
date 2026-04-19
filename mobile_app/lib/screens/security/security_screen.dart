// lib/screens/security/security_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _auth = LocalAuthentication();
  bool _faceIdEnabled = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _faceIdEnabled = prefs.getBool('faceIdEnabled') ?? false);
  }

  Future<void> _toggleFaceId(bool val) async {
    setState(() => _loading = true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: val
            ? 'Enable Face ID for DayFi'
            : 'Confirm to disable Face ID',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('faceIdEnabled', val);
        setState(() => _faceIdEnabled = val);
      }
    } catch (_) {}
    finally { setState(() => _loading = false); }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete Account',
            style: Theme.of(context).textTheme.titleLarge),
        content: Text(
          'This will permanently delete your account and wallet. '
          'Make sure you have saved your recovery phrase.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: DayFiColors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await apiService.clearToken();
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security'),
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [

            // ── Recovery Phrase ──────────────────────────
            _SectionLabel('Wallet'),
            _SettingsTile(
              icon: Icons.key_outlined,
              label: 'Recovery Phrase',
              subtitle: '12-word backup phrase',
              onTap: () => context.push('/security/phrase'),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 24),

            // ── Face ID ──────────────────────────────────
            _SectionLabel('Authentication'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.face_retouching_natural, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Face ID',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500)),
                        Text('Required on every app open',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  _loading
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Switch(
                          value: _faceIdEnabled,
                          onChanged: _toggleFaceId,
                        ),
                ],
              ),
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 32),

            // ── Danger zone ──────────────────────────────
            _SectionLabel('Danger Zone'),
            _SettingsTile(
              icon: Icons.delete_outline,
              label: 'Delete Account',
              subtitle: 'Permanently remove your account',
              iconColor: DayFiColors.red,
              onTap: _deleteAccount,
            ).animate().fadeIn(delay: 200.ms),
          ],
        ),
      ),
    );
  }
}

// ─── Settings Screen ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                )),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String?  subtitle;
  final Color?   iconColor;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: (iconColor ?? Theme.of(context).colorScheme.onSurface)
                  .withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20,
                color: iconColor ??
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
        ]),
      ),
    );
  }
}