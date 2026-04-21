// lib/models/asset.dart

class DayFiAsset {
  final String code;
  final String name;
  final String emoji; // path to asset image
  final bool regulated;

  const DayFiAsset({
    required this.code,
    required this.name,
    required this.emoji,
    this.regulated = false,
  });

  String formatAmount(double amount) {
    switch (code) {
      case 'USDC':
      case 'EURC':
      case 'PYUSD':
      case 'BENJI':
      case 'USDY':
        return amount.toStringAsFixed(2);
      case 'XLM':
        return amount.toStringAsFixed(4);
      case 'WTGOLD':
        return amount.toStringAsFixed(6); 
      default:
        return amount.toStringAsFixed(2);
    }
  }
}

const Map<String, DayFiAsset> kAssets = {
  'USDC': DayFiAsset(
    code: 'USDC',
    name: 'USD Coin',
    emoji: 'assets/images/usdc.png',
    regulated: true,
  ),
  'XLM': DayFiAsset(
    code: 'XLM',
    name: 'Stellar Lumens',
    emoji: 'assets/images/stellar.png',
  ),
  'EURC': DayFiAsset(
    code: 'EURC',
    name: 'Euro Coin',
    emoji: 'assets/images/eurc.png',
    regulated: true,
  ),
  'PYUSD': DayFiAsset(
    code: 'PYUSD',
    name: 'PayPal USD',
    emoji: 'assets/images/pyusd.png',
    regulated: true,
  ),
  'BENJI': DayFiAsset(
    code: 'BENJI',
    name: 'Franklin OnChain Fund',
    emoji: 'assets/images/benji.png',
    regulated: true,
  ),
  'USDY': DayFiAsset(
    code: 'USDY',
    name: 'Ondo US Dollar Yield',
    emoji: 'assets/images/usdy.png',
    regulated: true,
  ),
  'WTGOLD': DayFiAsset(
    code: 'WTGOLD',
    name: 'WisdomTree Gold',
    emoji: 'assets/images/wtgold.png',
    regulated: true,
  ),
};

const List<String> kAssetList = [
  'USDC',
  'XLM',
  'EURC',
  'PYUSD',
  'BENJI',
  'USDY',
  'WTGOLD',
];

const Map<String, double> kApproxPrices = {
  'USDC':   1.0,
  'XLM':    0.11,
  'EURC':   1.08,
  'PYUSD':  1.0,
  'BENJI':  1.0,
  'USDY':   1.0,
  'WTGOLD': 3200.0,
};