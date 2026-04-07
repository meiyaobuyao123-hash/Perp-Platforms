import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted local storage for exchange API keys.
/// Uses iOS Keychain / Android EncryptedSharedPreferences.
class KeyStorage {
  static const _storage = FlutterSecureStorage();

  // Exchange identifiers
  static const exchanges = [
    'hyperliquid', 'binance', 'bybit', 'okx', 'bitget', 'gate', 'mexc',
  ];

  static const exchangeLabels = {
    'hyperliquid': 'Hyperliquid',
    'binance': 'Binance',
    'bybit': 'Bybit',
    'okx': 'OKX',
    'bitget': 'Bitget',
    'gate': 'Gate.io',
    'mexc': 'MEXC',
  };

  // What credentials each exchange needs
  static const exchangeFields = {
    'hyperliquid': ['privateKey'],
    'binance': ['apiKey', 'secret'],
    'bybit': ['apiKey', 'secret'],
    'okx': ['apiKey', 'secret', 'passphrase'],
    'bitget': ['apiKey', 'secret', 'passphrase'],
    'gate': ['apiKey', 'secret'],
    'mexc': ['apiKey', 'secret'],
  };

  static String _key(String exchange, String field) => '${exchange}_$field';

  /// Save a credential field for an exchange.
  static Future<void> save(String exchange, String field, String value) async {
    await _storage.write(key: _key(exchange, field), value: value);
  }

  /// Read a credential field. Returns null if not set.
  static Future<String?> read(String exchange, String field) async {
    return _storage.read(key: _key(exchange, field));
  }

  /// Delete all credentials for an exchange.
  static Future<void> delete(String exchange) async {
    final fields = exchangeFields[exchange] ?? [];
    for (final f in fields) {
      await _storage.delete(key: _key(exchange, f));
    }
  }

  /// Check if an exchange has all required credentials configured.
  static Future<bool> isConfigured(String exchange) async {
    final fields = exchangeFields[exchange] ?? [];
    for (final f in fields) {
      final val = await _storage.read(key: _key(exchange, f));
      if (val == null || val.isEmpty) return false;
    }
    return fields.isNotEmpty;
  }

  /// Get configuration status for all exchanges.
  static Future<Map<String, bool>> allStatus() async {
    final result = <String, bool>{};
    for (final ex in exchanges) {
      result[ex] = await isConfigured(ex);
    }
    return result;
  }

  /// Get all credentials for an exchange (for signing requests).
  static Future<Map<String, String>> getCredentials(String exchange) async {
    final fields = exchangeFields[exchange] ?? [];
    final creds = <String, String>{};
    for (final f in fields) {
      final val = await _storage.read(key: _key(exchange, f));
      if (val != null) creds[f] = val;
    }
    return creds;
  }
}
