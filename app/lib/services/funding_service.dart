import 'dart:convert';
import 'package:http/http.dart' as http;

// ──────────────────────────────────────
// Models
// ──────────────────────────────────────

class FundingRate {
  final String source; // 'HL', 'Binance', etc.
  final double rate8h; // normalized to 8h rate

  const FundingRate({required this.source, required this.rate8h});

  double get annualized => rate8h * 3 * 365 * 100; // percentage
}

class ArbOpportunity {
  final String coin;
  final String longPlatform; // where to go long
  final double longRate8h;
  final String shortPlatform; // where to go short
  final double shortRate8h;
  final double spread8h; // shortRate - longRate
  final double annualizedPct;
  final Map<String, double> allRates; // all platform rates for this coin

  const ArbOpportunity({
    required this.coin,
    required this.longPlatform,
    required this.longRate8h,
    required this.shortPlatform,
    required this.shortRate8h,
    required this.spread8h,
    required this.annualizedPct,
    required this.allRates,
  });
}

class FundingResult {
  final List<ArbOpportunity> opportunities;
  final int totalCoins;
  final int sourcesLoaded;
  final int sourcesFailed;
  final List<String> failedSources;
  final DateTime fetchedAt;

  const FundingResult({
    required this.opportunities,
    required this.totalCoins,
    required this.sourcesLoaded,
    required this.sourcesFailed,
    required this.failedSources,
    required this.fetchedAt,
  });
}

// ──────────────────────────────────────
// Service
// ──────────────────────────────────────

class FundingService {
  static const _sourceNames = ['HL', 'dYdX', 'Binance', 'Bybit', 'Bitget', 'Gate', 'MEXC', 'OKX'];

  static Future<FundingResult> fetchAll() async {
    final allRates = <String, Map<String, double>>{}; // coin → {source: rate8h}
    final failed = <String>[];

    // Parallel fetch all sources
    final results = await Future.wait([
      _fetchHL(),
      _fetchDydx(),
      _fetchBinance(),
      _fetchBybit(),
      _fetchBitget(),
      _fetchGate(),
      _fetchMexc(),
      _fetchOkx(),
    ]);

    for (int i = 0; i < results.length; i++) {
      final source = _sourceNames[i];
      final rates = results[i];
      if (rates == null) {
        failed.add(source);
        continue;
      }
      for (final entry in rates.entries) {
        (allRates[entry.key] ??= {})[source] = entry.value;
      }
    }

    // Calculate arbitrage opportunities
    final opps = <ArbOpportunity>[];
    for (final entry in allRates.entries) {
      final coin = entry.key;
      final rates = entry.value;
      if (rates.length < 2) continue;

      // Find min rate (go long here) and max rate (go short here)
      String minSrc = rates.keys.first, maxSrc = rates.keys.first;
      for (final src in rates.keys) {
        if (rates[src]! < rates[minSrc]!) minSrc = src;
        if (rates[src]! > rates[maxSrc]!) maxSrc = src;
      }
      if (minSrc == maxSrc) continue;

      final spread = rates[maxSrc]! - rates[minSrc]!;
      if (spread <= 0) continue;

      final annual = spread * 3 * 365 * 100;

      opps.add(ArbOpportunity(
        coin: coin,
        longPlatform: minSrc,
        longRate8h: rates[minSrc]!,
        shortPlatform: maxSrc,
        shortRate8h: rates[maxSrc]!,
        spread8h: spread,
        annualizedPct: annual,
        allRates: Map.from(rates),
      ));
    }

    opps.sort((a, b) => b.annualizedPct.compareTo(a.annualizedPct));

    return FundingResult(
      opportunities: opps,
      totalCoins: allRates.length,
      sourcesLoaded: _sourceNames.length - failed.length,
      sourcesFailed: failed.length,
      failedSources: failed,
      fetchedAt: DateTime.now(),
    );
  }

  // ── Coin name normalization ──

  static String _norm(String raw) {
    var s = raw.toUpperCase();
    // Remove suffixes first (order matters)
    for (final suffix in ['-USDT-SWAP', '-USDC-SWAP', '-USD-SWAP', '_USDT', '_USDC', '_USD',
        'USDT', 'USDC', 'SWAP']) {
      if (s.endsWith(suffix)) { s = s.substring(0, s.length - suffix.length); break; }
    }
    // Remove 1000 prefix (Binance uses 1000PEPE etc.)
    if (s.startsWith('1000') && s.length > 4) s = s.substring(4);
    s = s.replaceAll('_', '').replaceAll('-', '');
    return s.isEmpty ? raw.toUpperCase() : s; // fallback to original if empty
  }

  // ── Data Sources ──

  static Future<Map<String, double>?> _fetchHL() async {
    try {
      final res = await http.post(
        Uri.parse('https://api.hyperliquid.xyz/info'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'type': 'metaAndAssetCtxs'}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final universe = data[0]['universe'] as List;
      final ctxs = data[1] as List;
      final rates = <String, double>{};
      for (int i = 0; i < universe.length && i < ctxs.length; i++) {
        final coin = universe[i]['name'].toString().toUpperCase();
        final fr = double.tryParse(ctxs[i]['funding']?.toString() ?? '0') ?? 0;
        rates[coin] = fr * 8; // hourly → 8h
      }
      return rates;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>?> _fetchDydx() async {
    try {
      final res = await http.get(
        Uri.parse('https://indexer.dydx.trade/v4/perpetualMarkets'),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final markets = jsonDecode(res.body)['markets'] as Map<String, dynamic>? ?? {};
      final rates = <String, double>{};
      for (final entry in markets.entries) {
        final coin = _norm(entry.key);
        final fr = double.tryParse(entry.value['nextFundingRate']?.toString() ?? '0') ?? 0;
        rates[coin] = fr;
      }
      return rates;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>?> _fetchBinance() async {
    try {
      final res = await http.get(
        Uri.parse('https://fapi.binance.com/fapi/v1/premiumIndex'),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as List;
      final rates = <String, double>{};
      for (final item in data) {
        final coin = _norm(item['symbol']?.toString() ?? '');
        if (coin.isEmpty) continue;
        final fr = double.tryParse(item['lastFundingRate']?.toString() ?? '0') ?? 0;
        rates[coin] = fr;
      }
      return rates;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>?> _fetchBybit() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.bybit.com/v5/market/tickers?category=linear'),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final items = jsonDecode(res.body)['result']?['list'] as List? ?? [];
      final rates = <String, double>{};
      for (final item in items) {
        final coin = _norm(item['symbol']?.toString() ?? '');
        if (coin.isEmpty) continue;
        final fr = double.tryParse(item['fundingRate']?.toString() ?? '') ?? 0;
        rates[coin] = fr;
      }
      return rates;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>?> _fetchBitget() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.bitget.com/api/v2/mix/market/current-fund-rate?productType=USDT-FUTURES'),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final items = jsonDecode(res.body)['data'] as List? ?? [];
      final rates = <String, double>{};
      for (final item in items) {
        final coin = _norm(item['symbol']?.toString() ?? '');
        if (coin.isEmpty) continue;
        final fr = double.tryParse(item['fundingRate']?.toString() ?? '0') ?? 0;
        rates[coin] = fr;
      }
      return rates;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>?> _fetchGate() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.gateio.ws/api/v4/futures/usdt/contracts'),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final items = jsonDecode(res.body) as List;
      final rates = <String, double>{};
      for (final item in items) {
        final coin = _norm(item['name']?.toString() ?? '');
        if (coin.isEmpty) continue;
        final fr = double.tryParse(item['funding_rate']?.toString() ?? '0') ?? 0;
        rates[coin] = fr;
      }
      return rates;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>?> _fetchMexc() async {
    try {
      final res = await http.get(
        Uri.parse('https://contract.mexc.com/api/v1/contract/ticker'),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final items = jsonDecode(res.body)['data'] as List? ?? [];
      final rates = <String, double>{};
      for (final item in items) {
        final coin = _norm(item['symbol']?.toString() ?? '');
        if (coin.isEmpty) continue;
        final fr = double.tryParse(item['fundingRate']?.toString() ?? '0') ?? 0;
        rates[coin] = fr;
      }
      return rates;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>?> _fetchOkx() async {
    try {
      // OKX requires per-symbol calls. Only fetch top coins.
      const top = ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'ADA', 'AVAX', 'LINK',
          'DOT', 'MATIC', 'UNI', 'ATOM', 'FIL', 'ARB', 'OP', 'SUI', 'APT', 'SEI', 'TIA', 'INJ'];
      final rates = <String, double>{};
      final futures = top.map((coin) async {
        try {
          final res = await http.get(
            Uri.parse('https://www.okx.com/api/v5/public/funding-rate?instId=$coin-USDT-SWAP'),
          ).timeout(const Duration(seconds: 10));
          if (res.statusCode != 200) return;
          final data = jsonDecode(res.body)['data'] as List? ?? [];
          if (data.isNotEmpty) {
            final fr = double.tryParse(data[0]['fundingRate']?.toString() ?? '0') ?? 0;
            rates[coin] = fr;
          }
        } catch (_) {}
      });
      await Future.wait(futures);
      return rates.isEmpty ? null : rates;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════
  // Historical Funding Rates
  // ══════════════════════════════════════

  /// Fetch historical funding rates for a coin from multiple sources.
  /// Returns map of source → list of (time, rate8h) pairs.
  static Future<Map<String, List<({DateTime time, double rate8h})>>> fetchHistory(
      String coin, Duration period) async {
    final result = <String, List<({DateTime time, double rate8h})>>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - period.inMilliseconds;

    final futures = <Future<void>>[
      // Hyperliquid
      () async {
        try {
          final res = await http.post(
            Uri.parse('https://api.hyperliquid.xyz/info'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'type': 'fundingHistory', 'coin': coin, 'startTime': start}),
          ).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) return;
          final data = jsonDecode(res.body) as List? ?? [];
          result['HL'] = data.map<({DateTime time, double rate8h})>((d) {
            final t = DateTime.fromMillisecondsSinceEpoch(d['time'] as int);
            final r = double.tryParse(d['fundingRate']?.toString() ?? '0') ?? 0;
            return (time: t, rate8h: r * 8); // hourly → 8h
          }).toList();
        } catch (_) {}
      }(),
      // Binance
      () async {
        try {
          final sym = '${coin}USDT';
          final res = await http.get(Uri.parse(
              'https://fapi.binance.com/fapi/v1/fundingRate?symbol=$sym&startTime=$start&limit=1000'),
          ).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) return;
          final data = jsonDecode(res.body) as List? ?? [];
          result['Binance'] = data.map<({DateTime time, double rate8h})>((d) {
            final t = DateTime.fromMillisecondsSinceEpoch(d['fundingTime'] as int);
            final r = double.tryParse(d['fundingRate']?.toString() ?? '0') ?? 0;
            return (time: t, rate8h: r);
          }).toList();
        } catch (_) {}
      }(),
      // Bybit
      () async {
        try {
          final sym = '${coin}USDT';
          final res = await http.get(Uri.parse(
              'https://api.bybit.com/v5/market/funding/history?category=linear&symbol=$sym&limit=200'),
          ).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) return;
          final list = jsonDecode(res.body)['result']?['list'] as List? ?? [];
          result['Bybit'] = list.map<({DateTime time, double rate8h})>((d) {
            final t = DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(d['fundingRateTimestamp']?.toString() ?? '0') ?? 0);
            final r = double.tryParse(d['fundingRate']?.toString() ?? '0') ?? 0;
            return (time: t, rate8h: r);
          }).where((p) => p.time.isAfter(DateTime.fromMillisecondsSinceEpoch(start))).toList();
        } catch (_) {}
      }(),
      // OKX
      () async {
        try {
          final res = await http.get(Uri.parse(
              'https://www.okx.com/api/v5/public/funding-rate-history?instId=$coin-USDT-SWAP&limit=100'),
          ).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) return;
          final data = jsonDecode(res.body)['data'] as List? ?? [];
          result['OKX'] = data.map<({DateTime time, double rate8h})>((d) {
            final t = DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(d['fundingTime']?.toString() ?? '0') ?? 0);
            final r = double.tryParse(d['fundingRate']?.toString() ?? '0') ?? 0;
            return (time: t, rate8h: r);
          }).where((p) => p.time.isAfter(DateTime.fromMillisecondsSinceEpoch(start))).toList();
        } catch (_) {}
      }(),
      // Gate.io
      () async {
        try {
          final contract = '${coin}_USDT';
          final res = await http.get(Uri.parse(
              'https://api.gateio.ws/api/v4/futures/usdt/funding_rate?contract=$contract&limit=100'),
          ).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) return;
          final data = jsonDecode(res.body) as List? ?? [];
          result['Gate'] = data.map<({DateTime time, double rate8h})>((d) {
            final t = DateTime.fromMillisecondsSinceEpoch(
                ((d['t'] as num?)?.toInt() ?? 0) * 1000); // seconds → ms
            final r = double.tryParse(d['r']?.toString() ?? '0') ?? 0;
            return (time: t, rate8h: r);
          }).where((p) => p.time.isAfter(DateTime.fromMillisecondsSinceEpoch(start))).toList();
        } catch (_) {}
      }(),
    ];

    await Future.wait(futures);
    // Remove empty series
    result.removeWhere((_, v) => v.isEmpty);
    return result;
  }
}
