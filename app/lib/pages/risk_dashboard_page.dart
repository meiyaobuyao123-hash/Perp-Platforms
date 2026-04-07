import 'dart:math';
import 'package:flutter/material.dart';
import '../services/position_service.dart';

class RiskDashboardPage extends StatefulWidget {
  const RiskDashboardPage({super.key});
  @override
  State<RiskDashboardPage> createState() => _RiskDashboardPageState();
}

class _RiskDashboardPageState extends State<RiskDashboardPage> {
  final _evmCtrl = TextEditingController();
  final _dydxCtrl = TextEditingController();
  bool _showDydx = false;
  bool _loading = false;
  PortfolioResult? _result;
  String? _error;
  double _stressPct = -10;
  final Map<String, bool> _expanded = {};

  // Apple system colors
  static const _blue = Color(0xFF007AFF);
  static const _bg = Color(0xFFF2F2F7);
  static const _label = Color(0xFF000000);
  static const _second = Color(0xFF3C3C43);
  static const _third = Color(0xFF8E8E93);
  static const _sep = Color(0xFFE5E5EA);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);

  Future<void> _query() async {
    var evm = _evmCtrl.text.trim();
    // Auto-prepend 0x if missing
    if (evm.isNotEmpty && !evm.startsWith('0x') && evm.length == 40) {
      evm = '0x$evm';
      _evmCtrl.text = evm;
    }
    if (evm.isEmpty || !evm.startsWith('0x') || evm.length != 42) {
      setState(() => _error = '请输入有效的 EVM 地址 (0x...)');
      return;
    }
    final dydx = _showDydx ? _dydxCtrl.text.trim() : null;
    if (dydx != null && dydx.isNotEmpty && !dydx.startsWith('dydx1')) {
      setState(() => _error = 'dYdX 地址应以 dydx1 开头');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final result = await PositionService.fetchAll(
      evmAddress: evm,
      dydxAddress: (dydx != null && dydx.isNotEmpty) ? dydx : null,
    );
    if (mounted) setState(() { _loading = false; _result = result; });
  }

  @override
  void dispose() { _evmCtrl.dispose(); _dydxCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28, color: _blue),
          onPressed: () => Navigator.pop(context)),
        title: const Text('跨DEX风控',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
        centerTitle: true,
      ),
      body: SafeArea(child: _result == null ? _inputView() : _resultView()),
    );
  }

  // ════════════════════════════════════
  // Input
  // ════════════════════════════════════

  Widget _inputView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 24),
        const Text('输入钱包地址',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: _label, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        const Text('自动查询 Hyperliquid / GMX / Aster / Lighter / dYdX',
            style: TextStyle(fontSize: 15, color: _third)),
        const SizedBox(height: 28),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(controller: _evmCtrl, style: const TextStyle(fontSize: 15, color: _label),
              decoration: const InputDecoration(hintText: '0x...', hintStyle: TextStyle(color: Color(0xFFC7C7CC)),
                  border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 16))),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _showDydx = !_showDydx),
          child: Text(_showDydx ? '- 收起 dYdX 地址' : '+ 添加 dYdX 地址（可选）',
              style: const TextStyle(fontSize: 14, color: _blue)),
        ),
        if (_showDydx) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(controller: _dydxCtrl, style: const TextStyle(fontSize: 15, color: _label),
                decoration: const InputDecoration(hintText: 'dydx1...', hintStyle: TextStyle(color: Color(0xFFC7C7CC)),
                    border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 16))),
          ),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(fontSize: 14, color: _red))),
        const SizedBox(height: 28),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _loading ? null : _query,
            style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white,
                elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('查询仓位', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  // ════════════════════════════════════
  // Result
  // ════════════════════════════════════

  Widget _resultView() {
    final r = _result!;
    final active = r.platforms.where((p) => p.positions.isNotEmpty).toList();
    final hedges = r.findHedges();
    final coins = <String>{};
    for (final p in r.platforms) for (final pos in p.positions) coins.add(pos.coin.toUpperCase());
    final coinList = coins.toList()..sort();

    // Risk level
    final riskColor = r.marginUsagePercent > 80 ? _red : r.marginUsagePercent > 50 ? const Color(0xFFFF9500) : _green;

    return RefreshIndicator(
      onRefresh: _query, color: _blue,
      child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
        const SizedBox(height: 4),
        // Address pill
        GestureDetector(
          onTap: () => setState(() => _result = null),
          child: Row(children: [
            Text('${_evmCtrl.text.substring(0, 6)}...${_evmCtrl.text.substring(38)}',
                style: const TextStyle(fontSize: 13, color: _third, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(width: 6),
            const Text('切换', style: TextStyle(fontSize: 13, color: _blue)),
          ]),
        ),
        const SizedBox(height: 20),

        // ── 第一层：指标概览 ──
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            // Top row: ring + key number
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Small ring
              SizedBox(width: 56, height: 56, child: CustomPaint(
                painter: _RingPainter(percent: r.marginUsagePercent / 100, color: riskColor),
                child: Center(child: Text('${r.marginUsagePercent.toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: riskColor))),
              )),
              const SizedBox(width: 20),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('\$${_f(r.totalAccountValue)}',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: _label, letterSpacing: -1)),
                const SizedBox(height: 2),
                Row(children: [
                  Text('${r.totalUnrealizedPnl >= 0 ? "+" : ""}\$${_f(r.totalUnrealizedPnl)}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                          color: r.totalUnrealizedPnl >= 0 ? _green : _red)),
                  const SizedBox(width: 12),
                  Text('${r.totalPositions} 个仓位', style: const TextStyle(fontSize: 14, color: _third)),
                ]),
              ])),
            ]),
            // Platform tags
            if (active.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(height: 0.5, color: _sep),
              const SizedBox(height: 12),
              Row(children: active.map((p) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${p.name}  \$${_f(p.accountValue)}',
                    style: const TextStyle(fontSize: 12, color: _third)),
              )).toList()),
            ],
          ]),
        ),
        const SizedBox(height: 20),

        // ── 第二层：仓位明细 ──
        ...active.map((p) => _platformCard(p)),

        // ── 第三层：压力测试 ──
        if (coinList.isNotEmpty) ...[
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('压力测试', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _stressPct < 0 ? _red.withAlpha(15) : _green.withAlpha(15),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('${_stressPct >= 0 ? "+" : ""}${_stressPct.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          color: _stressPct < 0 ? _red : _green)),
                ),
              ]),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  activeTrackColor: _stressPct < 0 ? _red : _green,
                  inactiveTrackColor: _sep, overlayColor: Colors.transparent,
                  thumbColor: _stressPct < 0 ? _red : _green),
                child: Slider(value: _stressPct, min: -50, max: 50, divisions: 100,
                    onChanged: (v) => setState(() => _stressPct = v)),
              ),
              const SizedBox(height: 8),
              ...coinList.map((coin) {
                final impact = r.stressTest(coin, _stressPct / 100);
                if (impact.abs() < 0.01) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 56, child: Text(coin, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _label))),
                    const Spacer(),
                    Text('${impact >= 0 ? "+" : ""}\$${_f(impact)}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                            color: impact >= 0 ? _green : _red)),
                  ]),
                );
              }),
              Padding(padding: const EdgeInsets.only(top: 8),
                child: Container(height: 0.5, color: _sep)),
              Padding(padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  const Text('合计', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _label)),
                  const Spacer(),
                  Builder(builder: (_) {
                    double total = 0;
                    for (final c in coinList) total += r.stressTest(c, _stressPct / 100);
                    return Text('${total >= 0 ? "+" : ""}\$${_f(total)}',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                            color: total >= 0 ? _green : _red));
                  }),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // Hedges
        if (hedges.isNotEmpty)
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('对冲提示', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _label)),
              const SizedBox(height: 8),
              ...hedges.map((h) => Padding(padding: const EdgeInsets.only(bottom: 4),
                  child: Text(h, style: const TextStyle(fontSize: 13, color: _third)))),
            ]),
          ),
        // Bottom: platforms checked summary
        const SizedBox(height: 20),
        Builder(builder: (_) {
          final empty = r.platforms.where((p) => p.positions.isEmpty && p.error == null).toList();
          final failed = r.platforms.where((p) => p.error != null).toList();
          if (empty.isEmpty && failed.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(children: [
              if (empty.isNotEmpty)
                Text('${empty.map((p) => p.name).join(" / ")} 已查询，无仓位',
                    style: const TextStyle(fontSize: 12, color: _third)),
              if (failed.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4),
                  child: Text('${failed.map((p) => p.name).join(" / ")} 查询异常',
                      style: TextStyle(fontSize: 12, color: _red.withAlpha(180)))),
            ]),
          );
        }),
        const SizedBox(height: 32),
      ]),
    );
  }

  // ── Platform Card ──

  Widget _platformCard(PlatformSummary p) {
    final key = p.name;
    final isExp = _expanded[key] ?? false;
    final show = isExp ? p.positions : p.positions.take(3).toList();
    final hasMore = p.positions.length > 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
          const SizedBox(width: 8),
          Text('${p.positions.length}', style: const TextStyle(fontSize: 13, color: _third)),
          const Spacer(),
          Text('\$${_f(p.accountValue)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
        ]),
        const SizedBox(height: 12),

        // Position rows
        ...show.asMap().entries.map((e) {
          final i = e.key;
          final pos = e.value;
          return Column(children: [
            if (i > 0) Container(height: 0.5, color: _sep, margin: const EdgeInsets.symmetric(vertical: 10)),
            // Row 1
            Row(children: [
              // Direction badge
              Container(
                width: 28, height: 18,
                decoration: BoxDecoration(
                  color: pos.isLong ? _green : _red,
                  borderRadius: BorderRadius.circular(4)),
                child: Center(child: Text(pos.isLong ? '多' : '空',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white))),
              ),
              const SizedBox(width: 8),
              Text(pos.coin, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _label)),
              if (pos.leverageValue > 0) ...[
                const SizedBox(width: 6),
                Text('${pos.leverageValue}x', style: const TextStyle(fontSize: 13, color: _third)),
              ],
              const Spacer(),
              Text('${pos.unrealizedPnl >= 0 ? "+" : ""}\$${_f(pos.unrealizedPnl)}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                      color: pos.unrealizedPnl >= 0 ? _green : _red)),
            ]),
            const SizedBox(height: 4),
            // Row 2
            Row(children: [
              const SizedBox(width: 36), // align with coin name
              Text('\$${_f(pos.size)}', style: const TextStyle(fontSize: 13, color: _third)),
              if (pos.entryPrice > 0) ...[
                const SizedBox(width: 12),
                Text('入场 ${_fp(pos.entryPrice)}', style: const TextStyle(fontSize: 13, color: _third)),
              ],
              if (pos.liquidationPrice != null && pos.liquidationPrice! > 0) ...[
                const SizedBox(width: 12),
                Text('清算 ${_fp(pos.liquidationPrice!)}', style: TextStyle(fontSize: 13, color: _red.withAlpha(200))),
              ],
            ]),
          ]);
        }),

        // Expand
        if (hasMore) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _expanded[key] = !isExp),
            child: Center(child: Text(isExp ? '收起' : '展开全部 ${p.positions.length} 个',
                style: const TextStyle(fontSize: 14, color: _blue))),
          ),
        ],
        const SizedBox(height: 4),
      ]),
    );
  }

  String _f(double n) {
    final a = n.abs();
    if (a >= 1e6) return '${(n / 1e6).toStringAsFixed(2)}M';
    if (a >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toStringAsFixed(a < 1 ? 2 : 0);
  }

  String _fp(double p) {
    if (p >= 10000) return p.toStringAsFixed(0);
    if (p >= 100) return p.toStringAsFixed(1);
    if (p >= 1) return p.toStringAsFixed(2);
    return p.toStringAsFixed(4);
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color color;
  _RingPainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFF2F2F7)..style = PaintingStyle.stroke..strokeWidth = 5);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2, 2 * pi * percent.clamp(0, 1), false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.percent != percent || o.color != color;
}
