import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Arbitrage position data model.
class ArbPosition {
  final String id;
  final String coin;
  final String longPlatform;
  final String shortPlatform;
  final double positionSize;
  final double quantity;
  final double longEntryPrice;
  final double shortEntryPrice;
  final double longRate8hAtOpen;
  final double shortRate8hAtOpen;
  final DateTime openedAt;
  final DateTime? closedAt;

  // Close conditions
  final double minSpreadToClose;
  final double? targetProfit;
  final int maxDays;

  // Status: opening, active, closing, closed, error
  final String status;

  // Close results
  final double? longClosePrice;
  final double? shortClosePrice;
  final double? totalFundingEarned;
  final double? totalFees;
  final double? netProfit;

  ArbPosition({
    required this.id,
    required this.coin,
    required this.longPlatform,
    required this.shortPlatform,
    required this.positionSize,
    required this.quantity,
    required this.longEntryPrice,
    required this.shortEntryPrice,
    required this.longRate8hAtOpen,
    required this.shortRate8hAtOpen,
    required this.openedAt,
    this.closedAt,
    this.minSpreadToClose = 0.00005,
    this.targetProfit,
    this.maxDays = 30,
    this.status = 'active',
    this.longClosePrice,
    this.shortClosePrice,
    this.totalFundingEarned,
    this.totalFees,
    this.netProfit,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'coin': coin,
    'longPlatform': longPlatform,
    'shortPlatform': shortPlatform,
    'positionSize': positionSize,
    'quantity': quantity,
    'longEntryPrice': longEntryPrice,
    'shortEntryPrice': shortEntryPrice,
    'longRate8hAtOpen': longRate8hAtOpen,
    'shortRate8hAtOpen': shortRate8hAtOpen,
    'openedAt': openedAt.millisecondsSinceEpoch,
    'closedAt': closedAt?.millisecondsSinceEpoch,
    'minSpreadToClose': minSpreadToClose,
    'targetProfit': targetProfit,
    'maxDays': maxDays,
    'status': status,
    'longClosePrice': longClosePrice,
    'shortClosePrice': shortClosePrice,
    'totalFundingEarned': totalFundingEarned,
    'totalFees': totalFees,
    'netProfit': netProfit,
  };

  static ArbPosition fromMap(Map<String, dynamic> m) => ArbPosition(
    id: m['id'],
    coin: m['coin'],
    longPlatform: m['longPlatform'],
    shortPlatform: m['shortPlatform'],
    positionSize: m['positionSize'],
    quantity: m['quantity'],
    longEntryPrice: m['longEntryPrice'],
    shortEntryPrice: m['shortEntryPrice'],
    longRate8hAtOpen: m['longRate8hAtOpen'],
    shortRate8hAtOpen: m['shortRate8hAtOpen'],
    openedAt: DateTime.fromMillisecondsSinceEpoch(m['openedAt']),
    closedAt: m['closedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['closedAt']) : null,
    minSpreadToClose: m['minSpreadToClose'] ?? 0.00005,
    targetProfit: m['targetProfit'],
    maxDays: m['maxDays'] ?? 30,
    status: m['status'] ?? 'active',
    longClosePrice: m['longClosePrice'],
    shortClosePrice: m['shortClosePrice'],
    totalFundingEarned: m['totalFundingEarned'],
    totalFees: m['totalFees'],
    netProfit: m['netProfit'],
  );

  ArbPosition copyWith({
    String? status,
    DateTime? closedAt,
    double? longClosePrice,
    double? shortClosePrice,
    double? totalFundingEarned,
    double? totalFees,
    double? netProfit,
    double? minSpreadToClose,
    double? targetProfit,
    int? maxDays,
  }) => ArbPosition(
    id: id, coin: coin, longPlatform: longPlatform, shortPlatform: shortPlatform,
    positionSize: positionSize, quantity: quantity,
    longEntryPrice: longEntryPrice, shortEntryPrice: shortEntryPrice,
    longRate8hAtOpen: longRate8hAtOpen, shortRate8hAtOpen: shortRate8hAtOpen,
    openedAt: openedAt,
    closedAt: closedAt ?? this.closedAt,
    minSpreadToClose: minSpreadToClose ?? this.minSpreadToClose,
    targetProfit: targetProfit ?? this.targetProfit,
    maxDays: maxDays ?? this.maxDays,
    status: status ?? this.status,
    longClosePrice: longClosePrice ?? this.longClosePrice,
    shortClosePrice: shortClosePrice ?? this.shortClosePrice,
    totalFundingEarned: totalFundingEarned ?? this.totalFundingEarned,
    totalFees: totalFees ?? this.totalFees,
    netProfit: netProfit ?? this.netProfit,
  );

  double get spreadAtOpen => shortRate8hAtOpen - longRate8hAtOpen;
  double get annualizedAtOpen => spreadAtOpen * 3 * 365 * 100;
  int get daysHeld => DateTime.now().difference(openedAt).inDays;
}

/// Local SQLite database for arbitrage position records.
class ArbDatabase {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'arb_positions.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE positions (
          id TEXT PRIMARY KEY,
          coin TEXT NOT NULL,
          longPlatform TEXT NOT NULL,
          shortPlatform TEXT NOT NULL,
          positionSize REAL NOT NULL,
          quantity REAL NOT NULL,
          longEntryPrice REAL NOT NULL,
          shortEntryPrice REAL NOT NULL,
          longRate8hAtOpen REAL NOT NULL,
          shortRate8hAtOpen REAL NOT NULL,
          openedAt INTEGER NOT NULL,
          closedAt INTEGER,
          minSpreadToClose REAL DEFAULT 0.00005,
          targetProfit REAL,
          maxDays INTEGER DEFAULT 30,
          status TEXT DEFAULT 'active',
          longClosePrice REAL,
          shortClosePrice REAL,
          totalFundingEarned REAL,
          totalFees REAL,
          netProfit REAL
        )
      ''');
    });
    return _db!;
  }

  static Future<void> insert(ArbPosition pos) async {
    final d = await db;
    await d.insert('positions', pos.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> update(ArbPosition pos) async {
    final d = await db;
    await d.update('positions', pos.toMap(), where: 'id = ?', whereArgs: [pos.id]);
  }

  static Future<List<ArbPosition>> getActive() async {
    final d = await db;
    final rows = await d.query('positions', where: "status IN ('active', 'opening')", orderBy: 'openedAt DESC');
    return rows.map(ArbPosition.fromMap).toList();
  }

  static Future<List<ArbPosition>> getClosed() async {
    final d = await db;
    final rows = await d.query('positions', where: "status = 'closed'", orderBy: 'closedAt DESC', limit: 50);
    return rows.map(ArbPosition.fromMap).toList();
  }

  static Future<List<ArbPosition>> getAll() async {
    final d = await db;
    final rows = await d.query('positions', orderBy: 'openedAt DESC');
    return rows.map(ArbPosition.fromMap).toList();
  }
}
