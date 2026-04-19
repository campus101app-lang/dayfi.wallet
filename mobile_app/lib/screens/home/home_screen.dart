// lib/screens/home/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/widgets/app_background.dart';
import '../../models/asset.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

final userProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => apiService.getMe(),
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _balanceHidden = false;
  bool _menuOpen = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.read(walletProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final userAsync = ref.watch(userProvider);
// home_screen.dart — replace the Scaffold return
return Scaffold(
  backgroundColor: Colors.transparent,
  body: AppBackground(
    child: SafeArea(
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await ref.read(walletProvider.notifier).refresh();
              ref.invalidate(userProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
                child: Column(
                  children: [
                    _buildTopBar(),
                    const Spacer(flex: 3),
                    _buildBalanceLabel(),
                    const SizedBox(height: 12),
                    _buildTotalBalance(walletState),
                    const SizedBox(height: 8),
                    _buildReserveInfo(walletState),
                    const SizedBox(height: 20),
                    _buildPortfolioChip(walletState),
                    const SizedBox(height: 12),
                    _buildTransactionsLink(),
                    const Spacer(flex: 4),
                    _buildActionRow(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
          if (_menuOpen) _buildMenu(userAsync),
        ],
      ),
    ),
  ),
);
  }

  // ─── Top bar ─────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'dayfi.',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _menuOpen = !_menuOpen),
            child: Icon(
              _menuOpen ? Icons.close : Icons.menu,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Balance label ───────────────────────────────────────

  Widget _buildBalanceLabel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Total Wallet Balance',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() => _balanceHidden = !_balanceHidden),
          child: Icon(
            _balanceHidden
                ? Icons.visibility_off_outlined
                : Icons.remove_red_eye_outlined,
            size: 15,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms);
  }

  // ─── Total balance ───────────────────────────────────────

  Widget _buildTotalBalance(WalletState walletState) {
    final xlmPriceUSD = walletState.xlmPriceUSD ?? 0.0;
    const xlmReserve = 2.0; // XLM reserve for multi-hop swaps
    final reservedUSD = xlmReserve * xlmPriceUSD;
    final total = walletState.totalUSD - reservedUSD;

    final wholePart = total.toInt().toString();
    final decimalPart = (total - total.toInt())
        .toStringAsFixed(2)
        .substring(1); // ".25"

    if (walletState.isLoading) {
      return Text(
        '\$—',
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
          fontSize: 64,
          fontWeight: FontWeight.w300,
          letterSpacing: -3,
        ),
      );
    }

    if (_balanceHidden) {
      return Text(
        '\$***.**',
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: 64,
          fontWeight: FontWeight.w300,
          letterSpacing: -3,
        ),
      );
    }

    // Split typography: large whole, smaller decimal (like the reference)
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '\$',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w300,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          wholePart,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: 72,
            fontWeight: FontWeight.w300,
            letterSpacing: -4,
            height: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            decimalPart,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w300,
              letterSpacing: -1,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.05, end: 0);
  }

  // ─── Reserve Info ────────────────────────────────────────

  Widget _buildReserveInfo(WalletState walletState) {
    if (walletState.isLoading || _balanceHidden) return const SizedBox.shrink();
    
    const reserved = 2.0; // 0.5 base + 0.5 USDC trustline + 0.5-1.0 path intermediates
    final availableXLM = (walletState.xlmBalance - reserved).clamp(0, double.infinity);
    final availableUSD = availableXLM * (walletState.xlmPriceUSD ?? 0.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available to Use',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${availableUSD.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Reserved (Minimum)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${reserved.toStringAsFixed(2)} XLM',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  // ─── Portfolio chip ──────────────────────────────────────

  Widget _buildPortfolioChip(WalletState walletState) {
    // Stacked coin emojis for held assets
    final heldAssets = <String>[];
    if (walletState.usdcBalance > 0) heldAssets.add('🔵'); // USDC
    if (walletState.xlmBalance > 0) heldAssets.add('⬛');   // XLM
    if (heldAssets.isEmpty) {
      heldAssets.add('🔵');
      heldAssets.add('⬛');
    }

    return GestureDetector(
      onTap: () => context.push('/portfolio'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stacked emoji avatars
            SizedBox(
              width: 16.0 + (heldAssets.length * 16.0),
              height: 26,
              child: Stack(
                children: List.generate(heldAssets.length, (i) {
                  return Positioned(
                    left: i * 16.0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          heldAssets[i],
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Portfolio',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  // ─── Transactions link ───────────────────────────────────

  Widget _buildTransactionsLink() {
    return GestureDetector(
      onTap: () => context.push('/transactions'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
          ),
          const SizedBox(width: 5),
          Text(
            'Transactions',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms);
  }

  // ─── Action row ──────────────────────────────────────────

  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 72),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            _ActionButton(
              icon: "assets/icons/svgs/receive.svg",
              label: 'Receive',
              onTap: () => context.push('/receive'),
            ),
             _ActionButton(
              icon: "assets/icons/svgs/swap.svg",
              label: 'Swap',
              onTap: () => context.push('/swap'),
            ),
            _ActionButton(
              icon: "assets/icons/svgs/send.svg",
              label: 'Send',
              onTap: () => context.push('/send'),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.4, end: 0);
  }

  // ─── Slide-out menu ──────────────────────────────────────

  Widget _buildMenu(AsyncValue<Map<String, dynamic>> userAsync) {
    final items = [
      // ('portfolio', '/portfolio'),
      ('transactions', '/transactions'),
      ('security', '/security'),
      ('settings', '/settings'),
      ('support', null),
      ('fund wallet (test)', 'test-fund'),
    ];

    return GestureDetector(
      onTap: () => setState(() => _menuOpen = false),
      child: AppBackground(
        // color: Colors.transparent,
        child: Container(
          width: double.infinity,
          // color: Theme.of(context).scaffoldBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              userAsync.when(
                data: (u) => Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Text(
                    '@${u['username'] ?? ''}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4),
                    ),
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              ...items.map(
                (item) => GestureDetector(
                  onTap: () async {
                    setState(() => _menuOpen = false);
                    if (item.$2 == 'test-fund') {
                      try {
                        await apiService.testFundWallet();
                        await ref.read(walletProvider.notifier).refresh();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Wallet funded with 1.0 XLM'),
                              backgroundColor: Color(0xFF4CAF50),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('❌ Fund failed: $e'),
                              backgroundColor: const Color(0xFFE53935),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    } else if (item.$2 != null) {
                      context.push(item.$2!);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      item.$1,
                      style:
                          Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w300,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 180.ms);
  }
}

// ─── Action Button ────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                icon,
                height: 22,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.55),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}