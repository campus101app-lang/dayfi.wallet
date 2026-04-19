// lib/screens/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: DayFiColors.background,
      body: Stack(
        children: [
          // Background image placeholder — replace with your asset
          Positioned.fill(
            child: Image.asset(
              'assets/images/onboarding_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0A0A0A), Color(0xFF000000)],
                  ),
                ),
              ),
            ),
          ),

          // Dark gradient overlay at bottom
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.3, 0.7, 1.0],
                  colors: [
                    Colors.transparent,
                    DayFiColors.background.withOpacity(0.7),
                    DayFiColors.background,
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 5),

                // Headline
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                            'Digital Dollar and Native.',
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                  fontSize: 32,
                                  color: Colors.white
                                ),
                            textAlign: TextAlign.center,
                          )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideY(begin: 0.2, end: 0),

                      const SizedBox(height: 16),

                      Text(
                        'Unstoppable Freedom in Your Pocket.\nBuilt for real life: your wealth, remittances, and everyday transfers. Simple, Powerful, Yours.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.2),
                        textAlign: TextAlign.center,
                      ).animate().fadeIn(delay: 200.ms, duration: 600.ms),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Create wallet
                      ElevatedButton.icon(
                            onPressed: () => context.push(
                              '/auth/email',
                              extra: {'isNewUser': true},
                            ),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 20,
                            ),
                            label: const Text('Create a New Wallet'),
                          )
                          .animate()
                          .fadeIn(delay: 400.ms)
                          .slideY(begin: 0.3, end: 0),

                      const SizedBox(height: 16),

                      // Log in
                      TextButton.icon(
                        onPressed: () => context.push(
                          '/auth/email',
                          extra: {'isNewUser': false},
                        ),
                        icon: const Icon(Icons.download_outlined, size: 20),
                        label: const Text('Log in to existing wallet'),
                        style: TextButton.styleFrom(
                          foregroundColor: DayFiColors.textSecondary,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ).animate().fadeIn(delay: 500.ms),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
