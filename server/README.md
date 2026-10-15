# 卡牌交易服务器部署指南

## 架构

- **平台**: Supabase Edge Functions (Deno + TypeScript)
- **数据库**: Supabase PostgreSQL（已有的免费项目）
- **费用**: 免费，无需信用卡
- **持久化**: PostgreSQL 自带持久化

## 文件结构

```
server/
├── README.md                          ← 本文件
└── supabase/
    ├── migrations/
    │   └── 001_init.sql               ← 建表脚本
    └── functions/
        └── card-trade/
            ├── index.ts               ← 7个端点主逻辑
            └── crypto.ts              ← HMAC + canonical JSON
```

## 部署步骤

### 1. 登录 Supabase Dashboard

打开 https://supabase.com/dashboard
项目: `mosdtstftotjcfgctaxg`（已有）

### 2. 执行建表 SQL

进入 **SQL Editor**，粘贴 `001_init.sql` 全部内容，执行。

验证：
```sql
SELECT table_name FROM information_schema.tables WHERE table_schema='public';
-- 应看到: devices, cards, packs, trades, receipts
```

### 3. 部署 Edge Function

**方式 A: Dashboard 手动部署**
1. 进入 Functions 页面
2. 新建 Function: `card-trade`
3. 把 `crypto.ts` 和 `index.ts` 内容粘贴进去

**方式 B: CLI 部署**
```bash
npm install -g supabase
supabase login
cd server/supabase
supabase functions deploy card-trade --project-ref mosdtstftotjcfgctaxg
```

### 4. 设置环境变量

在 Function 设置页添加：
- `SUPABASE_URL` = `https://mosdtstftotjcfgctaxg.supabase.co`
- `SUPABASE_SERVICE_ROLE_KEY` = Dashboard → Settings → API → service_role key

### 5. 验证

```bash
# ping 测试
curl https://mosdtstftotjcfgctaxg.supabase.co/functions/v1/card-trade/v1/market

# 应返回: {"items":[],"page":1,"page_size":20}
```

## 7 个端点

| # | 端点 | 方法 | 说明 |
|---|---|---|---|
| 1 | `/v1/devices/register` | POST | 注册设备+初始卡清单 |
| 2 | `/v1/packs` | POST | 提交 offer/cancel/enroll |
| 3 | `/v1/market?def=&want_def=&page=` | GET | 挂单列表 |
| 4 | `/v1/packs/{pack_id}/accept` | POST | 接受交易 |
| 5 | `/v1/receipts?device_id=&acked=false` | GET | 拉取未确认回执 |
| 6 | `/v1/receipts/{id}/ack` | POST | 确认回执 |
| 7 | `/v1/sync?device_id=&mac=` | GET | 对账同步 |

## 包名

- 游戏: `com.pipahua.cardmaster`
- 交易 App: `com.pipahua.cardmarket`
- ContentProvider authority: `com.pipahua.cardmarket.cardlink`
- 自定义权限: `com.pipahua.cardmarket.permission.CARD_LINK`