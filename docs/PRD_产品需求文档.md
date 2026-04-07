# Perp Tools — 产品需求文档 (PRD)

**版本**: v0.1.0
**更新日期**: 2026-04-07
**平台**: iOS (Flutter)
**目标市场**: 海外加密衍生品交易者

---

## 一、产品定位

Perp Tools 是一个**永续合约交易工具平台**，为 Perp DEX 和 CEX 交易者提供数据分析、风险管理和套利工具。核心价值：让交易者用一个APP看清跨平台的风险和机会。

---

## 二、产品架构

### 底部4个Tab
| Tab | 名称 | 功能 | 状态 |
|-----|------|------|------|
| 1 | 数据 | 市场数据卡片（盈亏分布、交易者画像） | 已上线 |
| 2 | 发现 | 占位 | 未开发 |
| 3 | 工具 | 交易工具入口列表 | 已上线 |
| 4 | 我的 | API Key管理、套利仓位、设置 | 已上线 |

---

## 三、模块详细设计

### 模块1：数据Tab — 交易者盈亏分布

**文件**: `data_page.dart` + `assets/hyperliquid_distribution.json`

**功能描述**: 展示 Hyperliquid 排行榜交易者的盈亏分层分布，包含盈利和亏损用户。

**数据源**:
- API: `GET https://stats-data.hyperliquid.xyz/Mainnet/leaderboard`
- 范围: 排行榜收录地址 33.4K（非全量231K+用户）
- 刷新: CDN缓存约30-60分钟
- 处理: 因原始数据27MB太大无法在移动端直接下载，通过Mac端Python脚本预处理为几KB的JSON，打包到APP assets中

**数据分层**:
| 层级 | 条件 | 颜色 |
|------|------|------|
| >$1M | allTime PnL > $1M | 琥珀色 |
| $100K-$1M | $100K < PnL ≤ $1M | 紫色 |
| $1K-$100K | $1K < PnL ≤ $100K | 蓝色 |
| $0-$1K | $0 < PnL ≤ $1K | 天蓝色 |
| 亏损 | PnL ≤ $0 | 珊瑚红 |

**UI设计**:
- 左侧: 宽扁金字塔（CustomPaint梯形），每层颜色对应
- 右侧: 图例+地址数+占比，逐行与金字塔层对齐
- 底部: 绿红盈亏比例条（如44%盈利 / 56%亏损）
- 问号ⓘ: 点击弹出BottomSheet说明数据口径

**边界条件**:
- 无网络: 从本地asset加载，不依赖网络
- 数据缺失: 不显示卡片

---

### 模块2：数据Tab — 盈利交易者画像

**文件**: `data_page.dart`（_ProfileCard组件）+ `assets/profitable_profile.json`

**功能描述**: 对allTime PnL>0的盈利交易者进行多维画像分析。

**数据源**: 同模块1的Hyperliquid排行榜，Python预处理提取4组统计。

**4个Section**:

**A. ROI分布**
| 档位 | 含义 |
|------|------|
| >1000% | 超级赢家 |
| 100%-1000% | 大赢家 |
| 50%-100% | 中等赢家 |
| 10%-50% | 小赢家 |
| 0%-10% | 微利 |
+ 展示中位数和平均值

**B. 账户规模分布**
按当前accountValue分5档：>$1M / $100K-$1M / $10K-$100K / $1K-$10K / <$1K

**C. 交易量分布**
按allTime交易量分4档：>$100M / $10M-$100M / $1M-$10M / <$1M

**D. 短期盈利持续性**
在全周期盈利者中，有多少在更短时间窗口仍盈利：
- 近一月: X%
- 近一周: X%
- 近一天: X%

**UI设计**: 每个Section包含标题+中位数callout+水平堆叠条+图例行。持续性用递减宽度的绿色条形漏斗。

**数据口径标注**: 卡片副标题明确"排行榜 14.9K/33.4K 盈利"

---

### 模块3：工具Tab — 跨DEX风控仪表盘

**文件**: `risk_dashboard_page.dart` + `position_service.dart`

**功能描述**: 用户输入EVM钱包地址，自动查询5个Perp DEX的仓位，展示组合风险视图。

**支持平台**:
| 平台 | API | 认证 | 返回数据 |
|------|-----|------|---------|
| Hyperliquid | POST `/info` clearinghouseState | 无 | 仓位详情(币种/大小/杠杆/入场价/清算价/PnL) |
| GMX v2 | GET `arbitrum-api.gmxinfra.io/positions` | 无 | 全量仓位(需客户端过滤，1.7MB) |
| Aster | POST `tapi.asterdex.com/info` aster_getBalance | 无 | 余额+仓位(需有Aster账户) |
| Lighter | GET `zklighter.elliot.ai/api/v1/account` | 无 | 仓位详情 |
| dYdX v4 | GET `dydx-rest.publicnode.com` Cosmos LCD | 无 | 永续仓位(不被中国墙) |

**用户流程**:
1. 输入EVM地址(0x...) → 自动补0x前缀
2. 可选添加dYdX Cosmos地址(dydx1...)
3. 点击"查询仓位" → 5个API并发请求
4. 结果页三层架构展示

**结果页三层架构**:
- **第一层 — 健康度**: 环形保证金使用率(绿/黄/红) + 总净值 + 未实现PnL + 仓位数
- **第二层 — 仓位明细**: 按平台分卡片，每仓位显示方向/币种/杠杆/仓位金额/入场价/清算价/PnL，默认展示3个可展开
- **第三层 — 压力测试**: 滑块控制跌幅(-50%~+50%)，自动列出所有持仓币种的影响金额，底部合计

**风控特性**:
- 对冲检测: 同一币种在不同平台方向相反时提示
- 平台摘要: 底部显示"GMX / Aster / Lighter 已查询，无仓位"

**边界条件**:
| 场景 | 处理 |
|------|------|
| 地址不存在 | 该平台返回空，显示"无仓位" |
| API超时 | 单平台标"加载失败"，不阻塞其他 |
| 地址无0x前缀 | 自动补全 |
| Lighter返回400(无账户) | 视为"无仓位"而非错误 |
| 全部平台无仓位 | 显示"未找到任何仓位" |

---

### 模块4：工具Tab — 费率套利

**文件**: `funding_arb_page.dart` + `arb_detail_page.dart` + `funding_service.dart`

**功能描述**: 从8个交易所实时获取资金费率，计算跨平台套利机会，按年化收益排序展示。

**数据源(8个)**:
| 来源 | 类型 | 币种数 | 端点 |
|------|------|--------|------|
| Hyperliquid | DEX | 229 | POST `/info` metaAndAssetCtxs |
| dYdX | DEX | 294 | GET perpetualMarkets |
| Binance | CEX | 714 | GET premiumIndex |
| Bybit | CEX | 650 | GET tickers |
| Bitget | CEX | 551 | GET current-fund-rate |
| Gate.io | CEX | 642 | GET contracts |
| MEXC | CEX | 848 | GET ticker |
| OKX | CEX | 20(主流) | GET funding-rate (逐个查) |

**费率标准化**: 全部统一为8小时费率（HL每小时×8，其余已是8h）

**套利计算逻辑**:
1. 同一币种匹配所有平台费率
2. 找最高费率(做空方)和最低费率(做多方)
3. 价差 = 最高 - 最低
4. 年化 = 价差 × 3次/天 × 365天 × 100%
5. 按年化降序排列

**列表页UI**:
- 顶部统计: 机会数量 / 最高年化 / 数据源数
- 筛选: 最低年化阈值滑块(默认>10%)
- 卡片: 币种 + 年化 + 做多平台(费率+收入/支出) + 做空平台(费率+收入/支出) + 展开全平台费率
- 底部: 风险提示(费率变动、执行时差、资金效率)

**详情页(点击卡片进入)**:
- 概览: 年化 + 费率差 + 全平台费率表
- 历史费率折线图: 支持24h/7d/30d切换，多源折线对比（HL/Binance/Bybit/OKX/Gate 5个源的历史数据API）
- 执行套利: 输入金额 → 预估收益/手续费/回本周期 → 确认执行 → 并发下单 → 结果展示

**币种名称映射**:
```
HL: BTC → BTC
Binance: BTCUSDT → BTC (去USDT/USDC/1000前缀)
dYdX: BTC-USD → BTC
Gate: BTC_USDT → BTC
MEXC: BTC_USDT → BTC
OKX: BTC-USDT-SWAP → BTC
```

---

### 模块5：套利执行系统

**文件**: `trading_service.dart` + `crypto_signer.dart` + `arb_manager.dart` + `key_storage.dart`

**功能描述**: 用户配置交易所API Key后，可一键在两个平台同时开仓执行套利，并自动监控费率变化、触发平仓。

**API Key管理**:
- 存储: flutter_secure_storage（iOS Keychain加密）
- 7个交易所: HL(私钥) / Binance(Key+Secret) / Bybit(Key+Secret) / OKX(Key+Secret+Passphrase) / Bitget(Key+Secret+Passphrase) / Gate(Key+Secret) / MEXC(Key+Secret)
- 安全: 所有字段obscureText，存储后不再显示明文，签名本地完成不经服务器

**下单服务(trading_service.dart)**:
- 统一接口: `placeMarketOrder(platform, coin, side, quantity)`
- 签名方式: Binance/Bybit/Gate/MEXC用HMAC-SHA256，OKX/Bitget用HMAC-SHA256+Base64
- 支持: 下单 / 撤单 / 查余额

**执行流程**:
1. 获取当前价格(Hyperliquid allMids API)
2. 计算coin数量 = USD金额 / 当前价格
3. 并发向两个平台发送市价单
4. 两边都成功 → 保存仓位记录到SQLite
5. 一边失败 → 尝试撤销成功的那边 → 提示用户检查

**风控校验(下单前)**:
- 两平台API Key已配置且验证通过
- 余额充足(仓位金额+10%缓冲)
- 下单数量≥最小下单量
- 费率差仍然存在(重新拉取确认)
- 价差滑点<0.5%

**仓位管理(arb_positions_page.dart)**:
- 活跃仓位列表: 币种、平台、开仓时间、开仓年化、当前年化
- 手动平仓: 确认弹窗 → 两边市价平仓 → 计算净收益 → 归档
- 历史记录: 已平仓列表含净收益

**自动监控(前台)**:
- 每5分钟刷新费率，检查平仓条件
- 触发条件(可配置): 费率差收敛<0.005%/8h / 累计收益达标 / 持仓超限 / 费率反转
- 触发后自动执行平仓 + SnackBar通知

**数据持久化**: SQLite本地数据库，ArbPosition模型含完整生命周期字段

---

### 模块6：我的Tab

**文件**: `profile_page.dart` + `api_keys_page.dart` + `arb_positions_page.dart`

**入口列表**:
1. 交易所API管理 → API Key配置/验证/删除
2. 我的套利仓位 → 活跃仓位+历史记录(Tab切换)
3. 关于 → 版本信息

---

## 四、技术架构

### 技术栈
- 框架: Flutter 3.41.2 (Dart 3.11.0)
- 状态管理: setState (无第三方状态库)
- 网络: http包
- 加密存储: flutter_secure_storage
- 本地数据库: sqflite
- 签名: crypto (HMAC-SHA256)
- 图表: CustomPaint (无第三方图表库)

### 项目结构
```
app/
├── lib/
│   ├── main.dart              # 入口+底部导航
│   ├── pages/
│   │   ├── data_page.dart     # 数据Tab(盈亏分布+交易者画像)
│   │   ├── discover_page.dart # 发现Tab(占位)
│   │   ├── tools_page.dart    # 工具Tab(入口列表)
│   │   ├── profile_page.dart  # 我的Tab
│   │   ├── risk_dashboard_page.dart  # 跨DEX风控
│   │   ├── funding_arb_page.dart     # 费率套利列表
│   │   ├── arb_detail_page.dart      # 套利详情+历史图+执行
│   │   ├── arb_positions_page.dart   # 套利仓位管理
│   │   └── api_keys_page.dart        # API Key管理
│   ├── services/
│   │   ├── position_service.dart     # 5平台仓位查询
│   │   ├── funding_service.dart      # 8源费率+历史费率
│   │   ├── trading_service.dart      # 7交易所下单API
│   │   ├── crypto_signer.dart        # 签名工具
│   │   ├── key_storage.dart          # API Key加密存储
│   │   └── arb_manager.dart          # 仓位数据模型+SQLite
│   └── widgets/
│       └── funding_chart.dart        # 历史费率折线图
├── assets/
│   ├── hyperliquid_distribution.json # 预处理盈亏分布
│   └── profitable_profile.json       # 预处理交易者画像
└── ios/
    └── Runner/Assets.xcassets/AppIcon.appiconset/  # 应用图标
```

### 数据流
```
外部API → Service层(fetch+parse) → Page层(setState) → Widget(build)
                                           ↕
                              本地存储(secure_storage/sqflite/assets)
```

---

## 五、设计规范

- 风格: UXDA苹果HIG，扁平简约
- 背景: #F2F2F7 (iOS系统灰)
- 卡片: 白色 + 圆角20 + 无阴影
- 主色: #007AFF (iOS蓝)
- 盈利: #34C759 (iOS绿)
- 亏损: #FF3B30 (iOS红)
- 文字层级: #000000(标题) / #3C3C43(正文) / #8E8E93(副文) / #AEAEB2(提示)
- 字体: 系统默认(SF Pro)
- icon: 深蓝渐变底+青蓝柱状图

---

## 六、待开发功能

| 功能 | 优先级 | 描述 |
|------|--------|------|
| 发现Tab | P1 | 内容待定 |
| 清算预警 | P1 | 监控仓位附近的清算集群，提前预警级联风险 |
| AI风控助手 | P2 | 基于链上数据的智能仓位分析与风险建议 |
| 后端Proxy | P2 | 服务器缓存Hyperliquid leaderboard，APP秒级加载实时数据 |
| Hyperliquid链上下单 | P2 | EIP-712签名，支持HL一键执行 |
| 推送通知 | P3 | 后台费率变动/清算预警推送 |
| 多语言 | P3 | 英文/中文切换 |
