import 'package:flutter/material.dart';
import 'api_keys_page.dart';
import 'arb_positions_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static const _bg = Color(0xFFF2F2F7);
  static const _label = Color(0xFF000000);
  static const _third = Color(0xFF8E8E93);
  static const _blue = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 8),
            const Text('我的',
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: _label,
                    letterSpacing: -0.5)),
            const SizedBox(height: 24),

            _item(context, Icons.key_outlined, '交易所 API 管理', '配置各交易所的 API Key',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ApiKeysPage()))),
            _item(context, Icons.swap_vert_rounded, '我的套利仓位', '查看活跃和历史套利记录',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ArbPositionsPage()))),
            _item(context, Icons.info_outline, '关于', 'Perp Tools v0.1.0'),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String title, String sub,
      {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: _third, size: 22),
        title: Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w500, color: _label)),
        subtitle:
            Text(sub, style: const TextStyle(fontSize: 12, color: _third)),
        trailing:
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC7C7CC)),
        onTap: onTap,
      ),
    );
  }
}
