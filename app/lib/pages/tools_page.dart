import 'package:flutter/material.dart';
import 'risk_dashboard_page.dart';
import 'funding_arb_page.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 8),
            const Text('工具',
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C2C2E),
                    letterSpacing: -0.5)),
            const SizedBox(height: 20),

            // Risk dashboard entry
            _ToolCard(
              icon: Icons.shield_outlined,
              color: const Color(0xFF007AFF),
              title: '跨DEX风控',
              subtitle: '输入地址，查看 Hyperliquid / GMX / Aster / Lighter / dYdX 组合风险',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RiskDashboardPage())),
            ),
            const SizedBox(height: 12),

            // Placeholder entries for future tools
            _ToolCard(
              icon: Icons.notifications_outlined,
              color: const Color(0xFFFF9500),
              title: '清算预警',
              subtitle: '监控仓位附近的清算集群，提前预警级联风险',
              onTap: null,
              comingSoon: true,
            ),
            const SizedBox(height: 12),
            _ToolCard(
              icon: Icons.swap_horiz_rounded,
              color: const Color(0xFF34C759),
              title: '费率套利',
              subtitle: '8 个交易所费率对比，发现跨平台套利机会',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FundingArbPage())),
            ),
            const SizedBox(height: 12),
            _ToolCard(
              icon: Icons.auto_awesome_outlined,
              color: const Color(0xFFAF52DE),
              title: 'AI 风控助手',
              subtitle: '基于链上数据的智能仓位分析与风险建议',
              onTap: null,
              comingSoon: true,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool comingSoon;

  const _ToolCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2C2C2E))),
                      if (comingSoon) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('即将上线',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFF8A8A8E))),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8A8A8E))),
                ],
              ),
            ),
            if (!comingSoon)
              const Icon(Icons.chevron_right,
                  size: 18, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }
}
