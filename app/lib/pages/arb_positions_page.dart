import 'package:flutter/material.dart';
import '../services/arb_manager.dart';
import '../services/funding_service.dart';
import '../services/trading_service.dart';

class ArbPositionsPage extends StatefulWidget {
  const ArbPositionsPage({super.key});
  @override
  State<ArbPositionsPage> createState() => _ArbPositionsPageState();
}

class _ArbPositionsPageState extends State<ArbPositionsPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<ArbPosition> _active = [];
  List<ArbPosition> _closed = [];
  bool _loading = true;
  bool _monitoring = false;
  Map<String, double>? _currentSpreads; // coin → current spread

  static const _blue = Color(0xFF007AFF);
  static const _bg = Color(0xFFF2F2F7);
  static const _label = Color(0xFF000000);
  static const _third = Color(0xFF8E8E93);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadPositions();
  }

  Future<void> _loadPositions() async {
    final active = await ArbDatabase.getActive();
    final closed = await ArbDatabase.getClosed();
    if (mounted) setState(() { _active = active; _closed = closed; _loading = false; });

    // Start monitoring if there are active positions (guard against duplicates)
    if (active.isNotEmpty && !_monitoring) {
      _startMonitoring();
    }
  }

  /// Foreground monitoring: check every 5 minutes if any position should auto-close.
  Future<void> _startMonitoring() async {
    _monitoring = true;
    while (mounted && _active.isNotEmpty) {
      await _checkAutoClose();
      await Future.delayed(const Duration(minutes: 5));
    }
    _monitoring = false;
  }

  /// Check current funding rates and auto-close positions if conditions met.
  Future<void> _checkAutoClose() async {
    if (_active.isEmpty) return;

    // Fetch current funding rates
    final fundingResult = await FundingService.fetchAll();

    for (final pos in List.of(_active)) {
      // Find current rates for this coin on both platforms
      final coinOpps = fundingResult.opportunities
          .where((o) => o.coin == pos.coin).toList();

      if (coinOpps.isEmpty) continue;

      // Find current spread between the two platforms
      final allRates = coinOpps.first.allRates;
      final longRate = allRates[pos.longPlatform];
      final shortRate = allRates[pos.shortPlatform];
      if (longRate == null || shortRate == null) continue;

      final currentSpread = shortRate - longRate;

      // Update UI with current spread
      (_currentSpreads ??= {})[pos.coin] = currentSpread;

      // Check close conditions
      bool shouldClose = false;
      String reason = '';

      // Condition 1: Spread below threshold
      if (currentSpread < pos.minSpreadToClose) {
        shouldClose = true;
        reason = '费率差收敛至 ${(currentSpread * 100).toStringAsFixed(4)}%';
      }

      // Condition 2: Max days exceeded
      if (pos.daysHeld >= pos.maxDays) {
        shouldClose = true;
        reason = '持仓已达 ${pos.maxDays} 天上限';
      }

      // Condition 3: Spread reversed (you're losing money)
      if (currentSpread < 0) {
        shouldClose = true;
        reason = '费率反转，当前亏损';
      }

      if (shouldClose) {
        // Auto close
        await _closePosition(pos);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${pos.coin} 自动平仓: $reason'),
            duration: const Duration(seconds: 5),
          ));
        }
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _closePosition(ArbPosition pos) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('确认平仓'),
      content: Text('将同时关闭 ${pos.coin} 在 ${pos.longPlatform} 和 ${pos.shortPlatform} 的仓位'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认平仓', style: TextStyle(color: _red))),
      ],
    ));
    if (confirm != true) return;

    // Execute close on both sides
    final results = await Future.wait([
      TradingService.placeMarketOrder(
        platform: pos.longPlatform.toLowerCase(),
        coin: pos.coin,
        side: 'SELL', // close long
        quantity: pos.quantity,
      ),
      TradingService.placeMarketOrder(
        platform: pos.shortPlatform.toLowerCase(),
        coin: pos.coin,
        side: 'BUY', // close short
        quantity: pos.quantity,
      ),
    ]);

    final updated = pos.copyWith(
      status: 'closed',
      closedAt: DateTime.now(),
      longClosePrice: results[0].filledPrice,
      shortClosePrice: results[1].filledPrice,
    );
    await ArbDatabase.update(updated);
    _loadPositions();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(results[0].success && results[1].success
            ? '平仓成功' : '平仓部分失败，请检查仓位'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28, color: _blue),
          onPressed: () => Navigator.pop(context)),
        title: const Text('我的套利仓位',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
        centerTitle: true,
        bottom: TabBar(controller: _tab,
          labelColor: _label, unselectedLabelColor: _third,
          indicatorColor: _blue, indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: '活跃 (${_active.length})'),
            Tab(text: '历史 (${_closed.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _blue))
          : TabBarView(controller: _tab, children: [
              _activeList(),
              _closedList(),
            ]),
    );
  }

  Widget _activeList() {
    if (_active.isEmpty) {
      return const Center(child: Text('暂无活跃套利仓位', style: TextStyle(color: _third, fontSize: 15)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _active.length,
      itemBuilder: (_, i) => _activeCard(_active[i]),
    );
  }

  Widget _closedList() {
    if (_closed.isEmpty) {
      return const Center(child: Text('暂无历史记录', style: TextStyle(color: _third, fontSize: 15)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _closed.length,
      itemBuilder: (_, i) => _closedCard(_closed[i]),
    );
  }

  Widget _activeCard(ArbPosition pos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Text(pos.coin, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _label)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: _green.withAlpha(15), borderRadius: BorderRadius.circular(4)),
            child: const Text('活跃', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _green)),
          ),
          const Spacer(),
          Text('\$${pos.positionSize.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _label)),
        ]),
        const SizedBox(height: 8),

        // Sides
        Text('做多 ${pos.longPlatform} · 做空 ${pos.shortPlatform}',
            style: const TextStyle(fontSize: 13, color: _third)),
        const SizedBox(height: 4),
        Text('开仓 ${pos.openedAt.toString().substring(0, 16)} · ${pos.daysHeld} 天',
            style: const TextStyle(fontSize: 12, color: _third)),
        const SizedBox(height: 4),
        Text('开仓年化 ${pos.annualizedAtOpen.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _green)),
        if (_currentSpreads != null && _currentSpreads!.containsKey(pos.coin)) ...[
          const SizedBox(height: 4),
          Builder(builder: (_) {
            final cs = _currentSpreads![pos.coin]!;
            final curAnnual = cs * 3 * 365 * 100;
            return Text('当前年化 ${curAnnual.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                    color: curAnnual > 5 ? _green : _red));
          }),
        ],

        const SizedBox(height: 12),
        // Close button
        SizedBox(width: double.infinity, height: 38,
          child: OutlinedButton(
            onPressed: () => _closePosition(pos),
            style: OutlinedButton.styleFrom(
              foregroundColor: _red, side: const BorderSide(color: _red, width: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('手动平仓', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ),
      ]),
    );
  }

  Widget _closedCard(ArbPosition pos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(pos.coin, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _label)),
          const Spacer(),
          if (pos.netProfit != null)
            Text('${pos.netProfit! >= 0 ? "+" : ""}\$${pos.netProfit!.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: pos.netProfit! >= 0 ? _green : _red)),
        ]),
        const SizedBox(height: 4),
        Text('${pos.longPlatform} ↔ ${pos.shortPlatform} · \$${pos.positionSize.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 12, color: _third)),
        Text('${pos.openedAt.toString().substring(0, 10)} → ${pos.closedAt?.toString().substring(0, 10) ?? "?"}',
            style: const TextStyle(fontSize: 12, color: _third)),
      ]),
    );
  }
}
