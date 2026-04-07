import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Cryptographic signing utilities for exchange API authentication.
class CryptoSigner {
  /// HMAC-SHA256 signature (Binance, Bybit, Gate, MEXC).
  static String hmacSha256(String secret, String payload) {
    final key = utf8.encode(secret);
    final bytes = utf8.encode(payload);
    final mac = Hmac(sha256, key).convert(bytes);
    return mac.toString();
  }

  /// HMAC-SHA256 signature Base64 encoded (OKX, Bitget).
  static String hmacSha256Base64(String secret, String payload) {
    final key = utf8.encode(secret);
    final bytes = utf8.encode(payload);
    final mac = Hmac(sha256, key).convert(bytes);
    return base64.encode(mac.bytes);
  }

  /// Build Binance query string with signature.
  static String binanceSign(String secret, Map<String, String> params) {
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final sig = hmacSha256(secret, query);
    return '$query&signature=$sig';
  }

  /// Build Bybit signature.
  /// Payload = timestamp + apiKey + recvWindow + queryString/body
  static String bybitSign(String secret, String timestamp, String apiKey,
      String recvWindow, String payload) {
    final raw = '$timestamp$apiKey$recvWindow$payload';
    return hmacSha256(secret, raw);
  }

  /// Build OKX signature.
  /// Payload = timestamp + method + requestPath + body
  static String okxSign(String secret, String timestamp, String method,
      String path, String body) {
    final raw = '$timestamp$method$path$body';
    return hmacSha256Base64(secret, raw);
  }

  /// Build Bitget signature (same pattern as OKX).
  static String bitgetSign(String secret, String timestamp, String method,
      String path, String body) {
    final raw = '$timestamp$method$path$body';
    return hmacSha256Base64(secret, raw);
  }

  /// Build Gate.io signature.
  /// Payload = method + path + query + hashedBody + timestamp
  static String gateSign(String secret, String method, String path,
      String query, String body, String timestamp) {
    final hashedBody = sha512.convert(utf8.encode(body)).toString();
    final raw = '$method\n$path\n$query\n$hashedBody\n$timestamp';
    return hmacSha256(secret, raw);
  }

  /// Current timestamp in milliseconds string.
  static String timestampMs() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  /// Current timestamp in seconds string.
  static String timestampSec() =>
      (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();

  /// ISO 8601 timestamp with milliseconds (for OKX).
  /// Format: 2020-12-08T09:08:57.715Z
  static String timestampIso() {
    final now = DateTime.now().toUtc();
    final ms = now.millisecond.toString().padLeft(3, '0');
    return '${now.toIso8601String().split('.')[0]}.$ms' 'Z';
  }
}
