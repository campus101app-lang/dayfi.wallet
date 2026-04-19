// lib/screens/swap/swap_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../models/asset.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SwapScreen extends ConsumerStatefulWidget {
  const SwapScreen({super.key});

  @override
  ConsumerState<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends ConsumerState<SwapScreen> {
  String _fromAsset = 'XLM';
  String _toAsset   = 'USDC';

  final _amountController = TextEditingController();

  Map<String, dynamic>? _quote;
  bool _loadingQuote = false;
  bool _executing    = false;
  String? _quoteError;
  Timer? _debounce;

  @override
  void dispose() {
    _amountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ─── Balance helpers ──────────────────────────────────────

  double _balanceFor(String asset) {
    final w = ref.read(walletProvider);
    switch (asset) {
      case 'USDC': return w.usdcBalance;
      case 'XLM':  return w.xlmBalance;
      default:     return 0;
    }
  }

  // XLM: reserve 2.0 for multi-hop swaps (0.5 base + 0.5 USDC trustline + 0.5-1.0 for path intermediates)
  // USDC: no reserve needed
  // Fee: negligible (~0.00001 XLM per operation)
  double _availableFor(String asset) {
    final balance = _balanceFor(asset);
    if (asset == 'XLM') {
      // Reserve 2.0 XLM minimum to handle multi-hop swap paths with intermediate assets
      return (balance - 2.0).clamp(0, double.infinity);
    }
    // USDC: can use full balance (fee is paid in XLM)
    return balance;
  }

  // Estimate swap fee in XLM (Stellar base fee is ~1 stroop = 0.00001 XLM)
  double _estimatedFeeXLM() => 0.00001;

  bool get _hasInsufficientBalance {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    return amount > 0 && amount > _availableFor(_fromAsset);
  }

  // ─── Quote ────────────────────────────────────────────────

  void _onAmountChanged(String val) {
    _debounce?.cancel();
    setState(() { _quote = null; _quoteError = null; });
    if (val.isEmpty || double.tryParse(val) == null) return;
    _debounce = Timer(const Duration(milliseconds: 800), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;
    if (_fromAsset == _toAsset) {
      setState(() => _quoteError = 'Choose two different assets');
      return;
    }

    // Balance check before hitting API
    if (amount > _availableFor(_fromAsset)) {
      setState(() => _quoteError =
          'Insufficient balance. Available: ${_availableFor(_fromAsset).toStringAsFixed(6)} $_fromAsset');
      return;
    }

    setState(() { _loadingQuote = true; _quoteError = null; });
    try {
      final result = await apiService.getSwapQuote(
        fromAsset: _fromAsset,
        toAsset: _toAsset,
        amount: amount,
      );
      if (mounted) setState(() => _quote = result);
    } catch (e, stack) {
      final errorMsg = apiService.parseError(e);
      developer.log(
        'Quote fetch failed',
        error: e,
        stackTrace: stack,
        name: 'SwapScreen.fetchQuote',
      );
      print('🟡 QUOTE ERROR: $errorMsg');
      if (mounted) setState(() => _quoteError = errorMsg.isEmpty ? 'Failed to fetch quote' : errorMsg);
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  Future<void> _executeSwap() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || _quote == null) return;

    // Final balance guard
    if (amount > _availableFor(_fromAsset)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Insufficient $_fromAsset balance. '
            'Available: ${_availableFor(_fromAsset).toStringAsFixed(6)}',
          ),
          backgroundColor: DayFiColors.red,
        ),
      );
      return;
    }

    setState(() => _executing = true);
    
    // Show loading dialog that persists
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  height: 40,
                  width: 40,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 16),
                Text('Processing swap...', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'This may take a few seconds',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await apiService.executeSwap(
        fromAsset: _fromAsset,
        toAsset: _toAsset,
        amount: amount,
      );

      // Wait for Stellar to fully settle (3 retries, 1 sec each)
      bool confirmed = false;
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(seconds: 1));
        try {
          await ref.read(walletProvider.notifier).refresh();
          confirmed = true;
          break;
        } catch (_) {
          // Keep retrying
        }
      }

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showSuccess(result, confirmed);
      }
    } catch (e, stack) {
      final errorMsg = apiService.parseError(e);
      developer.log(
        'Swap execution failed',
        error: e,
        stackTrace: stack,
        name: 'SwapScreen.executeSwap',
      );
      print('🔴 SWAP ERROR: $errorMsg');
      print('Full error: $e');
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        // Determine user-friendly message
        String displayMsg = errorMsg;
        if (displayMsg.isEmpty || displayMsg.contains('DioException')) {
          displayMsg = 'Swap failed - please check your balance and try again';
        } else if (displayMsg.contains('Insufficient')) {
          displayMsg = 'Not enough XLM available. Need 2.0 XLM reserved.';
        } else if (displayMsg.contains('Server processing')) {
          displayMsg = 'Server processing error - please try again in a moment';
        }
        
        // Show error with snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMsg),
            backgroundColor: DayFiColors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _executeSwap,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  void _flip() {
    setState(() {
      final tmp = _fromAsset;
      _fromAsset = _toAsset;
      _toAsset   = tmp;
      _quote     = null;
      _quoteError = null;
    });
    if (_amountController.text.isNotEmpty) _fetchQuote();
  }

  void _showSuccess(Map<String, dynamic> result, bool confirmed) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(color: DayFiColors.greenDim, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: DayFiColors.green, size: 32),
            ),
            const SizedBox(height: 20),
            Text('Swap Complete!', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '${_amountController.text} $_fromAsset → $_toAsset\nStellar DEX · ${confirmed ? 'Confirmed' : 'Processing'}',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (result['transaction']?['hash'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tx: ${(result['transaction']['hash'] as String).substring(0, 12)}...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () { Navigator.pop(ctx); context.go('/home'); },
              child: const Text('Done'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _estimatedReceive() {
    if (_quote == null) return '—';
    final val = _quote!['buy_amount'] ?? _quote!['toAmount'];
    return val != null ? '≈ $val' : '—';
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final fromAsset   = kAssets[_fromAsset]!;
    final toAsset     = kAssets[_toAsset]!;
    final available   = _availableFor(_fromAsset);
    final totalUSD    = walletState.totalUSD;

    // Disable if wallet hasn't loaded or total is 0
    final walletEmpty = !walletState.isLoading && totalUSD <= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swap'),
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _executing,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Network badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text('Stellar DEX · ~5s · Very low fees',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ).animate().fadeIn(),

              const SizedBox(height: 24),

              // Empty wallet warning
              if (walletEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: DayFiColors.redDim,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          color: DayFiColors.red, size: 16),
                      const SizedBox(width: 8),
                      Text('Your wallet has no funds to swap.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: DayFiColors.red)),
                    ],
                  ),
                ).animate().fadeIn(),

              // FROM card
              _SwapCard(
                label: 'You pay',
                asset: fromAsset,
                onAssetTap: () => _showAssetPicker(isFrom: true),
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: Theme.of(context).textTheme.headlineMedium,
                  onChanged: _onAmountChanged,
                  decoration: InputDecoration(
                    hintText: '0.00',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintStyle: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                        ),
                  ),
                ),
              ).animate().fadeIn(),

              // Available balance hint with reserve info
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _executing ? null : () {
                        final toUse = available - _estimatedFeeXLM();
                        _amountController.text = toUse.toStringAsFixed(
                          _fromAsset == 'XLM' ? 4 : 2,
                        );
                        _onAmountChanged(_amountController.text);
                      },
                      child: Text(
                        'Available: ${available.toStringAsFixed(_fromAsset == 'XLM' ? 4 : 2)} $_fromAsset  ·  Max',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _executing
                                  ? DayFiColors.red  // Red when processing
                                  : _hasInsufficientBalance
                                  ? DayFiColors.red
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                              fontWeight: _executing ? FontWeight.w600 : FontWeight.w400,
                            ),
                      ),
                    ),
                    if (_fromAsset == 'XLM')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '(Total: ${_balanceFor('XLM').toStringAsFixed(4)} - 2.0 XLM reserve - fee)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Flip button
              Center(
                child: GestureDetector(
                  onTap: _flip,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                      ),
                    ),
                    child: const Icon(Icons.swap_vert, size: 18),
                  ),
                ),
              ),

              // TO card
              _SwapCard(
                label: 'You receive',
                asset: toAsset,
                onAssetTap: () => _showAssetPicker(isFrom: false),
                child: _loadingQuote
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _estimatedReceive(),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: _quote != null
                                  ? null
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
                            ),
                      ),
              ).animate().fadeIn(delay: 80.ms),

              const SizedBox(height: 16),

              // Insufficient balance error
              if (_hasInsufficientBalance)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DayFiColors.redDim,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Insufficient balance. Available: '
                    '${available.toStringAsFixed(_fromAsset == 'XLM' ? 4 : 2)} $_fromAsset',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: DayFiColors.red),
                  ),
                ).animate().fadeIn()
              else if (_quoteError != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DayFiColors.redDim,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_quoteError!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: DayFiColors.red)),
                ).animate().fadeIn(),

              // Quote details
              if (_quote != null && !_hasInsufficientBalance) ...[
                const SizedBox(height: 4),
                _QuoteDetails(
                  quote: _quote!,
                  fromAsset: _fromAsset,
                  toAsset: _toAsset,
                ).animate().fadeIn(),
              ],

              const SizedBox(height: 28),

              // Swap button
              ElevatedButton(
                onPressed: (_quote == null || _executing ||
                        _hasInsufficientBalance || walletEmpty)
                    ? null
                    : _executeSwap,
                child: _executing
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text(_quote != null
                        ? 'Swap $_fromAsset → $_toAsset'
                        : 'Enter amount to get quote'),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 32),
            ],
                ),
              ),
            ),
            // Loading overlay when executing
            if (_executing)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          height: 48,
                          width: 48,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Processing Swap...',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please wait while your transaction\nis confirmed on the network',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
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

  void _showAssetPicker({required bool isFrom}) {
    final excluded = isFrom ? _toAsset : _fromAsset;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select Asset', style: Theme.of(context).textTheme.titleLarge),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...kAssetList.map((code) {
              final a          = kAssets[code]!;
              final isDisabled = code == excluded;
              final isSelected = code == (isFrom ? _fromAsset : _toAsset);
              final bal        = _availableFor(code);
              return GestureDetector(
                onTap: isDisabled ? null : () {
                  Navigator.pop(ctx);
                  setState(() {
                    if (isFrom) _fromAsset = code;
                    else        _toAsset   = code;
                    _quote = null;
                  });
                  if (_amountController.text.isNotEmpty) _fetchQuote();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                          : Theme.of(context).colorScheme.onSurface.withOpacity(
                              isDisabled ? 0.04 : 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(a.emoji,
                          style: TextStyle(
                              fontSize: 24,
                              color: isDisabled ? Colors.grey.withOpacity(0.4) : null)),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.code,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: isDisabled
                                        ? Theme.of(context).colorScheme.onSurface.withOpacity(0.3)
                                        : null,
                                  )),
                          Text(
                            isFrom
                                ? '${bal.toStringAsFixed(code == 'XLM' ? 4 : 2)} available'
                                : a.name,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isDisabled
                                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2)
                                      : bal == 0 && isFrom
                                          ? DayFiColors.red.withOpacity(0.7)
                                          : null,
                                ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (isSelected)
                        Icon(Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary, size: 20),
                      if (isDisabled && !isSelected)
                        Text('In use',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                                )),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Swap Card ────────────────────────────────────────────

class _SwapCard extends StatelessWidget {
  final String label;
  final DayFiAsset asset;
  final VoidCallback onAssetTap;
  final Widget child;

  const _SwapCard({
    required this.label,
    required this.asset,
    required this.onAssetTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: onAssetTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(asset.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(asset.code, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down, size: 16),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: child),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Quote Details ────────────────────────────────────────

class _QuoteDetails extends StatelessWidget {
  final Map<String, dynamic> quote;
  final String fromAsset;
  final String toAsset;

  const _QuoteDetails({
    required this.quote,
    required this.fromAsset,
    required this.toAsset,
  });

  @override
  Widget build(BuildContext context) {
    final price = quote['price']?.toString() ?? quote['rate']?.toString() ?? '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          _Row(label: 'Network',   value: 'Stellar DEX'),
          _Row(label: 'Rate',      value: '1 $fromAsset = $price $toAsset'),
          _Row(label: 'Est. Time', value: '~5 seconds'),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}