import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/funding_service.dart';
import '../services/trading_service.dart';
import '../services/key_storage.dart';
import '../services/arb_manager.dart';
import '../widgets/funding_chart.dart';

class ArbDetailPage extends StatefulWidget {
  final ArbOpportunity opp;
  const ArbDetailPage({super.key, required this.opp});
  @override
  State<ArbDetailPage> createState() => _ArbDetailPageState();
}

class _ArbDetailPageState extends State<ArbDetailPage> {
  int _periodIdx = 1; // 0=24h, 1=7d, 2=30d
  Map<String, List<FundingPoint>>? _chartData;
  bool _loadingChart = true;

  static const _periods = [
    ('24h', Duration(hours: 24)),
    ('7d', Duration(days: 7)),
    ('30d', Duration(days: 30)),
  ];

  static const _blue = Color(0xFF007AFF);
  static const _bg = Color(0xFFF2F2F7);
  static const _label = Color(0xFF000000);
  static const _third = Color(0xFF8E8E93);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);

  @override
  void initState() {
    super.initState();
    _loadChart();
  }

  Future<void> _loadChart() async {
    setState(() => _loadingChart = true);
    final history = await FundingService.fetchHistory(
        widget.opp.coin, _periods[_periodIdx].$2);

    final chartData = <String, List<FundingPoint>>{};
    for (final entry in history.entries) {
      chartData[entry.key] = entry.value
          .map((p) => FundingPoint(time: p.time, rate8h: p.rate8h))
          .toList();
    }

    if (mounted) setState(() { _chartData = chartData; _loadingChart = false; });
  }

  ArbOpportunity get opp => widget.opp;

  @override
  Widget build(BuildContext context) {
    final longEarns = opp.longRate8h < 0;
    final shortEarns = opp.shortRate8h > 0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28, color: _blue),
          onPressed: () => Navigator.pop(context)),
        title: Text(opp.coin,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
        centerTitle: true,
      ),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
        // ── Overview card ──
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('年化 ${opp.annualizedPct.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _green)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(6)),
              child: Text('${opp.allRates.length} 源',
                  style: const TextStyle(fontSize: 12, color: _third)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('费率差 ${(opp.spread8h * 100).toStringAsFixed(4)}%/8h',
              style: const TextStyle(fontSize: 13, color: _third)),
          const SizedBox(height: 16),

          _sideRow('做多', opp.longPlatform, opp.longRate8h, longEarns),
          const SizedBox(height: 8),
          _sideRow('做空', opp.shortPlatform, opp.shortRate8h, shortEarns),

          const SizedBox(height: 14),
          Container(height: 0.5, color: const Color(0xFFE5E5EA)),
          const SizedBox(height: 10),

          // All platform rates
          const Text('全平台费率 (8h)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _label)),
          const SizedBox(height: 8),
          ...(() {
            final sorted = opp.allRates.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
            return sorted.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 60, child: Text(e.key,
                    style: TextStyle(fontSize: 13,
                        fontWeight: e.key == opp.longPlatform || e.key == opp.shortPlatform
                            ? FontWeight.w600 : FontWeight.w400,
                        color: _label))),
                Expanded(child: Container(height: 0.5, color: const Color(0xFFF0F0F0))),
                const SizedBox(width: 8),
                Text('${(e.value * 100).toStringAsFixed(4)}%',
                    style: TextStyle(fontSize: 13,
                        color: e.value > 0 ? _red : e.value < 0 ? _green : _third)),
              ]),
            ));
          })(),
        ])),
        const SizedBox(height: 16),

        // ── History chart ──
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('历史费率', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _label)),
            const Spacer(),
            // Period tabs
            ...List.generate(_periods.length, (i) => GestureDetector(
              onTap: () => setState(() { _periodIdx = i; _loadChart(); }),
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _periodIdx == i ? _label : Colors.transparent,
                  borderRadius: BorderRadius.circular(6)),
                child: Text(_periods[i].$1,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                        color: _periodIdx == i ? Colors.white : _third)),
              ),
            )),
          ]),
          const SizedBox(height: 16),
          if (_loadingChart)
            const SizedBox(height: 180,
                child: Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: _blue)))
          else if (_chartData == null || _chartData!.isEmpty)
            const SizedBox(height: 180,
                child: Center(child: Text('无历史数据', style: TextStyle(color: _third, fontSize: 13))))
          else
            FundingChart(series: _chartData!, height: 180),
        ])),
        const SizedBox(height: 16),

        // ── Execute section ──
        _card(child: _ExecuteSection(opp: opp)),

        // Risk disclaimer
        Padding(padding: const EdgeInsets.fromLTRB(0, 16, 0, 40),
          child: Text(
            '费率每 1-8 小时变动，窗口可能关闭。需两平台同时开仓，存在执行时差。年化基于当前快照。',
            style: TextStyle(fontSize: 11, color: _third.withAlpha(180), height: 1.5),
          ),
        ),
      ]),
    );
  }

  Widget _sideRow(String dir, String platform, double rate, bool earns) {
    return Row(children: [
      Container(width: 28, height: 18,
        decoration: BoxDecoration(
          color: dir == '做多' ? _green : _red, borderRadius: BorderRadius.circular(4)),
        child: Center(child: Text(dir,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white))),
      ),
      const SizedBox(width: 8),
      Text(platform, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _label)),
      const Spacer(),
      Text('${(rate * 100).toStringAsFixed(4)}%/8h',
          style: const TextStyle(fontSize: 14, color: Color(0xFF3C3C43))),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: earns ? _green.withAlpha(15) : _red.withAlpha(15),
          borderRadius: BorderRadius.circular(4)),
        child: Text(earns ? '收入' : '支出',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: earns ? _green : _red)),
      ),
    ]);
  }

  Widget _card({required Widget child}) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    padding: const EdgeInsets.all(16), child: child);
}

// ══════════════════════════════════════
// Execute Section — amount input → confirm → execute → result
// ══════════════════════════════════════

class _ExecuteSection extends StatefulWidget {
  final ArbOpportunity opp;
  const _ExecuteSection({required this.opp});
  @override
  State<_ExecuteSection> createState() => _ExecuteSectionState();
}

class _ExecuteSectionState extends State<_ExecuteSection> {
  final _amountCtrl = TextEditingController(text: '1000');
  String _state = 'input'; // input, confirming, executing, success, error
  bool _longReady = false;
  bool _shortReady = false;
  OrderResult? _longResult;
  OrderResult? _shortResult;
  String? _errorMsg;

  static const _blue = Color(0xFF007AFF);
  static const _label = Color(0xFF000000);
  static const _third = Color(0xFF8E8E93);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);
  static const _bg = Color(0xFFF2F2F7);

  ArbOpportunity get opp => widget.opp;

  @override
  void initState() {
    super.initState();
    _checkKeys();
  }

  // Platforms that support API order execution
  static const _executablePlatforms = {'binance', 'bybit', 'okx', 'bitget', 'gate', 'mexc'};

  bool get _longExecutable => _executablePlatforms.contains(opp.longPlatform.toLowerCase());
  bool get _shortExecutable => _executablePlatforms.contains(opp.shortPlatform.toLowerCase());
  bool get _bothExecutable => _longExecutable && _shortExecutable;

  Future<void> _checkKeys() async {
    if (_longExecutable) _longReady = await KeyStorage.isConfigured(opp.longPlatform.toLowerCase());
    if (_shortExecutable) _shortReady = await KeyStorage.isConfigured(opp.shortPlatform.toLowerCase());
    if (mounted) setState(() {});
  }

  Future<void> _execute() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount < 10) {
      setState(() { _errorMsg = '最小金额 \$10'; });
      return;
    }

    setState(() { _state = 'executing'; _errorMsg = null; });

    // Re-fetch funding rates to confirm spread still exists
    try {
      final freshRates = await FundingService.fetchAll();
      final freshOpp = freshRates.opportunities.where((o) => o.coin == opp.coin).firstOrNull;
      if (freshOpp == null || freshOpp.annualizedPct < 5) {
        setState(() { _state = 'error'; _errorMsg = '费率差已收敛，套利机会已关闭'; });
        return;
      }
    } catch (_) {
      // If can't verify, warn but allow execution
    }

    // Fetch current price to calculate coin quantity
    double? currentPrice;
    try {
      final priceRes = await http.post(
        Uri.parse('https://api.hyperliquid.xyz/info'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'type': 'allMids'}),
      ).timeout(const Duration(seconds: 10));
      if (priceRes.statusCode == 200) {
        final prices = jsonDecode(priceRes.body) as Map<String, dynamic>;
        currentPrice = double.tryParse(prices[opp.coin]?.toString() ?? '');
      }
    } catch (_) {}

    if (currentPrice == null || currentPrice <= 0) {
      setState(() { _state = 'error'; _errorMsg = '无法获取 ${opp.coin} 当前价格'; });
      return;
    }

    final qty = amount / currentPrice; // Convert USD amount to coin quantity

    // Execute both sides in parallel
    final results = await Future.wait([
      TradingService.placeMarketOrder(
        platform: opp.longPlatform.toLowerCase(),
        coin: opp.coin,
        side: 'BUY',
        quantity: qty,
      ),
      TradingService.placeMarketOrder(
        platform: opp.shortPlatform.toLowerCase(),
        coin: opp.coin,
        side: 'SELL',
        quantity: qty,
      ),
    ]);

    _longResult = results[0];
    _shortResult = results[1];

    if (_longResult!.success && _shortResult!.success) {
      // Both succeeded — save position record
      final pos = ArbPosition(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        coin: opp.coin,
        longPlatform: opp.longPlatform,
        shortPlatform: opp.shortPlatform,
        positionSize: amount,
        quantity: qty,
        longEntryPrice: _longResult!.filledPrice ?? 0,
        shortEntryPrice: _shortResult!.filledPrice ?? 0,
        longRate8hAtOpen: opp.longRate8h,
        shortRate8hAtOpen: opp.shortRate8h,
        openedAt: DateTime.now(),
      );
      await ArbDatabase.insert(pos);
      setState(() => _state = 'success');
    } else if (_longResult!.success && !_shortResult!.success) {
      // Long succeeded, short failed — try to cancel long
      await TradingService.cancelOrder(
        platform: opp.longPlatform.toLowerCase(),
        coin: opp.coin,
        orderId: _longResult!.orderId ?? '',
      );
      setState(() {
        _state = 'error';
        _errorMsg = '做空侧失败: ${_shortResult!.error}\n已尝试撤销做多侧，请检查仓位';
      });
    } else if (!_longResult!.success && _shortResult!.success) {
      // Short succeeded, long failed — try to cancel short
      await TradingService.cancelOrder(
        platform: opp.shortPlatform.toLowerCase(),
        coin: opp.coin,
        orderId: _shortResult!.orderId ?? '',
      );
      setState(() {
        _state = 'error';
        _errorMsg = '做多侧失败: ${_longResult!.error}\n已尝试撤销做空侧，请检查仓位';
      });
    } else {
      setState(() {
        _state = 'error';
        _errorMsg = '两侧均失败\n多: ${_longResult!.error}\n空: ${_shortResult!.error}';
      });
    }
  }

  @override
  void dispose() { _amountCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('执行套利', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _label)),
      const SizedBox(height: 8),

      if (!_bothExecutable) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 16, color: _third),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '${!_longExecutable ? opp.longPlatform : opp.shortPlatform} 暂不支持 API 下单'
              '${opp.longPlatform == "HL" || opp.shortPlatform == "HL" ? "（Hyperliquid 需链上签名，开发中）" : ""}。'
              '\n请在各平台手动执行此套利。',
              style: const TextStyle(fontSize: 13, color: _third, height: 1.4),
            )),
          ]),
        ),
      ] else if (!_longReady || !_shortReady) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: _third),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '需配置 ${!_longReady ? opp.longPlatform : ""}'
              '${!_longReady && !_shortReady ? " 和 " : ""}'
              '${!_shortReady ? opp.shortPlatform : ""} 的 API Key',
              style: const TextStyle(fontSize: 13, color: _third),
            )),
          ]),
        ),
      ] else if (_state == 'input' || _state == 'confirming') ...[
        // Amount input
        const Text('投入金额 (USD)', style: TextStyle(fontSize: 13, color: _third)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _label),
            decoration: const InputDecoration(
              prefixText: '\$ ', border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        const SizedBox(height: 8),

        // Preview
        Builder(builder: (_) {
          final amt = double.tryParse(_amountCtrl.text) ?? 1000;
          // Fee estimate per platform (taker fees vary)
          const feeRates = {'HL': 0.00035, 'Binance': 0.0005, 'Bybit': 0.00055,
            'OKX': 0.0005, 'Bitget': 0.0006, 'Gate': 0.00065, 'MEXC': 0.0006, 'dYdX': 0.0005};
          final longFee = feeRates[opp.longPlatform] ?? 0.0005;
          final shortFee = feeRates[opp.shortPlatform] ?? 0.0005;
          final feeEst = amt * (longFee + shortFee) * 2; // open + close both sides
          final dailyEarn = amt * opp.spread8h * 3;
          final breakEvenDays = dailyEarn > 0 ? (feeEst / dailyEarn).ceil() : 999;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _infoRow('预计费率日收入', '\$${dailyEarn.toStringAsFixed(2)}'),
            _infoRow('开仓手续费 (约)', '\$${feeEst.toStringAsFixed(2)}'),
            _infoRow('回本周期 (约)', '$breakEvenDays 天'),
          ]);
        }),

        if (_errorMsg != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_errorMsg!, style: const TextStyle(fontSize: 13, color: _red))),

        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 46,
          child: ElevatedButton(
            onPressed: _execute,
            style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white,
                elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('确认执行', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ] else if (_state == 'executing') ...[
        const SizedBox(height: 16),
        const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(strokeWidth: 2, color: _blue),
          SizedBox(height: 12),
          Text('正在同时下单...', style: TextStyle(fontSize: 14, color: _third)),
        ])),
        const SizedBox(height: 16),
      ] else if (_state == 'success') ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _green.withAlpha(10), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.check_circle, size: 18, color: _green),
              const SizedBox(width: 8),
              const Text('套利仓位已建立', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _green)),
            ]),
            const SizedBox(height: 8),
            Text('做多 ${opp.longPlatform}: ${_longResult?.orderId ?? "成功"}',
                style: const TextStyle(fontSize: 13, color: _third)),
            Text('做空 ${opp.shortPlatform}: ${_shortResult?.orderId ?? "成功"}',
                style: const TextStyle(fontSize: 13, color: _third)),
          ]),
        ),
      ] else if (_state == 'error') ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _red.withAlpha(10), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.error_outline, size: 18, color: _red),
              const SizedBox(width: 8),
              const Text('执行失败', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _red)),
            ]),
            const SizedBox(height: 8),
            Text(_errorMsg ?? '未知错误', style: const TextStyle(fontSize: 13, color: _third)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() { _state = 'input'; _errorMsg = null; }),
              child: const Text('重试', style: TextStyle(fontSize: 14, color: _blue)),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: _third)),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _label)),
    ]),
  );
}
