// lib/screens/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/main.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/user_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart'; // for userProvider

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {
      setState(() => _appVersion = '1.0.0');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Log out', style: Theme.of(context).textTheme.titleLarge),
        content: Text(
          'Are you sure you want to log out?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
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
    final userAsync = ref.watch(userProvider);
    final walletState = ref.watch(walletProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // ── Profile header ────────────────────────────
            userAsync
                .when(
                  data: (u) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  (u['username'] as String? ?? 'U')[0]
                                      .toUpperCase(),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '@${u['username'] ?? ''}',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  u['email'] ?? '',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Backup warning if not backed up
                        if (u['isBackedUp'] == false) ...[
                          const SizedBox(height: 14),
                          GestureDetector(
                            onTap: () => context.push('/security/phrase'),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: DayFiColors.redDim,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: DayFiColors.red,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Your wallet is not backed up. Tap to back up now.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: DayFiColors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  loading: () => const SizedBox(
                    height: 80,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                )
                .animate()
                .fadeIn(),

            const SizedBox(height: 24),

            // ── Preferences ───────────────────────────────
            _SectionLabel('Preferences'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Dark Mode',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Switch(
                    value: isDark,
                    onChanged: (val) =>
                        ref.read(themeModeProvider.notifier).state = val
                        ? ThemeMode.dark
                        : ThemeMode.light,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 24),

            // ── Security ──────────────────────────────────
            _SectionLabel('Security'),
            _SettingsTile(
              icon: Icons.shield_outlined,
              label: 'Security',
              subtitle: 'Face ID · Recovery phrase',
              onTap: () => context.push('/security'),
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 24),

            // ── Support ───────────────────────────────────
            _SectionLabel('Support'),
            _SettingsTile(
              icon: Icons.help_outline,
              label: 'FAQs',
              subtitle: 'Frequently asked questions',
              onTap: () {
                /* TODO: open FAQ */
              },
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.info_outline,
              label: 'App Version',
              subtitle: _appVersion,
              onTap: () {},
              showChevron: false,
            ).animate().fadeIn(delay: 220.ms),

            const SizedBox(height: 32),

            // ── Log out ───────────────────────────────────
            GestureDetector(
              onTap: _logout,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: DayFiColors.redDim,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Log out',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: DayFiColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
  final bool showChevron;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.iconColor,
    this.showChevron = true,
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
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (iconColor ?? Theme.of(context).colorScheme.onSurface)
                    .withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color:
                    iconColor ??
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (showChevron)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
          ],
        ),
      ),
    );
  }
}
