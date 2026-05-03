class DayFiAsset {
  final String code;
  final String name;
  final String emoji;
  final bool regulated;

  const DayFiAsset({
    required this.code,
    required this.name,
    required this.emoji,
    this.regulated = false,
  });

  String formatAmount(double amount) {
    if (code == 'USDC') return amount.toStringAsFixed(2);
    if (code == 'XLM')  return amount.toStringAsFixed(4);
    return amount.toStringAsFixed(2);
  }

  String get displayCode {
    if (code == 'USDC') return 'USD';
    return code;
  }

  String get settlementHint {
    if (code == 'USDC') return 'via USDC on Stellar';
    return '';
  }
}

const Map<String, DayFiAsset> kAssets = {
  'USDC': DayFiAsset(
    code:  'USDC',
    name:  'US Dollar',
    emoji: 'assets/images/us.png',
  ),
  'XLM': DayFiAsset(
    code:  'XLM',
    name:  'Stellar Lumens',
    emoji: 'assets/images/stellar.png',
  ),
};

const List<String> kAssetList = ['USDC', 'XLM'];

const Map<String, double> kApproxPrices = {
  'USDC': 1.0,
  'XLM':  0.11,
};