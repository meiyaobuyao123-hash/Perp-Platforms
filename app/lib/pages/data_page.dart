import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

// ──────────────────────────────────────
// Models
// ──────────────────────────────────────

class ProfitTier {
  final String label;
  final Color color;
  final int count;
  final double pct;

  const ProfitTier({
    required this.label,
    required this.color,
    required this.count,
    required this.pct,
  });
}

class PlatformData {
  final String name;
  final List<ProfitTier> tiers;
  final int totalAddresses;
  final int profitCount;
  final int lossCount;
  final double profitPct;
  final String source;
  final String scope;
  final String updateFreq;
  final bool ready;

  const PlatformData({
    required this.name,
    required this.tiers,
    required this.totalAddresses,
    required this.profitCount,
    required this.lossCount,
    required this.profitPct,
    required this.source,
    required this.scope,
    required this.updateFreq,
    this.ready = true,
  });
}

// ──────────────────────────────────────
// Theme
// ──────────────────────────────────────

class _S {
  // Muted, warm palette
  static const tier1 = Color(0xFFF5A623); // warm amber
  static const tier2 = Color(0xFF9B6FD0); // soft purple
  static const tier3 = Color(0xFF4A90D9); // calm blue
  static const tier4 = Color(0xFF7EC8E3); // sky
  static const tierLoss = Color(0xFFE8695A); // muted coral

  static const green = Color(0xFF4CAF6E);
  static const red = Color(0xFFE8695A);

  static const label = Color(0xFF2C2C2E);
  static const sub = Color(0xFF8A8A8E);
  static const hint = Color(0xFFAEAEB2);
  static const divider = Color(0xFFF0F0F0);
  static const bg = Color(0xFFF5F5F7);
  static const card = Colors.white;
  static const accent = Color(0xFF007AFF);
}

// ──────────────────────────────────────
// API
// ──────────────────────────────────────

class _Api {
  static PlatformData _build(
    String name,
    List<double> allPnls,
    String source,
    String scope,
    String freq,
  ) {
    final profitList = allPnls.where((p) => p > 0).toList();
    final lossList = allPnls.where((p) => p <= 0).toList();
    final total = allPnls.length;
    final profitPct = total > 0 ? profitList.length / total * 100 : 0.0;

    final defs = [
      ('>\$1M', 1000000.0, double.infinity, _S.tier1),
      ('\$100K-\$1M', 100000.0, 1000000.0, _S.tier2),
      ('\$1K-\$100K', 1000.0, 100000.0, _S.tier3),
      ('\$0-\$1K', 0.0, 1000.0, _S.tier4),
    ];

    final tiers = <ProfitTier>[];
    for (final d in defs) {
      final list = d.$3 == double.infinity
          ? profitList.where((p) => p > d.$2)
          : profitList.where((p) => p > d.$2 && p <= d.$3);
      tiers.add(ProfitTier(
          label: d.$1,
          color: d.$4,
          count: list.length,
          pct: total > 0 ? list.length / total * 100 : 0));
    }
    tiers.add(ProfitTier(
        label: '亏损',
        color: _S.tierLoss,
        count: lossList.length,
        pct: total > 0 ? lossList.length / total * 100 : 0));

    return PlatformData(
      name: name,
      tiers: tiers,
      totalAddresses: total,
      profitCount: profitList.length,
      lossCount: lossList.length,
      profitPct: profitPct,
      source: source,
      scope: scope,
      updateFreq: freq,
    );
  }

  // Load pre-processed distribution from local asset.
  // Production: replace with backend proxy URL for real-time data.
  // Raw leaderboard is 27MB — too large for mobile direct download.
  static Future<PlatformData> hyperliquid() async {
    final raw = await rootBundle.loadString('assets/hyperliquid_distribution.json');
    final j = jsonDecode(raw);
    final tiers = (j['tiers'] as List).map<ProfitTier>((t) {
      final label = t['label'] == 'loss' ? '亏损' : t['label'] as String;
      final color = t['label'] == 'loss'
          ? _S.tierLoss
          : t['label'] == '>\$1M'
              ? _S.tier1
              : t['label'] == '\$100K-\$1M'
                  ? _S.tier2
                  : t['label'] == '\$1K-\$100K'
                      ? _S.tier3
                      : _S.tier4;
      return ProfitTier(
          label: label,
          color: color,
          count: t['count'] as int,
          pct: (t['pct'] as num).toDouble());
    }).toList();

    return PlatformData(
      name: j['platform'] as String,
      tiers: tiers,
      totalAddresses: j['totalAddresses'] as int,
      profitCount: j['profitCount'] as int,
      lossCount: j['lossCount'] as int,
      profitPct: (j['profitPct'] as num).toDouble(),
      source: j['source'] as String,
      scope: j['scope'] as String,
      updateFreq: j['updateFreq'] as String,
    );
  }

  static PlatformData pending(String name) => PlatformData(
      name: name,
      tiers: const [],
      totalAddresses: 0,
      profitCount: 0,
      lossCount: 0,
      profitPct: 0,
      source: '暂无公开 API',
      scope: '',
      updateFreq: '',
      ready: false);
}

// ──────────────────────────────────────
// Page
// ──────────────────────────────────────

class DataPage extends StatefulWidget {
  const DataPage({super.key});
  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  late List<PlatformData> _data;
  bool _initial = true;
  Map<String, dynamic>? _profile;

  static const _names = ['Hyperliquid'];

  @override
  void initState() {
    super.initState();
    _data = _names.map(_Api.pending).toList();
    _load();
  }

  Future<void> _load() async {
    try { _data[0] = await _Api.hyperliquid(); } catch (_) {}
    try {
      final raw = await rootBundle.loadString('assets/profitable_profile.json');
      _profile = jsonDecode(raw);
    } catch (_) {}
    if (mounted) setState(() => _initial = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _S.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _S.accent,
          child: ListView(
            children: [
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('数据',
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: _S.label,
                        letterSpacing: -0.5)),
              ),
              const SizedBox(height: 16),

              if (_initial)
                const SizedBox(
                    height: 280,
                    child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: _S.hint)))
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Card(
                      data: _data[0],
                      onInfo: () => _showInfo(context, _data[0])),
                ),
              // Profile card
              if (_profile != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ProfileCard(data: _profile!),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfo(BuildContext ctx, PlatformData d) {
    showModalBottomSheet(
        context: ctx,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _InfoSheet(data: d));
  }
}

// ──────────────────────────────────────
// Card
// ──────────────────────────────────────

class _Card extends StatelessWidget {
  final PlatformData data;
  final VoidCallback onInfo;
  const _Card({required this.data, required this.onInfo});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _S.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: data.ready ? _live() : _pending(),
    );
  }

  Widget _pending() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(data.name,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: _S.label)),
          const SizedBox(height: 8),
          const Text('数据接入中',
              style: TextStyle(fontSize: 14, color: _S.hint)),
        ]),
      );

  Widget _live() {
    const th = 34.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — single line, compact
          Row(
            children: [
              Text('交易者盈亏',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: _S.label)),
              const SizedBox(width: 6),
              Text('${data.name} · ${_fc(data.totalAddresses)}',
                  style: const TextStyle(fontSize: 12, color: _S.hint)),
              const Spacer(),
              GestureDetector(
                onTap: onInfo,
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _S.bg),
                  child: const Center(
                      child: Text('?',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _S.sub))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Pyramid + Legend
          SizedBox(
            height: th * data.tiers.length,
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: CustomPaint(
                    size: Size(90, th * data.tiers.length),
                    painter: _PyramidPainter(tiers: data.tiers, tierH: th),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: data.tiers.map((t) => SizedBox(
                      height: th,
                      child: Row(
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                                color: t.color, borderRadius: BorderRadius.circular(1.5))),
                          const SizedBox(width: 5),
                          Expanded(child: Text(t.label,
                              style: const TextStyle(fontSize: 13, color: _S.label))),
                          Text(_fc(t.count),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700, color: _S.label)),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 40,
                            child: Text(
                                t.pct < 0.01 ? '<0.01%' : '${t.pct.toStringAsFixed(1)}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 11, color: _S.sub)),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Row(children: [
                Expanded(
                    flex: (data.profitPct * 10).round().clamp(1, 999),
                    child: Container(color: _S.green)),
                Expanded(
                    flex: ((100 - data.profitPct) * 10).round().clamp(1, 999),
                    child: Container(color: _S.red)),
              ]),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${data.profitPct.toStringAsFixed(1)}% 盈利',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _S.green)),
              Text('${(100 - data.profitPct).toStringAsFixed(1)}% 亏损',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _S.red)),
            ],
          ),
        ],
      ),
    );
  }

  static String _fc(int n) {
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(2)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ──────────────────────────────────────
// Pyramid — wide, flat, rounded trapezoids
// ──────────────────────────────────────

class _PyramidPainter extends CustomPainter {
  final List<ProfitTier> tiers;
  final double tierH;
  _PyramidPainter({required this.tiers, required this.tierH});

  @override
  void paint(Canvas canvas, Size size) {
    if (tiers.isEmpty) return;
    final n = tiers.length;
    final cx = size.width / 2;
    final maxW = size.width;
    const gap = 3.0;
    const radius = 6.0;

    for (var i = 0; i < n; i++) {
      final y = i * tierH;
      final topW = maxW * (0.35 + (i / n) * 0.65);
      final botW = maxW * (0.35 + ((i + 1) / n) * 0.65);
      final left = cx - botW / 2;
      final right = cx + botW / 2;
      final topLeft = cx - topW / 2;
      final topRight = cx + topW / 2;

      final path = Path();
      // Top-left rounded corner
      path.moveTo(topLeft + radius, y + gap);
      path.lineTo(topRight - radius, y + gap);
      path.quadraticBezierTo(topRight, y + gap, topRight + (botW - topW) / 2 * 0.15, y + gap + radius * 0.5);
      // Right side
      path.lineTo(right - radius * 0.3, y + tierH - gap - radius * 0.3);
      path.quadraticBezierTo(right, y + tierH - gap, right - radius, y + tierH - gap);
      // Bottom
      path.lineTo(left + radius, y + tierH - gap);
      path.quadraticBezierTo(left, y + tierH - gap, left + radius * 0.3, y + tierH - gap - radius * 0.3);
      // Left side
      path.lineTo(topLeft + (topW - topW) / 2 * 0.15 + radius * 0.3, y + gap + radius * 0.5);
      path.quadraticBezierTo(topLeft, y + gap, topLeft + radius, y + gap);
      path.close();

      canvas.drawPath(path, Paint()..color = tiers[i].color);
    }
  }

  @override
  bool shouldRepaint(covariant _PyramidPainter old) => true;
}

// ──────────────────────────────────────
// Info Sheet
// ──────────────────────────────────────

class _InfoSheet extends StatelessWidget {
  final PlatformData data;
  const _InfoSheet({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFD1D1D6),
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('数据说明',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w600, color: _S.label)),
          const SizedBox(height: 20),
          _sec('字段说明', [
            '金额范围：交易者累计已实现盈利 (All Time PnL) 的分层区间',
            '地址数：该层交易者的链上地址数量',
            '占比：该层地址数 ÷ 全部地址数',
            '亏损：PnL ≤ 0 的地址统一归入亏损层',
          ]),
          const SizedBox(height: 16),
          _sec('数据口径', [
            '公开排行榜收录地址 (33.3K)，覆盖全周期交易量>\$0 的交易者',
            '其中 90% 全周期交易量超 \$1M',
            '非全部平台注册用户 (231K+)，未收录的主要是小额/试用用户',
          ]),
          const SizedBox(height: 16),
          _sec('数据来源', [
            'Hyperliquid Leaderboard API (stats-data.hyperliquid.xyz)',
          ]),
          const SizedBox(height: 16),
          _sec('刷新频率', [
            '源数据接近实时更新，CDN 缓存约 30-60 分钟',
            '下拉页面可手动刷新',
          ]),
        ],
      ),
    );
  }

  Widget _sec(String title, List<String> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: _S.label)),
          const SizedBox(height: 8),
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('·  ',
                          style: TextStyle(fontSize: 13, color: _S.sub)),
                      Expanded(
                          child: Text(t,
                              style: const TextStyle(
                                  fontSize: 13, color: _S.sub, height: 1.4))),
                    ]),
              )),
        ],
      );
}

// ──────────────────────────────────────
// Profile Card — 盈利交易者画像
// ──────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ProfileCard({required this.data});

  static const _sectionColors = [
    [Color(0xFFE85D75), Color(0xFFF5A623), Color(0xFF9B6FD0), Color(0xFF4A90D9), Color(0xFF7EC8E3)],
    [Color(0xFFF5A623), Color(0xFF9B6FD0), Color(0xFF4A90D9), Color(0xFF7EC8E3), Color(0xFFB8D4E3)],
    [Color(0xFFF5A623), Color(0xFF4A90D9), Color(0xFF7EC8E3), Color(0xFFB8D4E3)],
  ];

  @override
  Widget build(BuildContext context) {
    final totalP = data['totalProfitable'] ?? 0;
    final roi = data['roiDistribution'] ?? {};
    final acct = data['accountSizeDistribution'] ?? {};
    final vol = data['volumeDistribution'] ?? {};
    final cons = (data['consistency'] as List?) ?? [];

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          const Text('盈利交易者画像',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _S.label)),
          const SizedBox(width: 6),
          Text('排行榜 ${_fc(totalP)}/${_fc(data['totalTraders'] ?? 0)} 盈利',
              style: const TextStyle(fontSize: 12, color: _S.hint)),
          const Spacer(),
          GestureDetector(
            onTap: () => _showProfileInfo(context),
            child: Container(width: 20, height: 20,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _S.bg),
              child: const Center(child: Text('?',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _S.sub)))),
          ),
        ]),
        const SizedBox(height: 14),

        // ROI Distribution
        _bucketSection('ROI 分布', (roi['buckets'] as List?) ?? [], _sectionColors[0],
            callout: '中位数 ${roi['median'] ?? 0}%'),
        _divider(),

        // Account Size
        _bucketSection('账户规模', (acct['buckets'] as List?) ?? [], _sectionColors[1],
            callout: '中位数 \$${_fv(acct['median'] ?? 0)}'),
        _divider(),

        // Volume
        _bucketSection('交易量', (vol['buckets'] as List?) ?? [], _sectionColors[2],
            callout: '中位数 \$${_fv(vol['median'] ?? 0)}'),
        _divider(),

        // Consistency Funnel — skip the first row (allTime 100% is the filter itself)
        const Text('短期盈利持续性', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _S.label)),
        const SizedBox(height: 2),
        Text('全周期盈利者中，短期仍盈利的比例', style: TextStyle(fontSize: 11, color: _S.hint)),
        const SizedBox(height: 10),
        ...cons.asMap().entries.where((e) => e.key > 0).map((e) {
          final c = e.value;
          final pct = (c['pct'] as num?)?.toDouble() ?? 0;
          final opacity = [1.0, 0.7, 0.45][e.key.clamp(1, 3) - 1];
          return Padding(padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 44, child: Text(c['label'] ?? '',
                  style: const TextStyle(fontSize: 12, color: _S.sub))),
              const SizedBox(width: 6),
              Expanded(child: LayoutBuilder(builder: (_, box) => Stack(children: [
                Container(height: 16,
                    decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(3))),
                Container(height: 16, width: box.maxWidth * pct / 100,
                    decoration: BoxDecoration(
                        color: _S.green.withAlpha((opacity * 255).toInt()),
                        borderRadius: BorderRadius.circular(3))),
              ]))),
              const SizedBox(width: 8),
              SizedBox(width: 70, child: Text('${_fc(c['count'] ?? 0)} ${pct.toStringAsFixed(0)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: _S.sub))),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _bucketSection(String title, List buckets, List<Color> colors, {String? callout}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _S.label)),
        const Spacer(),
        if (callout != null) Text(callout,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF007AFF))),
      ]),
      const SizedBox(height: 8),
      // Stacked bar
      ClipRRect(borderRadius: BorderRadius.circular(2),
        child: SizedBox(height: 4, child: Row(children:
          buckets.asMap().entries.map((e) {
            final pct = (e.value['pct'] as num?)?.toDouble() ?? 0;
            return Expanded(flex: (pct * 10).round().clamp(1, 999),
                child: Container(color: colors[e.key % colors.length]));
          }).toList())),
      ),
      const SizedBox(height: 6),
      // Legend
      ...buckets.asMap().entries.map((e) {
        final b = e.value;
        return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(
                color: colors[e.key % colors.length], borderRadius: BorderRadius.circular(1.5))),
            const SizedBox(width: 6),
            Expanded(child: Text(b['label'] ?? '', style: const TextStyle(fontSize: 12, color: _S.label))),
            Text(_fc(b['count'] ?? 0),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _S.label)),
            const SizedBox(width: 6),
            SizedBox(width: 38, child: Text('${(b['pct'] as num?)?.toStringAsFixed(1) ?? 0}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: _S.sub))),
          ]),
        );
      }),
      const SizedBox(height: 4),
    ]);
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Container(height: 0.5, color: const Color(0xFFE5E5EA)));

  static String _fc(int n) {
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return '$n';
  }

  static String _fv(num n) {
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  static void _showProfileInfo(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('画像说明', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _S.label)),
          const SizedBox(height: 16),
          ...[
            'ROI = 累计已实现收益率 (All Time Return on Investment)',
            '账户规模 = 交易者当前账户净值',
            '交易量 = 累计全周期交易金额',
            '盈利持续性 = 全周期盈利者中，在更短时间窗口内也盈利的比例',
            '数据口径：Hyperliquid 排行榜盈利交易者，同金字塔卡片',
          ].map((t) => Padding(padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('·  ', style: TextStyle(fontSize: 13, color: _S.sub)),
                Expanded(child: Text(t, style: const TextStyle(fontSize: 13, color: _S.sub, height: 1.4))),
              ]))),
        ]),
      ),
    );
  }
}
