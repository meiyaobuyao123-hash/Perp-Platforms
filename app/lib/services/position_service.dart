import 'dart:convert';
import 'package:http/http.dart' as http;

// ──────────────────────────────────────
// Unified position model
// ──────────────────────────────────────

class Position {
  final String platform; // 'Hyperliquid', 'GMX', 'dYdX'
  final String coin;
  final bool isLong;
  final double size; // USD notional
  final double entryPrice;
  final double unrealizedPnl;
  final double marginUsed;
  final double? liquidationPrice;
  final String leverageType; // 'cross' or 'isolated'
  final int leverageValue;

  Position({
    required this.platform,
    required this.coin,
    required this.isLong,
    required this.size,
    required this.entryPrice,
    required this.unrealizedPnl,
    required this.marginUsed,
    this.liquidationPrice,
    required this.leverageType,
    required this.leverageValue,
  });
}

class PlatformSummary {
  final String name;
  final double accountValue;
  final double totalMarginUsed;
  final List<Position> positions;
  final String? error;

  PlatformSummary({
    required this.name,
    required this.accountValue,
    required this.totalMarginUsed,
    required this.positions,
    this.error,
  });

  static PlatformSummary failed(String name, String error) => PlatformSummary(
      name: name, accountValue: 0, totalMarginUsed: 0, positions: [], error: error);

  static PlatformSummary empty(String name) => PlatformSummary(
      name: name, accountValue: 0, totalMarginUsed: 0, positions: []);
}

class PortfolioResult {
  final List<PlatformSummary> platforms;
  final double totalAccountValue;
  final double totalMarginUsed;
  final double totalUnrealizedPnl;
  final int totalPositions;
  final double marginUsagePercent;

  PortfolioResult({required this.platforms})
      : totalAccountValue =
            platforms.fold(0.0, (s, p) => s + p.accountValue),
        totalMarginUsed =
            platforms.fold(0.0, (s, p) => s + p.totalMarginUsed),
        totalUnrealizedPnl = platforms.fold(
            0.0,
            (s, p) =>
                s + p.positions.fold(0.0, (s2, pos) => s2 + pos.unrealizedPnl)),
        totalPositions =
            platforms.fold(0, (s, p) => s + p.positions.length),
        marginUsagePercent = _calcMarginPct(platforms);

  static double _calcMarginPct(List<PlatformSummary> platforms) {
    final val = platforms.fold(0.0, (s, p) => s + p.accountValue);
    final used = platforms.fold(0.0, (s, p) => s + p.totalMarginUsed);
    return val > 0 ? (used / val * 100) : 0;
  }

  /// Estimate PnL change if a coin moves by `pctChange` (e.g. -0.10 = -10%)
  double stressTest(String coin, double pctChange) {
    double impact = 0;
    for (final p in platforms) {
      for (final pos in p.positions) {
        if (pos.coin.toUpperCase() != coin.toUpperCase()) continue;
        final delta = pos.size * pctChange;
        impact += pos.isLong ? delta : -delta;
      }
    }
    return impact;
  }

  /// Find hedge conflicts (same coin, opposite direction across platforms)
  List<String> findHedges() {
    final longs = <String, List<String>>{};
    final shorts = <String, List<String>>{};
    for (final p in platforms) {
      for (final pos in p.positions) {
        final c = pos.coin.toUpperCase();
        if (pos.isLong) {
          (longs[c] ??= []).add(p.name);
        } else {
          (shorts[c] ??= []).add(p.name);
        }
      }
    }
    final hedges = <String>[];
    for (final c in longs.keys) {
      if (shorts.containsKey(c)) {
        hedges.add('$c: 做多@${longs[c]!.join("+")} / 做空@${shorts[c]!.join("+")}');
      }
    }
    return hedges;
  }
}

// ──────────────────────────────────────
// API Service
// ──────────────────────────────────────

class PositionService {
  /// Fetch all platforms in parallel. Never throws — failures are per-platform.
  static Future<PortfolioResult> fetchAll({
    required String evmAddress,
    String? dydxAddress,
  }) async {
    final futures = <Future<PlatformSummary>>[
      _fetchHyperliquid(evmAddress),
      _fetchGmx(evmAddress),
      _fetchAster(evmAddress),
      _fetchLighter(evmAddress),
    ];
    if (dydxAddress != null && dydxAddress.startsWith('dydx1')) {
      futures.add(_fetchDydx(dydxAddress));
    }

    final results = await Future.wait(futures);
    return PortfolioResult(platforms: results);
  }

  // ── Hyperliquid ──

  static Future<PlatformSummary> _fetchHyperliquid(String address) async {
    try {
      final res = await http.post(
        Uri.parse('https://api.hyperliquid.xyz/info'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'type': 'clearinghouseState', 'user': address}),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return PlatformSummary.failed('Hyperliquid', 'HTTP ${res.statusCode}');

      final data = jsonDecode(res.body);
      final margin = data['marginSummary'] ?? {};
      final accountValue = double.tryParse(margin['accountValue']?.toString() ?? '0') ?? 0;
      final marginUsed = double.tryParse(margin['totalMarginUsed']?.toString() ?? '0') ?? 0;

      final rawPositions = data['assetPositions'] as List? ?? [];
      final positions = rawPositions.map<Position>((ap) {
        final p = ap['position'] ?? {};
        final lev = p['leverage'] ?? {};
        final szi = double.tryParse(p['szi']?.toString() ?? '0') ?? 0;

        return Position(
          platform: 'Hyperliquid',
          coin: p['coin'] ?? '?',
          isLong: szi > 0,
          size: (double.tryParse(p['positionValue']?.toString() ?? '0') ?? 0).abs(),
          entryPrice: double.tryParse(p['entryPx']?.toString() ?? '0') ?? 0,
          unrealizedPnl: double.tryParse(p['unrealizedPnl']?.toString() ?? '0') ?? 0,
          marginUsed: double.tryParse(p['marginUsed']?.toString() ?? '0') ?? 0,
          liquidationPrice: double.tryParse(p['liquidationPx']?.toString() ?? ''),
          leverageType: lev['type']?.toString() ?? 'cross',
          leverageValue: lev['value'] ?? 0,
        );
      }).where((p) => p.size > 0).toList();

      return PlatformSummary(
        name: 'Hyperliquid',
        accountValue: accountValue,
        totalMarginUsed: marginUsed,
        positions: positions,
      );
    } catch (e) {
      return PlatformSummary.failed('Hyperliquid', e.toString());
    }
  }

  // ── GMX v2 ──

  static List<Map<String, String>>? _gmxMarketsCache;

  static Future<PlatformSummary> _fetchGmx(String address) async {
    try {
      final res = await http.get(
        Uri.parse('https://arbitrum-api.gmxinfra.io/positions'),
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) return PlatformSummary.failed('GMX', 'HTTP ${res.statusCode}');

      final data = jsonDecode(res.body);
      final allPositions = data['positions'] as List? ?? [];

      // Filter by account
      final mine = allPositions.where(
        (p) => (p['account'] as String?)?.toLowerCase() == address.toLowerCase(),
      ).toList();

      if (mine.isEmpty) return PlatformSummary.empty('GMX');

      final positions = mine.map<Position>((p) {
        final sizeUsd = BigInt.tryParse(p['sizeInUsd']?.toString() ?? '0') ?? BigInt.zero;
        final pnl = BigInt.tryParse(p['pnl']?.toString() ?? '0') ?? BigInt.zero;
        final size = sizeUsd.toDouble() / 1e30;
        final pnlVal = pnl.toDouble() / 1e30;

        return Position(
          platform: 'GMX',
          coin: _gmxMarketToCoin(p['marketAddress']?.toString() ?? ''),
          isLong: p['isLong'] == true,
          size: size.abs(),
          entryPrice: 0, // GMX API doesn't return entry price directly
          unrealizedPnl: pnlVal,
          marginUsed: size / 10, // Approximate: assume 10x avg leverage
          liquidationPrice: null,
          leverageType: 'isolated',
          leverageValue: 0,
        );
      }).where((p) => p.size > 0).toList();

      final totalSize = positions.fold(0.0, (s, p) => s + p.size);

      return PlatformSummary(
        name: 'GMX',
        accountValue: totalSize * 0.15, // Approximate collateral
        totalMarginUsed: positions.fold(0.0, (s, p) => s + p.marginUsed),
        positions: positions,
      );
    } catch (e) {
      return PlatformSummary.failed('GMX', e.toString());
    }
  }

  static String _gmxMarketToCoin(String addr) {
    // Common GMX v2 market addresses on Arbitrum
    const map = {
      '0x47c031236e19d024b42f8ae6da7084a1a41b82c4': 'BTC',
      '0x70d95587d40a2cdd56194bbd4ad26d7c89643607': 'ETH',
      '0x09400d9db990d5ed3f35d7be61dfaeb900af03c9': 'SOL',
      '0xd9535bb5f58a1a75032416f2dfe7880c30575a41': 'DOGE',
      '0xb7e69749e3d2ed4c56e32c4458526c21638e53c5': 'LINK',
      '0xc7abb2c5f3bf3ceb389df0000896a53b9cf0f709': 'ARB',
      '0x0ccb4faa6f1f1b30911619f1184082ab4e25813c': 'XRP',
      '0x2b3a7c8e50afe0c5e4a981adab7e0b7a7d45b55f': 'AVAX',
    };
    return map[addr.toLowerCase()] ?? addr.substring(0, 8);
  }

  // ── dYdX v4 ──

  static Future<PlatformSummary> _fetchDydx(String address) async {
    try {
      final res = await http.get(
        Uri.parse(
            'https://dydx-rest.publicnode.com/dydxprotocol/subaccounts/subaccount/$address/0'),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return PlatformSummary.failed('dYdX', 'HTTP ${res.statusCode}');

      final data = jsonDecode(res.body);
      final sub = data['subaccount'] ?? {};
      final perps = sub['perpetual_positions'] as List? ?? [];
      final assets = sub['asset_positions'] as List? ?? [];

      if (perps.isEmpty) return PlatformSummary.empty('dYdX');

      // Asset balance (USDC, asset_id 0)
      double usdcBalance = 0;
      for (final a in assets) {
        if (a['asset_id'] == 0) {
          final q = BigInt.tryParse(a['quantums']?.toString() ?? '0') ?? BigInt.zero;
          usdcBalance = q.toDouble() / 1e6; // USDC has 6 decimals
        }
      }

      final positions = perps.map<Position>((p) {
        final perpId = p['perpetual_id'] ?? 0;
        final quantums = BigInt.tryParse(p['quantums']?.toString() ?? '0') ?? BigInt.zero;

        // Decode position size based on perpetual_id
        final coin = _dydxPerpIdToCoin(perpId);
        final decimals = _dydxPerpDecimals(perpId);
        final sizeInCoin = quantums.toDouble() / decimals;

        return Position(
          platform: 'dYdX',
          coin: coin,
          isLong: sizeInCoin > 0,
          size: sizeInCoin.abs(), // In coin terms, not USD (would need price)
          entryPrice: 0,
          unrealizedPnl: 0, // Cosmos RPC doesn't return this directly
          marginUsed: 0,
          liquidationPrice: null,
          leverageType: 'cross',
          leverageValue: 0,
        );
      }).toList();

      return PlatformSummary(
        name: 'dYdX',
        accountValue: usdcBalance,
        totalMarginUsed: 0,
        positions: positions,
      );
    } catch (e) {
      return PlatformSummary.failed('dYdX', e.toString());
    }
  }

  static String _dydxPerpIdToCoin(int id) {
    const map = {
      0: 'BTC', 1: 'ETH', 2: 'LINK', 3: 'MATIC', 4: 'CRV',
      5: 'SOL', 6: 'ADA', 7: 'AVAX', 8: 'FIL', 9: 'LTC',
      10: 'DOGE', 11: 'ATOM', 12: 'DOT', 13: 'UNI', 14: 'BCH',
      22: 'APE', 33: 'SUI', 65: 'PEPE',
    };
    return map[id] ?? 'PERP#$id';
  }

  static double _dydxPerpDecimals(int id) {
    if (id == 0) return 1e10;
    if (id == 1) return 1e9;
    return 1e7;
  }

  // ── Aster ──

  static Future<PlatformSummary> _fetchAster(String address) async {
    try {
      final res = await http.post(
        Uri.parse('https://tapi.asterdex.com/info'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'aster_getBalance',
          'params': [address, 'latest'],
          'id': 1,
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return PlatformSummary.failed('Aster', 'HTTP ${res.statusCode}');

      final data = jsonDecode(res.body);
      if (data['error'] != null) {
        final msg = data['error']['message']?.toString() ?? '';
        if (msg.contains('does not exist')) return PlatformSummary.empty('Aster');
        return PlatformSummary.failed('Aster', msg);
      }

      final result = data['result'] ?? {};
      final balances = result['balances'] as List? ?? [];
      final openPositions = result['positions'] as List? ?? [];

      if (openPositions.isEmpty) return PlatformSummary.empty('Aster');

      double totalBalance = 0;
      for (final b in balances) {
        totalBalance += double.tryParse(b['balance']?.toString() ?? '0') ?? 0;
      }

      final positions = openPositions.map<Position>((p) {
        final symbol = p['symbol']?.toString() ?? '?';
        final coin = symbol.replaceAll('USDT', '').replaceAll('USD', '');
        final posAmt = double.tryParse(p['positionAmt']?.toString() ?? '0') ?? 0;
        final entryPrice = double.tryParse(p['entryPrice']?.toString() ?? '0') ?? 0;
        final markPrice = double.tryParse(p['markPrice']?.toString() ?? '0') ?? 0;
        final uPnl = double.tryParse(p['unrealizedProfit']?.toString() ?? '0') ?? 0;
        final leverage = int.tryParse(p['leverage']?.toString() ?? '0') ?? 0;
        final marginType = p['marginType']?.toString() ?? 'cross';

        return Position(
          platform: 'Aster',
          coin: coin,
          isLong: posAmt > 0,
          size: (posAmt * markPrice).abs(),
          entryPrice: entryPrice,
          unrealizedPnl: uPnl,
          marginUsed: leverage > 0 ? (posAmt * markPrice).abs() / leverage : 0,
          liquidationPrice: double.tryParse(p['liquidationPrice']?.toString() ?? ''),
          leverageType: marginType,
          leverageValue: leverage,
        );
      }).where((p) => p.size > 0).toList();

      return PlatformSummary(
        name: 'Aster',
        accountValue: totalBalance,
        totalMarginUsed: positions.fold(0.0, (s, p) => s + p.marginUsed),
        positions: positions,
      );
    } catch (e) {
      return PlatformSummary.failed('Aster', e.toString());
    }
  }

  // ── Lighter ──

  static Future<PlatformSummary> _fetchLighter(String address) async {
    try {
      final res = await http.get(
        Uri.parse(
            'https://mainnet.zklighter.elliot.ai/api/v1/account?by=l1_address&value=$address'),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 400) {
        // "account not found" = user has no Lighter account, not an error
        return PlatformSummary.empty('Lighter');
      }
      if (res.statusCode != 200) return PlatformSummary.failed('Lighter', 'HTTP ${res.statusCode}');

      final data = jsonDecode(res.body);
      final accounts = data['accounts'] as List? ?? [];

      if (accounts.isEmpty) return PlatformSummary.empty('Lighter');

      final acct = accounts[0];
      final collateral = double.tryParse(acct['collateral']?.toString() ?? '0') ?? 0;
      final rawPositions = acct['positions'] as List? ?? [];

      final positions = rawPositions.map<Position?>((p) {
        final posSize = double.tryParse(p['position']?.toString() ?? '0') ?? 0;
        if (posSize == 0) return null;

        final symbol = p['symbol']?.toString() ?? 'MKT#${p['market_id']}';
        final coin = symbol
            .replaceAll('_USDC', '')
            .replaceAll('_USD', '')
            .replaceAll('/USDC', '');
        final uPnl = double.tryParse(p['unrealized_pnl']?.toString() ?? '0') ?? 0;
        final entryPrice = double.tryParse(p['avg_entry_price']?.toString() ?? '0') ?? 0;
        final posValue = double.tryParse(p['position_value']?.toString() ?? '0') ?? 0;
        final liqPrice = double.tryParse(p['liquidation_price']?.toString() ?? '');
        final margin = double.tryParse(p['allocated_margin']?.toString() ?? '0') ?? 0;
        final marginMode = p['margin_mode']?.toString() ?? 'cross';

        return Position(
          platform: 'Lighter',
          coin: coin,
          isLong: posSize > 0,
          size: posValue.abs(),
          entryPrice: entryPrice,
          unrealizedPnl: uPnl,
          marginUsed: margin,
          liquidationPrice: liqPrice,
          leverageType: marginMode == '1' ? 'isolated' : 'cross',
          leverageValue: margin > 0 ? (posValue / margin).round() : 0,
        );
      }).whereType<Position>().toList();

      return PlatformSummary(
        name: 'Lighter',
        accountValue: collateral,
        totalMarginUsed: positions.fold(0.0, (s, p) => s + p.marginUsed),
        positions: positions,
      );
    } catch (e) {
      return PlatformSummary.failed('Lighter', e.toString());
    }
  }
}
