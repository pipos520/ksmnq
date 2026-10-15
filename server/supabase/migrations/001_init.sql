-- card-trade schema v1
-- 见 card-trade-spec.md 第5章

CREATE TABLE IF NOT EXISTS devices (
  device_id  TEXT PRIMARY KEY,            -- 32 hex
  secret     TEXT NOT NULL,               -- 64 hex, 仅注册时提交一次
  nickname   TEXT,
  max_seq    INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS cards (
  uuid       TEXT PRIMARY KEY,            -- 全局唯一实例
  def        TEXT NOT NULL,               -- 卡牌定义 ID
  owner      TEXT NOT NULL,               -- device_id
  state      TEXT NOT NULL DEFAULT 'owned', -- owned | escrowed | traded
  pack_id    TEXT,                        -- escrowed 时关联挂单
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS packs (
  pack_id    TEXT PRIMARY KEY,
  device_id  TEXT NOT NULL,
  seq        INTEGER NOT NULL,
  type       TEXT NOT NULL,               -- offer | cancel | enroll
  give_json  TEXT NOT NULL,
  want_def   TEXT,
  state      TEXT NOT NULL DEFAULT 'listed', -- listed | traded | cancelled | rejected
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, seq)
);

CREATE TABLE IF NOT EXISTS trades (
  trade_id     TEXT PRIMARY KEY,
  pack_id      TEXT NOT NULL,
  seller       TEXT NOT NULL,
  buyer        TEXT NOT NULL,
  def_given    TEXT NOT NULL,
  def_received TEXT NOT NULL,
  created_at   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS receipts (
  receipt_id TEXT PRIMARY KEY,
  device_id  TEXT NOT NULL,               -- 接收方
  payload    TEXT NOT NULL,               -- 完整 receipt JSON(含 mac)原文
  acked      INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_cards_owner ON cards(owner);
CREATE INDEX IF NOT EXISTS idx_cards_state ON cards(state);
CREATE INDEX IF NOT EXISTS idx_packs_state ON packs(state);
CREATE INDEX IF NOT EXISTS idx_packs_device ON packs(device_id);
CREATE INDEX IF NOT EXISTS idx_receipts_device ON receipts(device_id);
CREATE INDEX IF NOT EXISTS idx_receipts_acked ON receipts(acked);
