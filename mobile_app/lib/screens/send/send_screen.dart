// lib/screens/send/send_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/asset.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _toController     = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController   = TextEditingController();

  String _selectedAsset = 'USDC';
  bool _loading   = false;
  bool _resolving = false;
  bool _invalidAmount = false;
  String? _amountError;
  Map<String, dynamic>? _resolvedRecipient;
  String? _recipientError;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_validateAmount);
  }

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _validateAmount() {
    final amount = double.tryParse(_amountController.text.trim());
    final available = _availableBalance(_selectedAsset);
    
    setState(() {
      if (amount == null) {
        _invalidAmount = false;
        _amountError = null;
      } else if (amount <= 0) {
        _invalidAmount = true;
        _amountError = 'Amount must be greater than 0';
      } else if (amount > available) {
        _invalidAmount = true;
        _amountError = 'Insufficient balance. Available: ${available.toStringAsFixed(_selectedAsset == 'XLM' ? 4 : 2)} $_selectedAsset';
      } else {
        _invalidAmount = false;
        _amountError = null;
      }
    });
  }

  double _availableBalance(String asset) {
    final wallet = ref.read(walletProvider);
    if (asset == 'XLM') {
      // Balance - 2.0 XLM reserve - fee (for multi-hop swaps)
      return (wallet.xlmBalance - 2.0 - _estimatedFeeXLM()).clamp(0, double.infinity);
    }
    // USDC: full balance available (fee paid in XLM)
    return wallet.usdcBalance;
  }

  Future<void> _resolveRecipient(String value) async {
    if (value.length < 3) {
      setState(() { _resolvedRecipient = null; _recipientError = null; });
      return;
    }
    setState(() { _resolving = true; _recipientError = null; _resolvedRecipient = null; });
    try {
      final result = await apiService.resolveRecipient(value);
      if (mounted) setState(() => _resolvedRecipient = result);
    } catch (_) {
      if (mounted) setState(() => _recipientError = 'Username or address not found');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _send() async {
    final to     = _toController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    if (to.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid recipient and amount')),
      );
      return;
    }

    // Check for validation errors
    if (_invalidAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_amountError ?? 'Invalid amount')),
      );
      return;
    }

    setState(() => _loading = true);
    
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
                Text('Sending...', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Processing your payment',
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
      final result = await apiService.sendFunds(
        to:    to,
        amount: amount,
        asset:  _selectedAsset,
        memo:   _memoController.text.trim().isEmpty
            ? null
            : _memoController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showSuccess(result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        // Show error with retry option
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Send Failed'),
            content: Text(apiService.parseError(e)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Dismiss'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _send(); // Retry
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccess(Map<String, dynamic> result) {
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
              decoration: const BoxDecoration(
                  color: DayFiColors.greenDim, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: DayFiColors.green, size: 32),
            ),
            const SizedBox(height: 20),
            Text('Sent!', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '${_amountController.text} $_selectedAsset sent successfully.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (result['transaction']?['hash'] != null)
              Text(
                'Tx: ${(result['transaction']['hash'] as String).substring(0, 12)}...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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

  double _estimatedFeeXLM() => 0.00001;

  Widget _buildSendBalanceInfo(String assetCode) {
    final available = _availableBalance(assetCode);
    final wallet = ref.read(walletProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available: ${available.toStringAsFixed(assetCode == 'XLM' ? 4 : 2)} $assetCode  •  Max',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          if (assetCode == 'XLM')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '(Total: ${wallet.xlmBalance.toStringAsFixed(4)} - 2.0 XLM reserve - ${_estimatedFeeXLM()} fee)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = kAssets[_selectedAsset]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send'),
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // ── Asset selector ──────────────────────────
              Text('Asset', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kAssetList.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final code     = kAssetList[i];
                    final a        = kAssets[code]!;
                    final selected = _selectedAsset == code;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedAsset = code;
                          _amountController.clear();
                          _amountError = null;
                          _invalidAmount = false;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.15),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(a.emoji,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(code,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: selected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .background
                                          : null,
                                      fontWeight: FontWeight.w600,
                                    )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ).animate().fadeIn(),

              const SizedBox(height: 16),

              // ── Network badge ────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.08),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('⭐', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text('Stellar Network',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ).animate().fadeIn(delay: 80.ms),

              const SizedBox(height: 20),

              // ── To ──────────────────────────────────────
              Text('To', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(
                controller: _toController,
                autocorrect: false,
                onChanged: (v) {
                  if (v.length > 3) _resolveRecipient(v);
                },
                decoration: InputDecoration(
                  hintText: 'username@dayfi.me or G...',
                  suffixIcon: _resolving
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SizedBox(
                            height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ))
                      : _resolvedRecipient != null
                          ? const Icon(Icons.check_circle,
                              color: DayFiColors.green, size: 20)
                          : null,
                  errorText: _recipientError,
                ),
              ).animate().fadeIn(delay: 100.ms),

              if (_resolvedRecipient != null) ...[
                const SizedBox(height: 6),
                Text(
                  _resolvedRecipient!['username'] ??
                      _resolvedRecipient!['address'] ??
                      '',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: DayFiColors.green),
                ),
              ],

              const SizedBox(height: 20),

              // ── Amount ──────────────────────────────────
              Text('Amount', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixText: asset.code == 'USDC' ? '\$ ' : '',
                  suffixText: asset.code,
                  errorText: _amountError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _invalidAmount 
                        ? DayFiColors.red 
                        : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _invalidAmount 
                        ? DayFiColors.red 
                        : Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _invalidAmount ? DayFiColors.red : Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  final maxAmount = _availableBalance(_selectedAsset);
                  _amountController.text = maxAmount.toStringAsFixed(_selectedAsset == 'XLM' ? 4 : 2);
                },
                child: _buildSendBalanceInfo(asset.code),
              ),

              const SizedBox(height: 20),

              // ── Memo ────────────────────────────────────
              Text('Memo (optional)',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(
                controller: _memoController,
                maxLength: 28,
                decoration: const InputDecoration(
                  hintText: "What's it for?",
                  counterText: '',
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: _loading || _invalidAmount || _amountController.text.isEmpty ? null : _send,
                child: _loading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text('Send $_selectedAsset'),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}