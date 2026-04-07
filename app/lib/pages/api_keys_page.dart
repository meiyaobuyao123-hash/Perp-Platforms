import 'package:flutter/material.dart';
import '../services/key_storage.dart';

class ApiKeysPage extends StatefulWidget {
  const ApiKeysPage({super.key});
  @override
  State<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends State<ApiKeysPage> {
  Map<String, bool> _status = {};
  bool _loading = true;

  static const _blue = Color(0xFF007AFF);
  static const _bg = Color(0xFFF2F2F7);
  static const _label = Color(0xFF000000);
  static const _third = Color(0xFF8E8E93);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final s = await KeyStorage.allStatus();
    if (mounted) setState(() { _status = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28, color: _blue),
          onPressed: () => Navigator.pop(context)),
        title: const Text('交易所 API 管理',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
              const SizedBox(height: 8),
              // Warning banner
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.lock_outline, size: 16, color: Color(0xFF856404)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text(
                    'API Key 仅加密存储在本机，不上传服务器。\n请只开启交易权限，务必关闭提现权限。',
                    style: TextStyle(fontSize: 13, color: Color(0xFF856404), height: 1.5),
                  )),
                ]),
              ),
              const SizedBox(height: 16),

              // Exchange list
              ...KeyStorage.exchanges.map((ex) {
                final configured = _status[ex] ?? false;
                final label = KeyStorage.exchangeLabels[ex] ?? ex;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(label,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _label)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: configured ? _green.withAlpha(15) : _bg,
                          borderRadius: BorderRadius.circular(6)),
                        child: Text(configured ? '已配置' : '未配置',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                                color: configured ? _green : _third)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC7C7CC)),
                    ]),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _ExchangeConfigPage(exchange: ex)));
                      _loadStatus();
                    },
                  ),
                );
              }),
              const SizedBox(height: 32),
            ]),
    );
  }
}

// ── Per-exchange config page ──

class _ExchangeConfigPage extends StatefulWidget {
  final String exchange;
  const _ExchangeConfigPage({required this.exchange});
  @override
  State<_ExchangeConfigPage> createState() => _ExchangeConfigPageState();
}

class _ExchangeConfigPageState extends State<_ExchangeConfigPage> {
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  bool _configured = false;
  String? _message;
  bool _success = false;

  static const _blue = Color(0xFF007AFF);
  static const _bg = Color(0xFFF2F2F7);
  static const _label = Color(0xFF000000);
  static const _third = Color(0xFF8E8E93);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);

  List<String> get _fields => KeyStorage.exchangeFields[widget.exchange] ?? [];
  String get _exLabel => KeyStorage.exchangeLabels[widget.exchange] ?? widget.exchange;

  static const _fieldLabels = {
    'apiKey': 'API Key',
    'secret': 'Secret Key',
    'passphrase': 'Passphrase',
    'privateKey': 'Private Key',
  };

  @override
  void initState() {
    super.initState();
    for (final f in _fields) _controllers[f] = TextEditingController();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    _configured = await KeyStorage.isConfigured(widget.exchange);
    // Don't load actual values (security: never show stored keys)
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() { _saving = true; _message = null; });

    for (final f in _fields) {
      final val = _controllers[f]!.text.trim();
      if (val.isEmpty) {
        setState(() { _saving = false; _message = '请填写 ${_fieldLabels[f] ?? f}'; _success = false; });
        return;
      }
    }

    for (final f in _fields) {
      await KeyStorage.save(widget.exchange, f, _controllers[f]!.text.trim());
    }

    setState(() {
      _saving = false;
      _configured = true;
      _message = '保存成功';
      _success = true;
      // Clear fields after save (don't keep in memory)
      for (final c in _controllers.values) c.clear();
    });
  }

  Future<void> _delete() async {
    await KeyStorage.delete(widget.exchange);
    setState(() { _configured = false; _message = '已删除'; _success = true; });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28, color: _blue),
          onPressed: () => Navigator.pop(context)),
        title: Text(_exLabel,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _label)),
        centerTitle: true,
      ),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
        const SizedBox(height: 16),

        if (_configured) ...[
          Container(
            decoration: BoxDecoration(color: _green.withAlpha(10), borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 18, color: _green),
              const SizedBox(width: 8),
              const Expanded(child: Text('已配置，如需更新请重新输入',
                  style: TextStyle(fontSize: 14, color: _green))),
              GestureDetector(
                onTap: _delete,
                child: const Text('删除', style: TextStyle(fontSize: 14, color: _red)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // Input fields
        ..._fields.map((f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_fieldLabels[f] ?? f,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _label)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _controllers[f],
              obscureText: true,
              style: const TextStyle(fontSize: 14, color: _label),
              decoration: InputDecoration(
                hintText: _configured ? '••••••••' : '请输入',
                hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ])),

        if (_message != null)
          Padding(padding: const EdgeInsets.only(bottom: 12),
            child: Text(_message!, style: TextStyle(fontSize: 14,
                color: _success ? _green : _red))),

        SizedBox(width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue, foregroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),

        const SizedBox(height: 24),
        Text(
          widget.exchange == 'hyperliquid'
              ? '请输入钱包私钥。Hyperliquid 通过链上交易下单，需要私钥进行签名。'
              : '请在 $_exLabel 后台创建 API Key，并只开启"交易"权限，关闭"提现"权限。',
          style: const TextStyle(fontSize: 12, color: _third, height: 1.5),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }
}
