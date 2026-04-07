import 'package:flutter/material.dart';
import '../services/funding_service.dart';
import 'arb_detail_page.dart';

class FundingArbPage extends StatefulWidget {
  const FundingArbPage({super.key});
  @override
  State<FundingArbPage> createState() => _FundingArbPageState();
}

class _FundingArbPageState extends State<FundingArbPage> {
  bool _loading = true;
  FundingResult? _result;
  double _minAnnual = 10; // default filter: >10% annual
  final Map<String, bool> _expanded = {};

  static const _blue = Color(0xFF007AFF);
  static const _bg = Color(0xFFF2F2F7);
  static const _label = Color(0xFF000000);
  static const _second = Color(0xFF3C3C43);
  static const _third = Color(0xFF8E8E93);
  static const _sep = Color(0xFFE5E5EA);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await FundingService.fetchAll();
    if (mounted) setState(() { _result = result; _loading = false; });
  }

  List<ArbOpportunity> get _filtered =>
      _result?.opportunities.where((o) => o.annualizedPct >= _minAnnual).toList() ?? [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28, color: _blue),
          onPressed: () => Navigator.pop(context)),
        title: const Text('费率套利',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _blue))
            : RefreshIndicator(onRefresh: _load, color: _blue, child: _content()),
      ),
    );
  }

  Widget _content() {
    final r = _result!;
    final filtered = _filtered;

    return CustomScrollView(
      slivers: [
        // Stats bar
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                _stat('机会', '${filtered.length}', subtitle: '>${_minAnnual.toInt()}% 年化'),
                _stat('最高年化', filtered.isNotEmpty ? '${filtered.first.annualizedPct.toStringAsFixed(0)}%' : '-',
                    color: _green),
                _stat('数据源', '${r.sourcesLoaded}/8',
                    subtitle: r.failedSources.isNotEmpty ? '${r.failedSources.join("/")} 异常' : null),
              ]),
              const SizedBox(height: 12),
              // Filter slider
              Row(children: [
                Text('最低年化 ${_minAnnual.toInt()}%',
                    style: const TextStyle(fontSize: 12, color: _third)),
                Expanded(child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2, overlayColor: Colors.transparent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    activeTrackColor: _blue, inactiveTrackColor: _sep, thumbColor: _blue),
                  child: Slider(value: _minAnnual, min: 0, max: 100, divisions: 20,
                      onChanged: (v) => setState(() => _minAnnual = v)),
                )),
              ]),
            ]),
          ),
        )),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // List
        filtered.isEmpty
            ? SliverFillRemaining(child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('无符合条件的机会', style: TextStyle(fontSize: 15, color: _third)),
                  const SizedBox(height: 8),
                  Text('尝试降低年化阈值', style: TextStyle(fontSize: 13, color: _third.withAlpha(150))),
                ],
              )))
            : SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  if (i == filtered.length) return _riskDisclaimer();
                  return _arbCard(filtered[i]);
                },
                childCount: filtered.length + 1,
              )),
      ],
    );
  }

  Widget _stat(String label, String value, {Color? color, String? subtitle}) {
    return Expanded(child: Column(children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color ?? _label)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: _third)),
      if (subtitle != null)
        Text(subtitle, style: TextStyle(fontSize: 10, color: _red.withAlpha(180))),
    ]));
  }

  Widget _arbCard(ArbOpportunity opp) {
    final isExp = _expanded[opp.coin] ?? false;
    // Wrap with tap to navigate to detail
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ArbDetailPage(opp: opp))),
      child: _arbCardContent(opp, isExp),
    );
  }

  Widget _arbCardContent(ArbOpportunity opp, bool isExp) {
    // Determine if each side earns or pays
    // Long position: negative rate = you earn, positive rate = you pay
    // Short position: positive rate = you earn, negative rate = you pay
    final longEarns = opp.longRate8h < 0;
    final shortEarns = opp.shortRate8h > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header: coin + annual
          Row(children: [
            Text(opp.coin, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _label)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(4)),
              child: Text('${opp.allRates.length} 源',
                  style: const TextStyle(fontSize: 11, color: _third)),
            ),
            const Spacer(),
            Text('${opp.annualizedPct.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _green)),
          ]),
          const SizedBox(height: 2),
          Text('年化收益 (当前快照)', style: TextStyle(fontSize: 11, color: _third.withAlpha(180))),

          const SizedBox(height: 12),

          // Long side
          _sideRow(
            direction: '做多',
            platform: opp.longPlatform,
            rate: opp.longRate8h,
            earns: longEarns,
          ),
          const SizedBox(height: 6),
          // Short side
          _sideRow(
            direction: '做空',
            platform: opp.shortPlatform,
            rate: opp.shortRate8h,
            earns: shortEarns,
          ),

          // Expand all rates
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _expanded[opp.coin] = !isExp),
            child: Row(children: [
              Text(isExp ? '收起' : '全部费率',
                  style: const TextStyle(fontSize: 13, color: _blue)),
              Icon(isExp ? Icons.expand_less : Icons.expand_more, size: 16, color: _blue),
            ]),
          ),
          if (isExp) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 0, runSpacing: 4, children: () {
              final sorted = opp.allRates.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
              return sorted.map((e) {
                final isMin = e.key == opp.longPlatform;
                final isMax = e.key == opp.shortPlatform;
                return SizedBox(width: MediaQuery.of(context).size.width / 2 - 36, child: Row(children: [
                  SizedBox(width: 48, child: Text(e.key,
                      style: TextStyle(fontSize: 12, fontWeight: isMin || isMax ? FontWeight.w600 : FontWeight.w400,
                          color: isMin || isMax ? _label : _third))),
                  Text('${(e.value * 100).toStringAsFixed(4)}%',
                      style: TextStyle(fontSize: 12,
                          color: e.value > 0 ? _red : e.value < 0 ? _green : _third)),
                ]));
              }).toList();
            }()),
          ],
        ]),
      ),
    );
  }

  Widget _sideRow({
    required String direction,
    required String platform,
    required double rate,
    required bool earns,
  }) {
    return Row(children: [
      Container(
        width: 28, height: 18,
        decoration: BoxDecoration(
          color: direction == '做多' ? _green : _red,
          borderRadius: BorderRadius.circular(4)),
        child: Center(child: Text(direction,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white))),
      ),
      const SizedBox(width: 8),
      Text(platform, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _label)),
      const Spacer(),
      Text('${(rate * 100).toStringAsFixed(4)}%/8h',
          style: const TextStyle(fontSize: 13, color: _second)),
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

  Widget _riskDisclaimer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9E6),
          borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('风险提示', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF8B7000))),
          SizedBox(height: 6),
          Text(
            '费率每 1-8 小时变动，套利窗口可能随时关闭\n'
            '需在两个平台同时开仓，存在执行时差和滑点\n'
            '需两边保证金，资金利用率约 50%\n'
            '展示年化基于当前快照，非保证收益\n'
            '小币种流动性风险高，大额仓位滑点大',
            style: TextStyle(fontSize: 12, color: Color(0xFF8B7000), height: 1.6),
          ),
        ]),
      ),
    );
  }
}
