import 'dart:convert';
import 'package:http/http.dart' as http;
import 'crypto_signer.dart';
import 'key_storage.dart';

// ──────────────────────────────────────
// Unified Order Result
// ──────────────────────────────────────

class OrderResult {
  final bool success;
  final String platform;
  final String? orderId;
  final double? filledPrice;
  final double? filledQty;
  final String? error;

  const OrderResult({
    required this.success,
    required this.platform,
    this.orderId,
    this.filledPrice,
    this.filledQty,
    this.error,
  });
}

// ──────────────────────────────────────
// Trading Service — unified interface for all exchanges
// ──────────────────────────────────────

class TradingService {
  /// Place a market order on the specified platform.
  /// [side] = 'BUY' or 'SELL'
  /// [coin] = 'BTC', 'ETH', 'SOL', etc.
  /// [quantity] = amount in coin units
  static Future<OrderResult> placeMarketOrder({
    required String platform,
    required String coin,
    required String side, // 'BUY' or 'SELL'
    required double quantity,
  }) async {
    final creds = await KeyStorage.getCredentials(platform);
    if (creds.isEmpty) {
      return OrderResult(success: false, platform: platform, error: '未配置 API Key');
    }

    switch (platform) {
      case 'binance':
        return _binanceOrder(creds, coin, side, quantity);
      case 'bybit':
        return _bybitOrder(creds, coin, side, quantity);
      case 'okx':
        return _okxOrder(creds, coin, side, quantity);
      case 'bitget':
        return _bitgetOrder(creds, coin, side, quantity);
      case 'gate':
        return _gateOrder(creds, coin, side, quantity);
      case 'mexc':
        return _mexcOrder(creds, coin, side, quantity);
      case 'hyperliquid':
        return OrderResult(success: false, platform: 'hyperliquid',
            error: 'Hyperliquid 需要链上签名，暂不支持客户端直接下单');
      default:
        return OrderResult(success: false, platform: platform, error: '不支持的平台');
    }
  }

  /// Cancel an order.
  static Future<OrderResult> cancelOrder({
    required String platform,
    required String coin,
    required String orderId,
  }) async {
    final creds = await KeyStorage.getCredentials(platform);
    if (creds.isEmpty) {
      return OrderResult(success: false, platform: platform, error: '未配置 API Key');
    }

    switch (platform) {
      case 'binance':
        return _binanceCancel(creds, coin, orderId);
      case 'bybit':
        return _bybitCancel(creds, coin, orderId);
      default:
        return OrderResult(success: false, platform: platform, error: '撤单暂不支持');
    }
  }

  /// Check account balance for a platform.
  static Future<double?> getBalance(String platform) async {
    final creds = await KeyStorage.getCredentials(platform);
    if (creds.isEmpty) return null;

    switch (platform) {
      case 'binance':
        return _binanceBalance(creds);
      case 'bybit':
        return _bybitBalance(creds);
      default:
        return null;
    }
  }

  // ══════════════════════════════════════
  // Binance Futures
  // ══════════════════════════════════════

  static Future<OrderResult> _binanceOrder(
      Map<String, String> creds, String coin, String side, double qty) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final symbol = '${coin}USDT';
      final ts = CryptoSigner.timestampMs();

      final params = {
        'symbol': symbol,
        'side': side,
        'type': 'MARKET',
        'quantity': qty.toString(),
        'timestamp': ts,
        'recvWindow': '5000',
      };
      final signed = CryptoSigner.binanceSign(secret, params);

      final res = await http.post(
        Uri.parse('https://fapi.binance.com/fapi/v1/order?$signed'),
        headers: {'X-MBX-APIKEY': apiKey},
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return OrderResult(
          success: true,
          platform: 'binance',
          orderId: data['orderId']?.toString(),
          filledPrice: double.tryParse(data['avgPrice']?.toString() ?? ''),
          filledQty: double.tryParse(data['executedQty']?.toString() ?? ''),
        );
      }
      return OrderResult(success: false, platform: 'binance',
          error: data['msg']?.toString() ?? 'Unknown error');
    } catch (e) {
      return OrderResult(success: false, platform: 'binance', error: e.toString());
    }
  }

  static Future<OrderResult> _binanceCancel(
      Map<String, String> creds, String coin, String orderId) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final ts = CryptoSigner.timestampMs();
      final params = {
        'symbol': '${coin}USDT',
        'orderId': orderId,
        'timestamp': ts,
      };
      final signed = CryptoSigner.binanceSign(secret, params);
      final res = await http.delete(
        Uri.parse('https://fapi.binance.com/fapi/v1/order?$signed'),
        headers: {'X-MBX-APIKEY': apiKey},
      ).timeout(const Duration(seconds: 10));
      return OrderResult(success: res.statusCode == 200, platform: 'binance',
          orderId: orderId);
    } catch (e) {
      return OrderResult(success: false, platform: 'binance', error: e.toString());
    }
  }

  static Future<double?> _binanceBalance(Map<String, String> creds) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final ts = CryptoSigner.timestampMs();
      final params = {'timestamp': ts, 'recvWindow': '5000'};
      final signed = CryptoSigner.binanceSign(secret, params);
      final res = await http.get(
        Uri.parse('https://fapi.binance.com/fapi/v2/balance?$signed'),
        headers: {'X-MBX-APIKEY': apiKey},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      for (final item in data) {
        if (item['asset'] == 'USDT') {
          return double.tryParse(item['availableBalance']?.toString() ?? '0');
        }
      }
      return 0;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════
  // Bybit V5
  // ══════════════════════════════════════

  static Future<OrderResult> _bybitOrder(
      Map<String, String> creds, String coin, String side, double qty) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final ts = CryptoSigner.timestampMs();
      const recv = '5000';

      final body = jsonEncode({
        'category': 'linear',
        'symbol': '${coin}USDT',
        'side': side == 'BUY' ? 'Buy' : 'Sell',
        'orderType': 'Market',
        'qty': qty.toString(),
      });

      final sign = CryptoSigner.bybitSign(secret, ts, apiKey, recv, body);

      final res = await http.post(
        Uri.parse('https://api.bybit.com/v5/order/create'),
        headers: {
          'X-BAPI-API-KEY': apiKey,
          'X-BAPI-TIMESTAMP': ts,
          'X-BAPI-RECV-WINDOW': recv,
          'X-BAPI-SIGN': sign,
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data['retCode'] == 0) {
        return OrderResult(
          success: true,
          platform: 'bybit',
          orderId: data['result']?['orderId']?.toString(),
        );
      }
      return OrderResult(success: false, platform: 'bybit',
          error: data['retMsg']?.toString() ?? 'Unknown error');
    } catch (e) {
      return OrderResult(success: false, platform: 'bybit', error: e.toString());
    }
  }

  static Future<OrderResult> _bybitCancel(
      Map<String, String> creds, String coin, String orderId) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final ts = CryptoSigner.timestampMs();
      const recv = '5000';
      final body = jsonEncode({
        'category': 'linear',
        'symbol': '${coin}USDT',
        'orderId': orderId,
      });
      final sign = CryptoSigner.bybitSign(secret, ts, apiKey, recv, body);
      final res = await http.post(
        Uri.parse('https://api.bybit.com/v5/order/cancel'),
        headers: {
          'X-BAPI-API-KEY': apiKey,
          'X-BAPI-TIMESTAMP': ts,
          'X-BAPI-RECV-WINDOW': recv,
          'X-BAPI-SIGN': sign,
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      return OrderResult(success: data['retCode'] == 0, platform: 'bybit', orderId: orderId);
    } catch (e) {
      return OrderResult(success: false, platform: 'bybit', error: e.toString());
    }
  }

  static Future<double?> _bybitBalance(Map<String, String> creds) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final ts = CryptoSigner.timestampMs();
      const recv = '5000';
      const query = 'accountType=UNIFIED';
      final sign = CryptoSigner.bybitSign(secret, ts, apiKey, recv, query);
      final res = await http.get(
        Uri.parse('https://api.bybit.com/v5/account/wallet-balance?$query'),
        headers: {
          'X-BAPI-API-KEY': apiKey,
          'X-BAPI-TIMESTAMP': ts,
          'X-BAPI-RECV-WINDOW': recv,
          'X-BAPI-SIGN': sign,
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final coins = data['result']?['list']?[0]?['coin'] as List? ?? [];
      for (final c in coins) {
        if (c['coin'] == 'USDT') return double.tryParse(c['availableToWithdraw']?.toString() ?? '0');
      }
      return 0;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════
  // OKX V5
  // ══════════════════════════════════════

  static Future<OrderResult> _okxOrder(
      Map<String, String> creds, String coin, String side, double qty) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final passphrase = creds['passphrase']!;
      final ts = CryptoSigner.timestampIso();
      const path = '/api/v5/trade/order';

      final bodyMap = {
        'instId': '$coin-USDT-SWAP',
        'tdMode': 'cross',
        'side': side.toLowerCase(),
        'ordType': 'market',
        'sz': qty.toString(),
      };
      final body = jsonEncode(bodyMap);
      final sign = CryptoSigner.okxSign(secret, ts, 'POST', path, body);

      final res = await http.post(
        Uri.parse('https://www.okx.com$path'),
        headers: {
          'OK-ACCESS-KEY': apiKey,
          'OK-ACCESS-SIGN': sign,
          'OK-ACCESS-TIMESTAMP': ts,
          'OK-ACCESS-PASSPHRASE': passphrase,
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data['code'] == '0') {
        final d = (data['data'] as List?)?.firstOrNull;
        return OrderResult(success: true, platform: 'okx',
            orderId: d?['ordId']?.toString());
      }
      return OrderResult(success: false, platform: 'okx',
          error: data['msg']?.toString() ?? 'Unknown error');
    } catch (e) {
      return OrderResult(success: false, platform: 'okx', error: e.toString());
    }
  }

  // ══════════════════════════════════════
  // Bitget V2
  // ══════════════════════════════════════

  static Future<OrderResult> _bitgetOrder(
      Map<String, String> creds, String coin, String side, double qty) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final passphrase = creds['passphrase']!;
      final ts = CryptoSigner.timestampMs();
      const path = '/api/v2/mix/order/place-order';

      final bodyMap = {
        'symbol': '${coin}USDT',
        'productType': 'USDT-FUTURES',
        'marginMode': 'crossed',
        'marginCoin': 'USDT',
        'side': side.toLowerCase(),
        'orderType': 'market',
        'size': qty.toString(),
      };
      final body = jsonEncode(bodyMap);
      final sign = CryptoSigner.bitgetSign(secret, ts, 'POST', path, body);

      final res = await http.post(
        Uri.parse('https://api.bitget.com$path'),
        headers: {
          'ACCESS-KEY': apiKey,
          'ACCESS-SIGN': sign,
          'ACCESS-TIMESTAMP': ts,
          'ACCESS-PASSPHRASE': passphrase,
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data['code'] == '00000') {
        return OrderResult(success: true, platform: 'bitget',
            orderId: data['data']?['orderId']?.toString());
      }
      return OrderResult(success: false, platform: 'bitget',
          error: data['msg']?.toString() ?? 'Unknown error');
    } catch (e) {
      return OrderResult(success: false, platform: 'bitget', error: e.toString());
    }
  }

  // ══════════════════════════════════════
  // Gate.io V4
  // ══════════════════════════════════════

  static Future<OrderResult> _gateOrder(
      Map<String, String> creds, String coin, String side, double qty) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final ts = CryptoSigner.timestampSec();
      const path = '/api/v4/futures/usdt/orders';

      // Gate uses positive size for long, negative for short
      final size = side == 'BUY' ? qty.toInt() : -qty.toInt();
      final bodyMap = {
        'contract': '${coin}_USDT',
        'size': size,
        'price': '0', // market order
        'tif': 'ioc',
      };
      final body = jsonEncode(bodyMap);
      final sign = CryptoSigner.gateSign(secret, 'POST', path, '', body, ts);

      final res = await http.post(
        Uri.parse('https://api.gateio.ws$path'),
        headers: {
          'KEY': apiKey,
          'SIGN': sign,
          'Timestamp': ts,
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 201 || res.statusCode == 200) {
        return OrderResult(success: true, platform: 'gate',
            orderId: data['id']?.toString(),
            filledPrice: double.tryParse(data['fill_price']?.toString() ?? ''),
            filledQty: double.tryParse(data['size']?.toString() ?? ''));
      }
      return OrderResult(success: false, platform: 'gate',
          error: data['message']?.toString() ?? 'HTTP ${res.statusCode}');
    } catch (e) {
      return OrderResult(success: false, platform: 'gate', error: e.toString());
    }
  }

  // ══════════════════════════════════════
  // MEXC
  // ══════════════════════════════════════

  static Future<OrderResult> _mexcOrder(
      Map<String, String> creds, String coin, String side, double qty) async {
    try {
      final apiKey = creds['apiKey']!;
      final secret = creds['secret']!;
      final ts = CryptoSigner.timestampMs();

      // MEXC futures uses similar signature to Binance
      final params = {
        'symbol': '${coin}_USDT',
        'side': side == 'BUY' ? '1' : '2', // 1=open long, 2=open short
        'type': '5', // market order
        'vol': qty.toString(),
        'timestamp': ts,
      };
      final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      final sign = CryptoSigner.hmacSha256(secret, query);

      final res = await http.post(
        Uri.parse('https://contract.mexc.com/api/v1/private/order/submit'),
        headers: {
          'ApiKey': apiKey,
          'Request-Time': ts,
          'Signature': sign,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(params),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data['code'] == 0) {
        return OrderResult(success: true, platform: 'mexc',
            orderId: data['data']?.toString());
      }
      return OrderResult(success: false, platform: 'mexc',
          error: data['msg']?.toString() ?? 'Unknown error');
    } catch (e) {
      return OrderResult(success: false, platform: 'mexc', error: e.toString());
    }
  }

  // ══════════════════════════════════════
  // Verify API Key (test connection)
  // ══════════════════════════════════════

  /// Verify that stored API credentials are valid by making a lightweight authenticated request.
  static Future<bool> verifyCredentials(String platform) async {
    final balance = await getBalance(platform);
    return balance != null;
  }
}
