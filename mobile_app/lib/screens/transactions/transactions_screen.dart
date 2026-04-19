// lib/screens/transactions/transactions_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<dynamic> _transactions = [];
  bool _loading = true;
  String? _typeFilter;
  String? _assetFilter;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _transactions = [];
      });
    }

    try {
      final result = await apiService.getTransactions(
        page: _page,
        limit: 20,
        type: _typeFilter,
        asset: _assetFilter,
      );

      final txs = result['transactions'] as List;
      final pagination = result['pagination'];

      if (mounted) {
        setState(() {
          _transactions = refresh ? txs : [..._transactions, ...txs];
          _hasMore = _page < (pagination['pages'] ?? 1);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncTransactions() async {
    try {
      // Call the sync endpoint on backend
      await apiService.syncTransactionsFromBlockchain();
      // Reload transactions after sync
      await _load(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Transactions synced from blockchain')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  void _applyFilter(String? type, String? asset) {
    setState(() {
      _typeFilter = type;
      _assetFilter = asset;
    });
    _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: _syncTransactions,
              child: Tooltip(
                message: 'Sync from blockchain',
                child: Icon(
                  Icons.cloud_download_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Date',
                    selected: false,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Currency',
                    selected: _assetFilter != null,
                    onTap: () => _showAssetFilter(),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Type',
                    selected: _typeFilter != null,
                    onTap: () => _showTypeFilter(),
                  ),
                ],
              ),
            ).animate().fadeIn(),

            // List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _transactions.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: () => _load(refresh: true),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _transactions.length + (_hasMore ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i == _transactions.length) {
                                return _buildLoadMore();
                              }
                              return _TxTile(
                                tx: _transactions[i],
                                index: i,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 48,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildLoadMore() {
    return Center(
      child: TextButton(
        onPressed: () {
          setState(() => _page++);
          _load();
        },
        child: const Text('Load more'),
      ),
    );
  }

  void _showTypeFilter() {
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
            Text('Filter by Type', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('All'),
              onTap: () { Navigator.pop(ctx); _applyFilter(null, _assetFilter); },
            ),
            ListTile(
              title: const Text('Sent'),
              onTap: () { Navigator.pop(ctx); _applyFilter('send', _assetFilter); },
            ),
            ListTile(
              title: const Text('Received'),
              onTap: () { Navigator.pop(ctx); _applyFilter('receive', _assetFilter); },
            ),
          ],
        ),
      ),
    );
  }

  void _showAssetFilter() {
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
            Text('Filter by Currency', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(title: const Text('All'), onTap: () { Navigator.pop(ctx); _applyFilter(_typeFilter, null); }),
            ListTile(title: const Text('USDC'), onTap: () { Navigator.pop(ctx); _applyFilter(_typeFilter, 'USDC'); }),
            ListTile(title: const Text('XLM'), onTap: () { Navigator.pop(ctx); _applyFilter(_typeFilter, 'XLM'); }),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
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

class _TxTile extends StatelessWidget {
  final Map<String, dynamic> tx;
  final int index;

  const _TxTile({required this.tx, required this.index});

  @override
  Widget build(BuildContext context) {
    final isSend = tx['type'] == 'send';
    final amount = (tx['amount'] as num).toDouble();
    final asset = tx['asset'] as String;
    final createdAt = DateTime.tryParse(tx['createdAt'] ?? '') ?? DateTime.now();
    final toUsername = tx['toUsername'] as String?;
    final memo = tx['memo'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSend ? DayFiColors.redDim : DayFiColors.greenDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isSend ? Icons.arrow_upward : Icons.arrow_downward,
              color: isSend ? DayFiColors.red : DayFiColors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSend
                      ? (toUsername != null ? '@$toUsername' : 'Sent')
                      : 'Received',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (memo != null) ...[
                  const SizedBox(height: 2),
                  Text(memo, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, h:mm a').format(createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '${isSend ? '-' : '+'}${amount.toStringAsFixed(2)} $asset',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isSend ? DayFiColors.red : DayFiColors.green,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 50));
  }
}