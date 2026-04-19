// lib/screens/portfolio/portfolio_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

// ─── Provider: raw transactions (up to 100, all assets) ──────────────────────

final _txProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final result = await apiService.getTransactions(page: 1, limit: 100);
  return List<Map<String, dynamic>>.from(result['transactions'] ?? []);
});

// ─── Portfolio screen ─────────────────────────────────────────────────────────

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  int _selectedPeriod = 1; // 0=1D 1=1W 2=1M 3=ALL
  final _periods = ['1D', '1W', '1M', 'ALL'];

  DateTime get _periodStart {
    final now = DateTime.now();
    return switch (_selectedPeriod) {
      0 => now.subtract(const Duration(days: 1)),
      1 => now.subtract(const Duration(days: 7)),
      2 => now.subtract(const Duration(days: 30)),
      _ => DateTime(2000),
    };
  }

  /// Reconstructs historical balance curve from transactions.
  /// Walks backwards from current balance, undoing each tx chronologically.
  /// Returns USD values (not normalised — painter handles that).
  List<double> _buildPoints(
    List<Map<String, dynamic>> txs,
    String asset,
    double currentBalance,
    double xlmPrice,
  ) {
    final cutoff = _periodStart;
    final filtered = txs
        .where((t) => t['asset'] == asset)
        .where((t) {
          final dt = DateTime.tryParse(t['createdAt'] ?? '');
          return dt != null && dt.isAfter(cutoff);
        })
        .toList()
      ..sort((a, b) => DateTime.parse(a['createdAt'])
          .compareTo(DateTime.parse(b['createdAt'])));

    if (filtered.isEmpty) {
      final usd = asset == 'XLM' ? currentBalance * xlmPrice : currentBalance;
      return [usd, usd];
    }

    double running = currentBalance;
    final reversed = filtered.reversed.toList();
    final rawValues = <double>[];

    for (final tx in reversed) {
      final amt  = (tx['amount'] as num).toDouble();
      final type = tx['type'] as String;
      if (type == 'send' || type == 'swap') {
        running += amt;
      } else {
        running -= amt;
      }
      rawValues.add(running.clamp(0, double.infinity));
    }

    final chronological = rawValues.reversed.toList()..add(currentBalance);

    return chronological.map((b) {
      return asset == 'XLM' ? b * xlmPrice : b;
    }).toList();
  }

  double _computeChange(List<double> points) {
    if (points.length < 2) return 0.0;
    final first = points.first;
    if (first <= 0) return 0.0;
    return ((points.last - first) / first) * 100;
  }

  /// Interpolates two series to the same length then sums pointwise.
  List<double> _combinePoints(List<double> a, List<double> b) {
    final len = a.length > b.length ? a.length : b.length;
    if (len == 0) return [];
    List<double> interp(List<double> src) {
      if (src.length == len) return src;
      return List.generate(len, (i) {
        final t  = i / (len - 1);
        final si = t * (src.length - 1);
        final lo = si.floor().clamp(0, src.length - 1);
        final hi = si.ceil().clamp(0, src.length - 1);
        return src[lo] + (src[hi] - src[lo]) * (si - lo);
      });
    }
    final ia = interp(a), ib = interp(b);
    return List.generate(len, (i) => ia[i] + ib[i]);
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final txAsync     = ref.watch(_txProvider);

    return Scaffold(
      body: SafeArea(
        child: txAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (e, _) => Center(child: Text('Error: $e')),
          data:    (txs) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_txProvider);
              await ref.read(walletProvider.notifier).refresh();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildBody(context, walletState, txs),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WalletState w, List<Map<String, dynamic>> txs) {
    final xlmPrice = w.xlmPriceUSD;
    const xlmReserve = 2.0; // 0.5 base + 0.5 USDC trustline + 0.5-1.0 path intermediates
    final reservedUSD = xlmReserve * xlmPrice;
    final xlmUSD   = w.xlmBalance * xlmPrice;
    final usdcUSD  = w.usdcBalance;
    final total    = w.totalUSD - reservedUSD;

    final xlmPoints  = _buildPoints(txs, 'XLM',  w.xlmBalance,  xlmPrice);
    final usdcPoints = _buildPoints(txs, 'USDC', w.usdcBalance, 1.0);
    final combined   = _combinePoints(xlmPoints, usdcPoints);

    final changePct = _computeChange(combined);
    final changeAbs = combined.length >= 2 ? combined.last - combined.first : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 32),
        _buildTotalValue(total),
        const SizedBox(height: 8),
        _buildChangeRow(changePct, changeAbs),
        const SizedBox(height: 28),
        _buildPeriodSelector(),
        const SizedBox(height: 20),
        _buildChart(combined),
        const SizedBox(height: 36),
        _buildReserveInfo(w),
        const SizedBox(height: 24),
        _buildAllocation(xlmUSD, usdcUSD, total),
        const SizedBox(height: 36),
        _buildAssetList(w, xlmUSD, usdcUSD, xlmPoints, usdcPoints),
        const SizedBox(height: 40),
      ],
    );
  }

  // ─── Header ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Icon(Icons.arrow_back_ios, size: 20,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(width: 16),
          Text('Portfolio',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600, letterSpacing: -0.5)),
        ],
      ),
    );
  }

  // ─── Total value ─────────────────────────────────────────

  Widget _buildTotalValue(double total) {
    final whole   = total.toInt().toString();
    final decimal = (total - total.toInt()).toStringAsFixed(2).substring(1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('\$', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w300)),
        ),
        Text(whole, style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: 56, fontWeight: FontWeight.w300, letterSpacing: -3, height: 1)),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(decimal, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w300, letterSpacing: -1)),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms);
  }

  // ─── Change row ──────────────────────────────────────────

  Widget _buildChangeRow(double pct, double abs) {
    final pos = pct >= 0;
    final label = ['today', 'this week', 'this month', 'all time'][_selectedPeriod];
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: pos ? DayFiColors.greenDim : Colors.red.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('${pos ? '+' : ''}${pct.toStringAsFixed(2)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: pos ? DayFiColors.green : Colors.redAccent,
              fontWeight: FontWeight.w600, fontSize: 11)),
        ),
        const SizedBox(width: 8),
        Text('${pos ? '+' : ''}\$${abs.abs().toStringAsFixed(2)} $label',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4))),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  // ─── Period selector ─────────────────────────────────────

  Widget _buildPeriodSelector() {
    return Row(
      children: List.generate(_periods.length, (i) {
        final sel = i == _selectedPeriod;
        return GestureDetector(
          onTap: () => setState(() => _selectedPeriod = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? Colors.transparent
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.12)),
            ),
            child: Text(_periods[i],
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: sel
                    ? Theme.of(context).scaffoldBackgroundColor
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                fontSize: 12)),
          ),
        );
      }),
    );
  }

  // ─── Chart ───────────────────────────────────────────────

  Widget _buildChart(List<double> points) {
    final pos = _computeChange(points) >= 0;
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _SparklinePainter(
          points: points,
          color: pos ? DayFiColors.green : Colors.redAccent,
          fillColor: pos
              ? DayFiColors.green.withOpacity(0.06)
              : Colors.redAccent.withOpacity(0.06),
        ),
        child: const SizedBox.expand(),
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  // ─── Allocation donut ─────────────────────────────────────

  Widget _buildAllocation(double xlmUSD, double usdcUSD, double total) {
    final xlmPct  = total > 0 ? xlmUSD  / total : 0.5;
    final usdcPct = total > 0 ? usdcUSD / total : 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Allocation', style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -0.3)),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 90, height: 90,
              child: CustomPaint(painter: _DonutPainter(segments: [
                _DonutSegment(
                  fraction: xlmPct,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85)),
                _DonutSegment(
                  fraction: usdcPct,
                  color: DayFiColors.green.withOpacity(0.7)),
              ])),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AllocationLegendRow(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                    label: 'XLM', pct: xlmPct, value: xlmUSD),
                  const SizedBox(height: 12),
                  _AllocationLegendRow(
                    color: DayFiColors.green.withOpacity(0.7),
                    label: 'USDC', pct: usdcPct, value: usdcUSD),
                ],
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }

  // ─── Reserve info ─────────────────────────────────────────

  Widget _buildReserveInfo(WalletState w) {
    final reserved = 2.0; // XLM reserve for multi-hop swaps
    final available = (w.xlmBalance - reserved).clamp(0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reserve Information',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available to Use',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 4),
                  Text('${available.toStringAsFixed(4)} XLM',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: DayFiColors.green)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Reserved (Minimum)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 4),
                  Text('${reserved.toStringAsFixed(1)} XLM',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 250.ms);
  }

  // ─── Asset list ───────────────────────────────────────────

  Widget _buildAssetList(
    WalletState w, double xlmUSD, double usdcUSD,
    List<double> xlmPoints, List<double> usdcPoints,
  ) {
    final assets = [
      (emoji: '⬛', code: 'XLM',  name: 'Stellar Lumens',
       balance: w.xlmBalance,  usd: xlmUSD,
       change: _computeChange(xlmPoints),  points: xlmPoints),
      (emoji: '🔵', code: 'USDC', name: 'USD Coin',
       balance: w.usdcBalance, usd: usdcUSD,
       change: _computeChange(usdcPoints), points: usdcPoints),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Assets', style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -0.3)),
        const SizedBox(height: 16),
        ...assets.asMap().entries.map((e) {
          final a = e.value;
          return _AssetRow(
            emoji: a.emoji, code: a.code, name: a.name,
            balance: a.balance, usdValue: a.usd,
            change: a.change, points: a.points,
          )
            .animate()
            .fadeIn(delay: Duration(milliseconds: 350 + e.key * 80))
            .slideX(begin: 0.04, end: 0);
        }),
      ],
    );
  }
}

// ─── Asset row ────────────────────────────────────────────

class _AssetRow extends StatelessWidget {
  final String emoji, code, name;
  final double balance, usdValue, change;
  final List<double> points;

  const _AssetRow({
    required this.emoji, required this.code,  required this.name,
    required this.balance, required this.usdValue,
    required this.change,  required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final pos = change >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code, style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text('${balance.toStringAsFixed(code == 'USDC' ? 2 : 4)} $code',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 11)),
              ],
            ),
          ),
          SizedBox(
            width: 56, height: 30,
            child: CustomPaint(
              painter: _SparklinePainter(
                points: points,
                color: pos ? DayFiColors.green : Colors.redAccent,
                fillColor: Colors.transparent,
                strokeWidth: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${usdValue.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text('${pos ? '+' : ''}${change.toStringAsFixed(2)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: pos ? DayFiColors.green : Colors.redAccent,
                  fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Allocation legend row ────────────────────────────────

class _AllocationLegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final double pct, value;

  const _AllocationLegendRow({
    required this.color, required this.label,
    required this.pct,   required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500))),
        Text('${(pct * 100).toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 11)),
        const SizedBox(width: 12),
        Text('\$${value.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600, fontSize: 12)),
      ],
    );
  }
}

// ─── Sparkline painter ────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color, fillColor;
  final double strokeWidth;

  const _SparklinePainter({
    required this.points, required this.color, required this.fillColor,
    this.strokeWidth = 1.8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final min   = points.reduce((a, b) => a < b ? a : b);
    final max   = points.reduce((a, b) => a > b ? a : b);
    final range = (max - min).clamp(0.001, double.infinity);
    final xStep = size.width / (points.length - 1);

    Offset pt(int i) => Offset(
      i * xStep,
      size.height - ((points[i] - min) / range) * size.height * 0.82 - size.height * 0.09,
    );

    final fill = Path()..moveTo(0, size.height);
    for (int i = 0; i < points.length; i++) fill.lineTo(pt(i).dx, pt(i).dy);
    fill..lineTo(size.width, size.height)..close();
    canvas.drawPath(fill, Paint()..color = fillColor..style = PaintingStyle.fill);

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < points.length; i++) {
      final p = pt(i - 1), c = pt(i);
      final cx = (p.dx + c.dx) / 2;
      line.cubicTo(cx, p.dy, cx, c.dy, c.dx, c.dy);
    }
    canvas.drawPath(line,
      Paint()
        ..color = color ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparklinePainter o) => o.points != points || o.color != color;
}

// ─── Donut painter ────────────────────────────────────────

class _DonutSegment {
  final double fraction;
  final Color color;
  const _DonutSegment({required this.fraction, required this.color});
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  const _DonutPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const sw = 12.0, gap = 0.04;
    final total = segments.fold<double>(0, (s, e) => s + e.fraction);
    double start = -3.14159 / 2;

    for (final seg in segments) {
      final sweep = (seg.fraction / total) * (2 * 3.14159) - gap;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - sw / 2),
        start, sweep, false,
        Paint()
          ..color = seg.color ..style = PaintingStyle.stroke
          ..strokeWidth = sw ..strokeCap = StrokeCap.round,
      );
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => o.segments != segments;
}