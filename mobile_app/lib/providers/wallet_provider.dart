// lib/providers/wallet_provider.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

// ─── Wallet State ─────────────────────────────────────────────────────────────

class WalletState {
  final double usdcBalance;
  final double xlmBalance;
  final double xlmPriceUSD;   // live from CoinGecko
  final String? stellarAddress;
  final String? dayfiUsername;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? lastUpdated;

  const WalletState({
    this.usdcBalance = 0.0,
    this.xlmBalance = 0.0,
    this.xlmPriceUSD = 0.169,  // fallback
    this.stellarAddress,
    this.dayfiUsername,
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.lastUpdated,
  });

  // ✅ Real total: USDC (1:1) + XLM at live price
  double get totalUSD => usdcBalance + (xlmBalance * xlmPriceUSD);

  // Available XLM after 1 XLM reserve requirement
  double get availableXLM => xlmBalance > 1.0 ? xlmBalance - 1.0 : 0.0;
  double get availableXLMUSD => availableXLM * xlmPriceUSD;

  WalletState copyWith({
    double? usdcBalance,
    double? xlmBalance,
    double? xlmPriceUSD,
    String? stellarAddress,
    String? dayfiUsername,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    DateTime? lastUpdated,
  }) {
    return WalletState(
      usdcBalance: usdcBalance ?? this.usdcBalance,
      xlmBalance: xlmBalance ?? this.xlmBalance,
      xlmPriceUSD: xlmPriceUSD ?? this.xlmPriceUSD,
      stellarAddress: stellarAddress ?? this.stellarAddress,
      dayfiUsername: dayfiUsername ?? this.dayfiUsername,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

// ─── Wallet Notifier ──────────────────────────────────────────────────────────

class WalletNotifier extends StateNotifier<WalletState> {
  WalletNotifier() : super(const WalletState(isLoading: true)) {
    load();
  }

  Future<double> _fetchXlmPrice() async {
    try {
      final res = await http.get(Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price?ids=stellar&vs_currencies=usd',
      )).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['stellar']['usd'] as num).toDouble();
      }
    } catch (_) {}
    return 0.169; // fallback if CoinGecko is unreachable
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final results = await Future.wait([
        apiService.getBalance(),
        apiService.getAddress(),
        _fetchXlmPrice(),
      ]);

      final balanceData = results[0] as Map<String, dynamic>;
      final addressData = results[1] as Map<String, dynamic>;
      final xlmPrice   = results[2] as double;
      final balances   = balanceData['balances'] as Map<String, dynamic>? ?? {};

      state = state.copyWith(
        usdcBalance:    (balances['USDC'] as num?)?.toDouble() ?? 0.0,
        xlmBalance:     (balances['XLM']  as num?)?.toDouble() ?? 0.0,
        xlmPriceUSD:    xlmPrice,
        stellarAddress: addressData['stellarAddress'] as String?,
        dayfiUsername:  addressData['dayfiUsername']  as String?,
        isLoading:      false,
        lastUpdated:    DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    if (state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, error: null);
    try {
      final results = await Future.wait([
        apiService.getBalance(),
        _fetchXlmPrice(),
      ]);

      final balanceData = results[0] as Map<String, dynamic>;
      final xlmPrice    = results[1] as double;
      final balances    = balanceData['balances'] as Map<String, dynamic>? ?? {};

      state = state.copyWith(
        usdcBalance:  (balances['USDC'] as num?)?.toDouble() ?? 0.0,
        xlmBalance:   (balances['XLM']  as num?)?.toDouble() ?? 0.0,
        xlmPriceUSD:  xlmPrice,
        isRefreshing: false,
        lastUpdated:  DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(isRefreshing: false, error: e.toString());
    }
  }

Future<Map<String, dynamic>> send({
  required String to,
  required double amount,
  required String asset,
  String? memo,
}) async {
  final result = await apiService.sendFunds(
    to: to, amount: amount, asset: asset, memo: memo,
  );
  await refresh();
  return result;
}

  Future<Map<String, dynamic>?> resolveRecipient(String identifier) async {
    if (identifier.length < 3) return null;
    try {
      return await apiService.resolveRecipient(identifier);
    } catch (_) {
      return null;
    }
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final walletProvider =
    StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  return WalletNotifier();
});

final usdcBalanceProvider  = Provider<double>((ref) => ref.watch(walletProvider).usdcBalance);
final xlmBalanceProvider   = Provider<double>((ref) => ref.watch(walletProvider).xlmBalance);
final xlmPriceProvider     = Provider<double>((ref) => ref.watch(walletProvider).xlmPriceUSD);
final walletAddressProvider = Provider<String?>((ref) => ref.watch(walletProvider).stellarAddress);
final dayfiUsernameProvider = Provider<String?>((ref) => ref.watch(walletProvider).dayfiUsername);