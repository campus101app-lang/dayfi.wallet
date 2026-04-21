// lib/providers/wallet_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

// ─── Wallet State ─────────────────────────────────────────────────────────────

class WalletState {
  final double usdcBalance;
  final double xlmBalance;
  final double eurcBalance;
  final double pyusdBalance;
  final double benjiBalance;
  final double usdyBalance;
  final double wtgoldBalance;

  final double xlmPriceUSD;
  final double eurcPriceUSD;
  final double wtgoldPriceUSD;

  final String? stellarAddress;
  final String? dayfiUsername;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? lastUpdated;
  final bool hasError;
  final bool isOffline;
  final double? lastKnownTotal;

  const WalletState({
    this.usdcBalance    = 0.0,
    this.xlmBalance     = 0.0,
    this.eurcBalance    = 0.0,
    this.pyusdBalance   = 0.0,
    this.benjiBalance   = 0.0,
    this.usdyBalance    = 0.0,
    this.wtgoldBalance  = 0.0,
    this.xlmPriceUSD    = 0.169,
    this.eurcPriceUSD   = 1.08,
    this.wtgoldPriceUSD = 3200.0,
    this.stellarAddress,
    this.dayfiUsername,
    this.isLoading    = false,
    this.isRefreshing = false,
    this.error,
    this.lastUpdated,
    this.hasError  = false,
    this.isOffline = false,
    this.lastKnownTotal,
  });

  // Total USD value across all assets
  double get totalUSD =>
      usdcBalance +
      (xlmBalance     * xlmPriceUSD)    +
      (eurcBalance    * eurcPriceUSD)   +
      pyusdBalance    +   // pegged to $1
      benjiBalance    +   // stable $1 NAV
      usdyBalance     +   // pegged to $1
      (wtgoldBalance  * wtgoldPriceUSD);

  double get availableXLM => xlmBalance > 2.0 ? xlmBalance - 2.0 : 0.0;
  double get availableXLMUSD => availableXLM * xlmPriceUSD;

  /// Returns balance for any asset code — used by swap/send screens.
  double balanceFor(String code) {
    switch (code) {
      case 'USDC':   return usdcBalance;
      case 'XLM':    return xlmBalance;
      case 'EURC':   return eurcBalance;
      case 'PYUSD':  return pyusdBalance;
      case 'BENJI':  return benjiBalance;
      case 'USDY':   return usdyBalance;
      case 'WTGOLD': return wtgoldBalance;
      default:       return 0.0;
    }
  }

  /// USD value for any asset code.
  double usdValueFor(String code) {
    switch (code) {
      case 'USDC':   return usdcBalance;
      case 'XLM':    return xlmBalance    * xlmPriceUSD;
      case 'EURC':   return eurcBalance   * eurcPriceUSD;
      case 'PYUSD':  return pyusdBalance;
      case 'BENJI':  return benjiBalance;
      case 'USDY':   return usdyBalance;
      case 'WTGOLD': return wtgoldBalance * wtgoldPriceUSD;
      default:       return 0.0;
    }
  }

  /// Price per unit for any asset code.
  double priceFor(String code) {
    switch (code) {
      case 'USDC':   return 1.0;
      case 'XLM':    return xlmPriceUSD;
      case 'EURC':   return eurcPriceUSD;
      case 'PYUSD':  return 1.0;
      case 'BENJI':  return 1.0;
      case 'USDY':   return 1.0;
      case 'WTGOLD': return wtgoldPriceUSD;
      default:       return 0.0;
    }
  }

  WalletState copyWith({
    double? usdcBalance,
    double? xlmBalance,
    double? eurcBalance,
    double? pyusdBalance,
    double? benjiBalance,
    double? usdyBalance,
    double? wtgoldBalance,
    double? xlmPriceUSD,
    double? eurcPriceUSD,
    double? wtgoldPriceUSD,
    String? stellarAddress,
    String? dayfiUsername,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    DateTime? lastUpdated,
    bool? hasError,
    bool? isOffline,
    double? lastKnownTotal,
  }) {
    return WalletState(
      usdcBalance:    usdcBalance    ?? this.usdcBalance,
      xlmBalance:     xlmBalance     ?? this.xlmBalance,
      eurcBalance:    eurcBalance    ?? this.eurcBalance,
      pyusdBalance:   pyusdBalance   ?? this.pyusdBalance,
      benjiBalance:   benjiBalance   ?? this.benjiBalance,
      usdyBalance:    usdyBalance    ?? this.usdyBalance,
      wtgoldBalance:  wtgoldBalance  ?? this.wtgoldBalance,
      xlmPriceUSD:    xlmPriceUSD    ?? this.xlmPriceUSD,
      eurcPriceUSD:   eurcPriceUSD   ?? this.eurcPriceUSD,
      wtgoldPriceUSD: wtgoldPriceUSD ?? this.wtgoldPriceUSD,
      stellarAddress: stellarAddress ?? this.stellarAddress,
      dayfiUsername:  dayfiUsername  ?? this.dayfiUsername,
      isLoading:      isLoading      ?? this.isLoading,
      isRefreshing:   isRefreshing   ?? this.isRefreshing,
      error:          error,
      lastUpdated:    lastUpdated    ?? this.lastUpdated,
      hasError:       hasError       ?? this.hasError,
      isOffline:      isOffline      ?? this.isOffline,
      lastKnownTotal: lastKnownTotal ?? this.lastKnownTotal,
    );
  }
}

// ─── Wallet Notifier ──────────────────────────────────────────────────────────

class WalletNotifier extends StateNotifier<WalletState> {
  WalletNotifier() : super(const WalletState(isLoading: true)) {
    load();
  }

  // Fetch XLM price from CoinGecko; also grab EURC price
  Future<Map<String, double>> _fetchPrices() async {
    try {
      final res = await http
          .get(Uri.parse(
            'https://api.coingecko.com/api/v3/simple/price'
            '?ids=stellar,euro-coin&vs_currencies=usd',
          ))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {
          'XLM':  (data['stellar']    ?['usd'] as num?)?.toDouble() ?? state.xlmPriceUSD,
          'EURC': (data['euro-coin']  ?['usd'] as num?)?.toDouble() ?? state.eurcPriceUSD,
        };
      }
    } catch (_) {}
    return { 'XLM': state.xlmPriceUSD, 'EURC': state.eurcPriceUSD };
  }

  double? _computeLastKnown(WalletState s) {
    final live = s.totalUSD;
    return live > 0 ? live : state.lastKnownTotal;
  }

  bool _isNetworkError(Object e) {
    return e is SocketException ||
        e is TimeoutException ||
        e.toString().contains('SocketException') ||
        e.toString().contains('TimeoutException') ||
        e.toString().contains('Failed host lookup') ||
        e.toString().contains('Network is unreachable') ||
        e.toString().contains('Connection refused');
  }

  WalletState _applyBalances(
    WalletState current,
    Map<String, dynamic> balances,
    Map<String, double> prices,
  ) {
    return current.copyWith(
      usdcBalance:    (balances['USDC']   as num?)?.toDouble() ?? 0.0,
      xlmBalance:     (balances['XLM']    as num?)?.toDouble() ?? 0.0,
      eurcBalance:    (balances['EURC']   as num?)?.toDouble() ?? 0.0,
      pyusdBalance:   (balances['PYUSD']  as num?)?.toDouble() ?? 0.0,
      benjiBalance:   (balances['BENJI']  as num?)?.toDouble() ?? 0.0,
      usdyBalance:    (balances['USDY']   as num?)?.toDouble() ?? 0.0,
      wtgoldBalance:  (balances['WTGOLD'] as num?)?.toDouble() ?? 0.0,
      xlmPriceUSD:    prices['XLM']  ?? current.xlmPriceUSD,
      eurcPriceUSD:   prices['EURC'] ?? current.eurcPriceUSD,
    );
  }

  // ─── Initial load ─────────────────────────────────────────

  Future<void> load() async {
    state = state.copyWith(isLoading: true, hasError: false, isOffline: false, error: null);

    try {
      final results = await Future.wait([
        apiService.getBalance(),
        apiService.getAddress(),
        _fetchPrices(),
      ]);

      final balanceData = results[0] as Map<String, dynamic>;
      final addressData = results[1] as Map<String, dynamic>;
      final prices      = results[2] as Map<String, double>;
      final balances    = balanceData['balances'] as Map<String, dynamic>? ?? {};

      final next = _applyBalances(state, balances, prices).copyWith(
        stellarAddress: addressData['stellarAddress'] as String?,
        dayfiUsername:  addressData['dayfiUsername']  as String?,
        isLoading:      false,
        hasError:       false,
        isOffline:      false,
        lastUpdated:    DateTime.now(),
      );

      state = next.copyWith(lastKnownTotal: _computeLastKnown(next));
    } catch (e) {
      final offline = _isNetworkError(e);
      state = state.copyWith(
        isLoading: false,
        hasError:  !offline,
        isOffline: offline,
        error:     e.toString(),
      );
    }
  }

  // ─── Refresh ──────────────────────────────────────────────

  Future<void> refresh() async {
    if (state.isRefreshing) return;

    final previousTotal = state.totalUSD > 0 ? state.totalUSD : state.lastKnownTotal;

    state = state.copyWith(isRefreshing: true, hasError: false, isOffline: false, error: null);

    try {
      final results = await Future.wait([
        apiService.getBalance(),
        _fetchPrices(),
      ]);

      final balanceData = results[0] as Map<String, dynamic>;
      final prices      = results[1] as Map<String, double>;
      final balances    = balanceData['balances'] as Map<String, dynamic>? ?? {};

      final next = _applyBalances(state, balances, prices).copyWith(
        isRefreshing: false,
        hasError:     false,
        isOffline:    false,
        lastUpdated:  DateTime.now(),
      );

      state = next.copyWith(lastKnownTotal: _computeLastKnown(next));
    } catch (e) {
      final offline = _isNetworkError(e);
      state = state.copyWith(
        isRefreshing:   false,
        hasError:       !offline,
        isOffline:      offline,
        error:          e.toString(),
        lastKnownTotal: previousTotal,
      );
    }
  }

  // ─── Send ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> send({
    required String to,
    required double amount,
    required String asset,
    String? memo,
  }) async {
    final result = await apiService.sendFunds(to: to, amount: amount, asset: asset, memo: memo);
    await refresh();
    return result;
  }

  // ─── Resolve recipient ────────────────────────────────────

  Future<Map<String, dynamic>?> resolveRecipient(String identifier) async {
    if (identifier.length < 3) return null;
    if (_isStellarAddress(identifier)) {
      return { 'stellarAddress': identifier, 'dayfiUsername': null, 'displayName': identifier };
    }
    try {
      return await apiService.resolveRecipient(identifier);
    } catch (_) {
      return null;
    }
  }

  bool _isStellarAddress(String input) {
    return input.length == 56 &&
        input.startsWith('G') &&
        RegExp(r'^[A-Z2-7]+$').hasMatch(input);
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  return WalletNotifier();
});

// Convenience providers
final usdcBalanceProvider   = Provider<double>((ref) => ref.watch(walletProvider).usdcBalance);
final xlmBalanceProvider    = Provider<double>((ref) => ref.watch(walletProvider).xlmBalance);
final eurcBalanceProvider   = Provider<double>((ref) => ref.watch(walletProvider).eurcBalance);
final pyusdBalanceProvider  = Provider<double>((ref) => ref.watch(walletProvider).pyusdBalance);
final benjiBalanceProvider  = Provider<double>((ref) => ref.watch(walletProvider).benjiBalance);
final usdyBalanceProvider   = Provider<double>((ref) => ref.watch(walletProvider).usdyBalance);
final wtgoldBalanceProvider = Provider<double>((ref) => ref.watch(walletProvider).wtgoldBalance);
final xlmPriceProvider      = Provider<double>((ref) => ref.watch(walletProvider).xlmPriceUSD);
final walletAddressProvider = Provider<String?>((ref) => ref.watch(walletProvider).stellarAddress);
final dayfiUsernameProvider = Provider<String?>((ref) => ref.watch(walletProvider).dayfiUsername);