// lib/screens/receive/receive_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/widgets/app_background.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/api_service.dart';

// ─── Emoji mapping for emojis that come from backend ────────────────────────────

final Map<String, String> _assetEmojis = {
  'USDC': '💵',
  'XLM': '🌟',
  'BTC': '₿',
  'SOL': '☀️',
  'XAUT': '🥇',
  'GOLD': '🥇',
};

final Map<String, String> _networkEmojis = {
  'stellar': '⭐',
  'ethereum': '🔹',
  'arbitrum': '💙',
  'polygon': '💜',
  'avalanche': '🔺',
  'bitcoin': '🟠',
  'solana': '☀️',
};

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  int _selectedTab = 0; // 0 = Blockchains, 1 = Username

  Map<String, dynamic>? _addressData;
  Map<String, dynamic>? _rawAssets;
  Map<String, dynamic>? _rawNetworks;
  bool _loading = true;

  String? _selectedAssetCode;
  String? _selectedNetworkKey;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      // Fetch both address and network config in parallel
      final results = await Future.wait([
        apiService.getAddress(),
        apiService.getNetworkConfig(),
      ]);

      final addressData = results[0];
      final configData = results[1];

      if (mounted) {
        setState(() {
          _addressData = addressData;
          // Parse assets map: { "USDC": ["stellar"], "XLM": ["stellar"] }
          _rawAssets =
              configData['assets'] as Map<String, dynamic>? ??
              {
                'USDC': ['stellar'],
                'XLM': ['stellar'],
              };
          // Parse networks map: { "stellar": { "name": "Stellar", ... } }
          _rawNetworks =
              configData['networks'] as Map<String, dynamic>? ??
              {
                'stellar': {
                  'name': 'Stellar Network',
                  'emoji': '⭐',
                  'description': 'Fast, low-cost payments on Stellar',
                },
              };
          _loading = false;

          // Auto-select first asset and network for convenience
          if (_selectedAssetCode == null &&
              _rawAssets != null &&
              _rawAssets!.isNotEmpty) {
            _selectedAssetCode = _rawAssets!.keys.first;
            final networks = _rawAssets![_selectedAssetCode];
            if (networks is List && networks.isNotEmpty) {
              _selectedNetworkKey = networks.first;
            }
          }
        });
      }
    } catch (e) {
      print('Error loading wallet config: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          // Set defaults on error
          _rawAssets = {
            'USDC': ['stellar'],
            'XLM': ['stellar'],
          };
          _rawNetworks = {
            'stellar': {
              'name': 'Stellar Network',
              'emoji': '⭐',
              'description': 'Fast, low-cost payments on Stellar',
            },
          };
          if (_selectedAssetCode == null) {
            _selectedAssetCode = 'USDC';
            _selectedNetworkKey = 'stellar';
          }
        });
      }
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _share(String text) => Share.share(text);

  /// Map network key to the corresponding address field
  String _getAddressForNetwork() {
    if (_selectedNetworkKey == null) return '';

    switch (_selectedNetworkKey) {
      case 'stellar':
        return _addressData?['stellarAddress'] ?? '';
      case 'bitcoin':
        return _addressData?['bitcoinAddress'] ?? '';
      case 'solana':
        return _addressData?['solanaAddress'] ?? '';
      default:
        // Ethereum, Arbitrum, Polygon, Avalanche all use EVM address
        return _addressData?['evmAddress'] ?? '';
    }
  }

  // ─── Currency bottom sheet ───────────────────────────────

  void _showCurrencyPicker() {
    print('_rawAssets: $_rawAssets');
    print('_addressData: $_addressData');

    if (_rawAssets == null) return;

    final currencies = _rawAssets!.keys.toList();

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
                Text(
                  'Choose Currency to Receive',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...currencies.map((assetCode) {
              final emoji = _assetEmojis[assetCode] ?? '💎';
              final isSelected = _selectedAssetCode == assetCode;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedAssetCode = assetCode;
                    _selectedNetworkKey = null; // Reset network selection
                  });
                  Navigator.pop(ctx);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(ctx).colorScheme.primary.withOpacity(0.08)
                        : Theme.of(ctx).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(ctx).colorScheme.primary.withOpacity(0.3)
                          : Theme.of(
                              ctx,
                            ).colorScheme.onSurface.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assetCode,
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          Text(
                            assetCode, // TODO: Fetch full names from backend
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: Theme.of(ctx).colorScheme.primary,
                          size: 20,
                        ),
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

  // ─── Network bottom sheet ────────────────────────────────

  void _showNetworkPicker() {
    if (_selectedAssetCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a currency first')),
      );
      return;
    }

    final supportedNetworks =
        _rawAssets?[_selectedAssetCode] as List<dynamic>? ?? [];

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
                Text(
                  'Choose Network',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...supportedNetworks.map((networkKey) {
              final networkInfo =
                  _rawNetworks?[networkKey] as Map<String, dynamic>? ?? {};
              final networkName = networkInfo['name'] ?? networkKey;
              final emoji = _networkEmojis[networkKey] ?? '🔗';
              final isSelected = _selectedNetworkKey == networkKey;

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedNetworkKey = networkKey);
                  Navigator.pop(ctx);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(ctx).colorScheme.primary.withOpacity(0.08)
                        : Theme.of(ctx).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(ctx).colorScheme.primary.withOpacity(0.3)
                          : Theme.of(
                              ctx,
                            ).colorScheme.onSurface.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 14),
                      Text(
                        networkName,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: Theme.of(ctx).colorScheme.primary,
                          size: 20,
                        ),
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

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,

          title: const Text('Receive Funds'),
          leading: GestureDetector(
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios, size: 20),
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Tab switcher
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Tab(
                              label: 'Blockchains',
                              selected: _selectedTab == 0,
                              onTap: () => setState(() => _selectedTab = 0),
                            ),
                            _Tab(
                              label: 'dayfi.me',
                              selected: _selectedTab == 1,
                              onTap: () => setState(() => _selectedTab = 1),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(),

                      const SizedBox(height: 32),

                      if (_selectedTab == 0) _buildBlockchainTab(),
                      if (_selectedTab == 1) _buildUsernameTab(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ─── Blockchain tab ───────────────────────────────────────

  Widget _buildBlockchainTab() {
    final address = _getAddressForNetwork();
    final ready =
        _selectedAssetCode != null &&
        _selectedNetworkKey != null &&
        address.isNotEmpty;

    String selectedNetworkName = '';
    if (_selectedNetworkKey != null && _rawNetworks != null) {
      final networkInfo = _rawNetworks![_selectedNetworkKey];
      if (networkInfo is Map<String, dynamic>) {
        selectedNetworkName = networkInfo['name'] ?? _selectedNetworkKey ?? '';
      } else {
        selectedNetworkName = _selectedNetworkKey ?? '';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Manually Select Blockchain',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ).animate().fadeIn(),
        const SizedBox(height: 8),
        Text(
          'Choose the currency and network below to get\nyour unique receiving address and QR code.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 24),

        // Currency + Network dropdowns
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _showCurrencyPicker,
                child: _DropdownBox(
                  emoji: _selectedAssetCode != null
                      ? _assetEmojis[_selectedAssetCode]
                      : null,
                  label: _selectedAssetCode ?? 'Choose Currency',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _showNetworkPicker,
                child: _DropdownBox(
                  emoji: _selectedNetworkKey != null
                      ? _networkEmojis[_selectedNetworkKey]
                      : null,
                  label: selectedNetworkName.isNotEmpty
                      ? selectedNetworkName
                      : 'Choose Network',
                ),
              ),
            ),
          ],
        ).animate().fadeIn(delay: 150.ms),

        const SizedBox(height: 32),

        // QR + address — show when both selected
        if (!ready) ...[
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.qr_code_2,
                  size: 80,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.15),
                ),
                const SizedBox(height: 16),
                Text(
                  'Waiting for selection...',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Once you select a currency and network,\nyour QR code and wallet address will\nappear right here.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ] else ...[
          Center(child: _QRCard(data: address).animate().scale()),
          const SizedBox(height: 20),
          _AddressBox(
            text: address.length > 16
                ? '${address.substring(0, 8)}...${address.substring(address.length - 8)}'
                : address,
            onCopy: () => _copy(address),
          ).animate().fadeIn(),
          const SizedBox(height: 20),
          _ActionButtons(
            onShare: () => _share(address),
            onCopy: () => _copy(address),
          ).animate().fadeIn(),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  // ─── Username tab ─────────────────────────────────────────

  Widget _buildUsernameTab() {
    final username = _addressData?['dayfiUsername'] ?? '';
    final qrData = 'https://dayfi.me/pay/$username';

    return Column(
      children: [
        Text(
          'Receive via dayfi.me',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ).animate().fadeIn(),
        const SizedBox(height: 8),
        Text(
          'Share this QR or your dayfi.me username.\nAnyone can send you USDC instantly.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 32),
        _QRCard(data: qrData).animate().scale(delay: 200.ms),
        const SizedBox(height: 8),
        Text(
          'Stellar Network · USDC',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        _AddressBox(
          text: username,
          onCopy: () => _copy(username),
        ).animate().fadeIn(delay: 300.ms),
        const SizedBox(height: 20),
        _ActionButtons(
          onShare: () => _share('Send me USDC at $username'),
          onCopy: () => _copy(username),
        ).animate().fadeIn(delay: 350.ms),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: selected ? Theme.of(context).colorScheme.background : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DropdownBox extends StatelessWidget {
  final String? emoji;
  final String label;

  const _DropdownBox({this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: emoji == null
                    ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
                    : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ],
      ),
    );
  }
}

class _QRCard extends StatelessWidget {
  final String data;
  const _QRCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: QrImageView(
        data: data.isEmpty ? 'dayfi' : data,
        version: QrVersions.auto,
        size: 220,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.circle,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _AddressBox extends StatelessWidget {
  final String text;
  final VoidCallback onCopy;
  const _AddressBox({required this.text, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCopy,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onCopy;
  const _ActionButtons({required this.onShare, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Share'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ),
      ],
    );
  }
}
