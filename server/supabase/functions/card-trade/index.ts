// card-trade Edge Function 主入口
// Supabase Edge Functions (Deno) 实现 card-trade-spec.md §5 的 7 个端点
//
// 部署后 URL 形如:
//   https://mosdtstftotjcfgctaxg.supabase.co/functions/v1/card-trade/v1/packs
//
// 路由格式: /v1/<path>

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { canonicalJson, verifyMac, signReceipt, hmacSha256Base64, uuid, now } from "./crypto.ts";

const SUPABASE_URL = Deno.env.get("DB_URL") ?? "";
const SERVICE_KEY = Deno.env.get("DB_SERVICE_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false },
});

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
};

function json(body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS },
  });
}

function err(error: string, status = 409): Response {
  return json({ error }, status);
}

// ---- 主入口 ----

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }

  const url = new URL(req.url);
  // Edge Function 挂在 /functions/v1/card-trade 下，后面是实际路径
  let path = url.pathname;
  // 去掉 function 前缀（可能含也可能不含）
  path = path.replace(/^\/functions\/v1\/card-trade/, "");
  path = path.replace(/^\/card-trade/, "");
  if (!path.startsWith("/")) path = "/" + path;

  try {
    // 路由
    if (path === "/v1/devices/register" && req.method === "POST")
      return await handleRegister(req);
    if (path === "/v1/packs" && req.method === "POST")
      return await handleSubmitPack(req);
    if (path === "/v1/market" && req.method === "GET")
      return await handleMarket(req, url);
    if (path.match(/^\/v1\/packs\/[^/]+\/accept$/) && req.method === "POST")
      return await handleAccept(req, path);
    if (path === "/v1/receipts" && req.method === "GET")
      return await handleFetchReceipts(req, url);
    if (path.match(/^\/v1\/receipts\/[^/]+\/ack$/) && req.method === "POST")
      return await handleAckReceipt(req, path);
    if (path === "/v1/sync" && req.method === "GET")
      return await handleSync(req, url);

    return err("not_found", 404);
  } catch (e) {
    console.error("Unhandled:", e);
    return err("internal_error", 500);
  }
});

// ---- 1. 注册 ----

async function handleRegister(req: Request): Promise<Response> {
  const body = await req.json();
  const { device_id, secret, initial_cards, platform, mac } = body;
  if (!device_id || !secret || !initial_cards || !mac)
    return err("bad_request", 400);

  // 查已有
  const { data: existing } = await supabase
    .from("devices").select("secret").eq("device_id", device_id).single();

  if (existing) {
    if (existing.secret !== secret) return err("device_id_conflict", 409);
    return json({ ok: true, message: "already_registered" }, 200);
  }

  // 验 MAC: 对 canonical body（去 mac）算 HMAC，密钥 = secret
  const macOk = await verifyMac(body, secret);
  if (!macOk) return err("bad_mac", 401);

  const ts = now();

  // 事务: 插设备 + 批量插卡
  const { error: devErr } = await supabase
    .from("devices").insert({
      device_id, secret, max_seq: 0, created_at: ts,
    });
  if (devErr) return err("device_insert_failed: " + devErr.message, 500);

  if (initial_cards.length > 0) {
    const cardRows = initial_cards.map((c: any) => ({
      uuid: c.uuid, def: c.def, owner: device_id,
      state: "owned", created_at: ts,
    }));
    const { error: cardErr } = await supabase.from("cards").insert(cardRows);
    if (cardErr) {
      // 回滚设备
      await supabase.from("devices").delete().eq("device_id", device_id);
      return err("card_insert_failed: " + cardErr.message, 500);
    }
  }

  return json({ ok: true }, 201);
}

// ---- 2. 提交 pack (offer / cancel / enroll) ----

async function handleSubmitPack(req: Request): Promise<Response> {
  const pack = await req.json();
  const { device_id, seq, type, pack_id, mac: macField } = pack;
  if (!device_id || seq === undefined || !type || !pack_id)
    return err("bad_request", 400);

  // 查设备
  const { data: dev } = await supabase
    .from("devices").select("secret, max_seq").eq("device_id", device_id).single();
  if (!dev) return err("device_not_found", 404);

  // seq 校验
  if (seq <= dev.max_seq) return err("seq_too_old", 409);

  // 验 MAC
  const macOk = await verifyMac(pack, dev.secret);
  if (!macOk) return err("bad_mac", 401);

  const ts = now();

  if (type === "offer") {
    return await handleOffer(pack, device_id, seq, dev.max_seq, ts);
  } else if (type === "cancel") {
    return await handleCancel(pack, device_id, seq, dev.max_seq, ts);
  } else if (type === "enroll") {
    return await handleEnroll(pack, device_id, seq, dev.max_seq, ts);
  }
  return err("bad_type", 400);
}

// offer: 挂单
async function handleOffer(pack: any, deviceId: string, seq: number, maxSeq: number, ts: number): Promise<Response> {
  const give = pack.give;
  if (!give || !Array.isArray(give) || give.length === 0 || give.length > 5)
    return err("bad_give", 409);
  if (!pack.want || !pack.want.def)
    return err("bad_want", 409);

  // 校验每张卡
  for (const c of give) {
    const { data: card } = await supabase
      .from("cards").select("owner, state, def").eq("uuid", c.uuid).single();
    if (!card) return err("dup_unknown_uuid", 409);
    if (card.owner !== deviceId) return err("card_not_owned", 409);
    if (card.state !== "owned") return err("card_locked", 409);
    if (card.def !== c.def) return err("card_def_mismatch", 409);
  }

  // 事务: 卡 → escrowed + 插 pack + 更新 max_seq
  const { error: packErr } = await supabase.from("packs").insert({
    pack_id: pack.pack_id, device_id: deviceId, seq,
    type: "offer", give_json: JSON.stringify(give),
    want_def: pack.want.def, state: "listed", created_at: ts,
  });
  if (packErr) return err("pack_insert_failed: " + packErr.message, 500);

  for (const c of give) {
    await supabase.from("cards").update({
      state: "escrowed", pack_id: pack.pack_id,
    }).eq("uuid", c.uuid);
  }

  await supabase.from("devices").update({ max_seq: seq }).eq("device_id", deviceId);

  return json({ ok: true, state: "listed" }, 201);
}

// cancel: 撤单
async function handleCancel(pack: any, deviceId: string, seq: number, maxSeq: number, ts: number): Promise<Response> {
  const cancelId = pack.cancel_pack_id;
  if (!cancelId) return err("bad_cancel", 400);

  const { data: target } = await supabase
    .from("packs").select("device_id, state, give_json").eq("pack_id", cancelId).single();
  if (!target) return err("pack_not_found", 404);
  if (target.device_id !== deviceId) return err("not_owner", 403);
  if (target.state !== "listed") return err("not_listed", 409);

  // 卡回 owned
  const giveCards = JSON.parse(target.give_json);
  for (const c of giveCards) {
    await supabase.from("cards").update({
      state: "owned", pack_id: null,
    }).eq("uuid", c.uuid);
  }

  // pack → cancelled
  await supabase.from("packs").update({ state: "cancelled" }).eq("pack_id", cancelId);
  await supabase.from("devices").update({ max_seq: seq }).eq("device_id", deviceId);

  // 生成 refund receipt
  const refundReceipt = {
    v: 1, alg: "hmac-sha256", type: "refund",
    receipt_id: uuid(), trade_id: null,
    device_id: deviceId, pack_id: cancelId,
    receive: giveCards, give_away: [],
    server_time: ts, mac: "",
  };
  const { data: dev } = await supabase
    .from("devices").select("secret").eq("device_id", deviceId).single();
  refundReceipt.mac = await signReceipt(refundReceipt, dev.secret);

  await supabase.from("receipts").insert({
    receipt_id: refundReceipt.receipt_id, device_id: deviceId,
    payload: JSON.stringify(refundReceipt), acked: 0, created_at: ts,
  });

  return json({ ok: true, state: "cancelled" }, 200);
}

// enroll: 首注册后续（MVP 里 enroll 走 register 端点，这里处理兼容）
async function handleEnroll(pack: any, deviceId: string, seq: number, maxSeq: number, ts: number): Promise<Response> {
  // enroll 通常通过 /v1/devices/register 走；如果直接走 packs，则注册卡
  const initial = pack.initial_cards || [];
  if (initial.length > 60) return err("too_many_initial_cards", 409);

  // 幂等：卡已存在则跳过
  for (const c of initial) {
    const { data: existing } = await supabase
      .from("cards").select("uuid").eq("uuid", c.uuid).single();
    if (!existing) {
      await supabase.from("cards").insert({
        uuid: c.uuid, def: c.def, owner: deviceId,
        state: "owned", created_at: ts,
      });
    }
  }

  await supabase.from("devices").update({ max_seq: seq }).eq("device_id", deviceId);
  return json({ ok: true, state: "enrolled" }, 201);
}

// ---- 3. 市场列表 ----

async function handleMarket(req: Request, url: URL): Promise<Response> {
  const def = url.searchParams.get("def") || "";
  const wantDef = url.searchParams.get("want_def") || "";
  const page = parseInt(url.searchParams.get("page") || "1");
  const pageSize = 20;
  const offset = (page - 1) * pageSize;

  let query = supabase
    .from("packs").select(`
      pack_id, give_json, want_def, created_at,
      devices:device_id ( nickname, device_id )
    `).eq("state", "listed")
    .order("created_at", { ascending: false })
    .range(offset, offset + pageSize - 1);

  if (def) {
    // give_json 含指定 def
    query = query.ilike("give_json", `%${def}%`);
  }
  if (wantDef) {
    query = query.eq("want_def", wantDef);
  }

  const { data: packs, error } = await query;
  if (error) return err("query_failed: " + error.message, 500);

  const items = (packs || []).map((p: any) => {
    const give = JSON.parse(p.give_json);
    const dev = p.devices || {};
    return {
      pack_id: p.pack_id,
      nickname: dev.nickname || (dev.device_id || "").substring(0, 6),
      give,
      want_def: p.want_def,
      created_at: p.created_at,
    };
  });

  return json({ items, page, page_size: pageSize });
}

// ---- 4. 接受交易 ----

async function handleAccept(req: Request, path: string): Promise<Response> {
  const parts = path.split("/");
  const packId = parts[parts.length - 2]; // /v1/packs/{pack_id}/accept

  const body = await req.json();
  const { device_id: buyerId, give_uuid, mac } = body;
  if (!buyerId || !give_uuid) return err("bad_request", 400);

  // 买家设备
  const { data: buyerDev } = await supabase
    .from("devices").select("secret, max_seq").eq("device_id", buyerId).single();
  if (!buyerDev) return err("buyer_not_found", 404);

  // 验 MAC（body 去 mac）
  const macOk = await verifyMac(body, buyerDev.secret);
  if (!macOk) return err("bad_mac", 401);

  // pack 必须 listed
  const { data: pack } = await supabase
    .from("packs").select("*").eq("pack_id", packId).single();
  if (!pack) return err("pack_not_found", 404);
  if (pack.state !== "listed") return err("not_listed", 409);
  if (pack.device_id === buyerId) return err("self_accept", 409);

  // 买家选定的卡
  const { data: buyerCard } = await supabase
    .from("cards").select("owner, state, def").eq("uuid", give_uuid).single();
  if (!buyerCard) return err("dup_unknown_uuid", 409);
  if (buyerCard.owner !== buyerId) return err("card_not_owned", 409);
  if (buyerCard.state !== "owned") return err("card_locked", 409);
  if (buyerCard.def !== pack.want_def) return err("def_mismatch", 409);

  // 卖家的卡
  const sellerGive = JSON.parse(pack.give_json); // [{uuid, def}]
  const sellerCardUuid = sellerGive[0].uuid;
  const sellerCardDef = sellerGive[0].def;
  const sellerId = pack.device_id;

  const ts = now();
  const tradeId = uuid();

  // 事务: 卡归属交换 + pack → traded + trades 记录
  // 卖家的卡 → 买家, state = traded
  await supabase.from("cards").update({
    owner: buyerId, state: "traded", pack_id: null,
  }).eq("uuid", sellerCardUuid);

  // 买家的卡 → 卖家, state = traded
  await supabase.from("cards").update({
    owner: sellerId, state: "traded", pack_id: null,
  }).eq("uuid", give_uuid);

  // pack → traded
  await supabase.from("packs").update({ state: "traded" }).eq("pack_id", packId);

  // trade 记录
  await supabase.from("trades").insert({
    trade_id: tradeId, pack_id: packId,
    seller: sellerId, buyer: buyerId,
    def_given: sellerCardDef, def_received: pack.want_def,
    created_at: ts,
  });

  // 生成两条 trade_done receipt（分别用对方 secret 签 MAC）
  const { data: sellerDev } = await supabase
    .from("devices").select("secret, nickname").eq("device_id", sellerId).single();

  // 卖家视角: give_away = 卖家的卡, receive = 买家的卡
  const sellerReceipt: any = {
    v: 1, alg: "hmac-sha256", type: "trade_done",
    receipt_id: uuid(), trade_id: tradeId,
    device_id: sellerId, pack_id: packId,
    receive: [{ uuid: give_uuid, def: pack.want_def }],
    give_away: [{ uuid: sellerCardUuid, def: sellerCardDef }],
    server_time: ts, mac: "",
  };
  sellerReceipt.mac = await signReceipt(sellerReceipt, sellerDev.secret);

  // 买家视角: give_away = 买家的卡, receive = 卖家的卡
  const buyerReceipt: any = {
    v: 1, alg: "hmac-sha256", type: "trade_done",
    receipt_id: uuid(), trade_id: tradeId,
    device_id: buyerId, pack_id: packId,
    receive: [{ uuid: sellerCardUuid, def: sellerCardDef }],
    give_away: [{ uuid: give_uuid, def: pack.want_def }],
    server_time: ts, mac: "",
  };
  buyerReceipt.mac = await signReceipt(buyerReceipt, buyerDev.secret);

  await supabase.from("receipts").insert([
    {
      receipt_id: sellerReceipt.receipt_id, device_id: sellerId,
      payload: JSON.stringify(sellerReceipt), acked: 0, created_at: ts,
    },
    {
      receipt_id: buyerReceipt.receipt_id, device_id: buyerId,
      payload: JSON.stringify(buyerReceipt), acked: 0, created_at: ts,
    },
  ]);

  return json({ ok: true, trade_id: tradeId, receipt_id: buyerReceipt.receipt_id }, 200);
}

// ---- 5. 拉取未确认回执 ----

async function handleFetchReceipts(req: Request, url: URL): Promise<Response> {
  const deviceId = url.searchParams.get("device_id") || "";
  if (!deviceId) return err("bad_request", 400);

  const { data: receipts, error } = await supabase
    .from("receipts").select("payload").eq("device_id", deviceId)
    .eq("acked", 0).order("created_at", { ascending: true });

  if (error) return err("query_failed: " + error.message, 500);

  const items = (receipts || []).map((r: any) => JSON.parse(r.payload));
  return json({ receipts: items });
}

// ---- 6. 确认回执 ----

async function handleAckReceipt(req: Request, path: string): Promise<Response> {
  const parts = path.split("/");
  const receiptId = parts[parts.length - 2]; // /v1/receipts/{id}/ack

  const body = await req.json();
  const { device_id } = body;
  if (!device_id) return err("bad_request", 400);

  const { data: r } = await supabase
    .from("receipts").select("device_id").eq("receipt_id", receiptId).single();
  if (!r) return err("receipt_not_found", 404);
  if (r.device_id !== device_id) return err("not_owner", 403);

  const { error } = await supabase
    .from("receipts").update({ acked: 1 }).eq("receipt_id", receiptId);
  if (error) return err("update_failed: " + error.message, 500);

  return json({ ok: true });
}

// ---- 7. 对账同步 ----

async function handleSync(req: Request, url: URL): Promise<Response> {
  const deviceId = url.searchParams.get("device_id") || "";
  const mac = url.searchParams.get("mac") || "";
  if (!deviceId || !mac) return err("bad_request", 400);

  const { data: dev } = await supabase
    .from("devices").select("secret, max_seq").eq("device_id", deviceId).single();
  if (!dev) return err("device_not_found", 404);

  // 验 MAC: canonical({device_id, mac去掉})
  const verifyObj = { device_id: deviceId, mac: mac };
  const macOk = await verifyMac(verifyObj, dev.secret);
  if (!macOk) return err("bad_mac", 401);

  // 该设备所有 pack
  const { data: packs } = await supabase
    .from("packs").select("pack_id, state").eq("device_id", deviceId);

  // 未确认回执
  const { data: unacked } = await supabase
    .from("receipts").select("payload").eq("device_id", deviceId)
    .eq("acked", 0);

  return json({
    max_seq: dev.max_seq,
    packs: (packs || []).map((p: any) => ({ pack_id: p.pack_id, state: p.state })),
    unacked_receipts: (unacked || []).map((r: any) => JSON.parse(r.payload)),
  });
}