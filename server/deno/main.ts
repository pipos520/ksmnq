// card-trade Deno Deploy 主入口
// Deno KV 实现卡牌 1 换 1 交易（card-trade-spec.md §5 的 7 个端点）
//
// 部署后 URL: https://<project>.deno.dev/v1/<path>

import { canonicalJson, verifyMac, signReceipt, hmacSha256Base64, uuid, now } from "./crypto.ts";

// Deno KV - 在 Deno Deploy 上自动可用
const kv = await Deno.openKv();

const CORS: Record<string, string> = {
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

// ============ 主入口 ============

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }

  const url = new URL(req.url);
  const path = url.pathname;

  try {
    if (path === "/v1/devices/register" && req.method === "POST")
      return await handleRegister(req);
    if (path === "/v1/packs" && req.method === "POST")
      return await handleSubmitPack(req);
    if (path === "/v1/market" && req.method === "GET")
      return await handleMarket(url);
    if (path.match(/^\/v1\/packs\/[^/]+\/accept$/) && req.method === "POST")
      return await handleAccept(req, path);
    if (path === "/v1/receipts" && req.method === "GET")
      return await handleFetchReceipts(url);
    if (path.match(/^\/v1\/receipts\/[^/]+\/ack$/) && req.method === "POST")
      return await handleAckReceipt(req, path);
    if (path === "/v1/sync" && req.method === "GET")
      return await handleSync(url);

    return err("not_found", 404);
  } catch (e) {
    console.error("Unhandled:", e);
    return err("internal_error", 500);
  }
});

// ============ KV helper ============

// Key 结构:
// ["devices", device_id] -> { device_id, secret, max_seq, nickname, created_at }
// ["cards", uuid] -> { uuid, def, owner, state, pack_id, created_at }
// ["packs", pack_id] -> { pack_id, device_id, seq, type, give_json, want_def, state, created_at }
// ["packs_by_device", device_id, pack_id] -> true  (索引)
// ["packs_by_state", state, created_at, pack_id] -> pack_id (索引, 列表用)
// ["trades", trade_id] -> { trade_id, pack_id, seller, buyer, def_given, def_received, created_at }
// ["receipts", receipt_id] -> { receipt_id, device_id, payload, acked, created_at }
// ["receipts_unacked", device_id, created_at, receipt_id] -> true (索引)
// ["cards_by_owner", owner, uuid] -> true (索引)

async function getDevice(deviceId: string) {
  const res = await kv.get(["devices", deviceId]);
  return res.value as any | null;
}

async function getCard(cardUuid: string) {
  const res = await kv.get(["cards", cardUuid]);
  return res.value as any | null;
}

async function getPack(packId: string) {
  const res = await kv.get(["packs", packId]);
  return res.value as any | null;
}

// ============ 1. 注册 ============

async function handleRegister(req: Request): Promise<Response> {
  const body = await req.json();
  const { device_id, secret, initial_cards, mac } = body;
  if (!device_id || !secret || !initial_cards || !mac)
    return err("bad_request", 400);

  // 查已有
  const existing = await getDevice(device_id);
  if (existing) {
    if (existing.secret !== secret) return err("device_id_conflict", 409);
    return json({ ok: true, message: "already_registered" }, 200);
  }

  // 验 MAC
  const macOk = await verifyMac(body, secret);
  if (!macOk) return err("bad_mac", 401);

  const ts = now();

  // 事务: 插设备 + 批量插卡
  await kv.atomic()
    .set(["devices", device_id], {
      device_id, secret, max_seq: 0, created_at: ts,
    })
    .commit();

  if (Array.isArray(initial_cards) && initial_cards.length > 0) {
    const entries = [];
    for (const c of initial_cards) {
      entries.push(kv.atomic().set(["cards", c.uuid], {
        uuid: c.uuid, def: c.def, owner: device_id,
        state: "owned", pack_id: null, created_at: ts,
      }).set(["cards_by_owner", device_id, c.uuid], true).commit());
    }
    await Promise.all(entries);
  }

  return json({ ok: true }, 201);
}

// ============ 2. 提交 pack (offer / cancel / enroll) ============

async function handleSubmitPack(req: Request): Promise<Response> {
  const pack = await req.json();
  const { device_id, seq, type, pack_id } = pack;
  if (!device_id || seq === undefined || !type || !pack_id)
    return err("bad_request", 400);

  const dev = await getDevice(device_id);
  if (!dev) return err("device_not_found", 404);

  if (seq <= dev.max_seq) return err("seq_too_old", 409);

  const macOk = await verifyMac(pack, dev.secret);
  if (!macOk) return err("bad_mac", 401);

  const ts = now();

  if (type === "offer") return await handleOffer(pack, device_id, dev, ts);
  if (type === "cancel") return await handleCancel(pack, device_id, dev, ts);
  if (type === "enroll") return await handleEnroll(pack, device_id, dev, ts);
  return err("bad_type", 400);
}

// offer: 挂单
async function handleOffer(pack: any, deviceId: string, dev: any, ts: number): Promise<Response> {
  const give = pack.give;
  if (!give || !Array.isArray(give) || give.length === 0 || give.length > 5)
    return err("bad_give", 409);
  if (!pack.want || !pack.want.def)
    return err("bad_want", 409);

  // 校验每张卡
  for (const c of give) {
    const card = await getCard(c.uuid);
    if (!card) return err("dup_unknown_uuid", 409);
    if (card.owner !== deviceId) return err("card_not_owned", 409);
    if (card.state !== "owned") return err("card_locked", 409);
    if (card.def !== c.def) return err("card_def_mismatch", 409);
  }

  const packId = pack.pack_id;
  const seq = pack.seq;

  // 卡 → escrowed + 插 pack + 更新 max_seq
  const atomic = kv.atomic()
    .set(["packs", packId], {
      pack_id: packId, device_id: deviceId, seq,
      type: "offer", give_json: JSON.stringify(give),
      want_def: pack.want.def, state: "listed", created_at: ts,
    })
    .set(["packs_by_device", deviceId, packId], true)
    .set(["packs_by_state", "listed", ts, packId], packId)
    .set(["devices", deviceId], { ...dev, max_seq: seq });

  for (const c of give) {
    const card = await getCard(c.uuid);
    atomic.set(["cards", c.uuid], { ...card, state: "escrowed", pack_id: packId });
  }

  const res = await atomic.commit();
  if (!res.ok) return err("concurrent_modification", 409);

  return json({ ok: true, state: "listed" }, 201);
}

// cancel: 撤单
async function handleCancel(pack: any, deviceId: string, dev: any, ts: number): Promise<Response> {
  const cancelId = pack.cancel_pack_id;
  if (!cancelId) return err("bad_cancel", 400);

  const target = await getPack(cancelId);
  if (!target) return err("pack_not_found", 404);
  if (target.device_id !== deviceId) return err("not_owner", 403);
  if (target.state !== "listed") return err("not_listed", 409);

  const giveCards = JSON.parse(target.give_json);

  // 卡回 owned + pack → cancelled + max_seq
  const atomic = kv.atomic()
    .set(["packs", cancelId], { ...target, state: "cancelled" })
    .delete(["packs_by_state", "listed", target.created_at, cancelId])
    .set(["packs_by_state", "cancelled", ts, cancelId], cancelId)
    .set(["devices", deviceId], { ...dev, max_seq: pack.seq });

  for (const c of giveCards) {
    const card = await getCard(c.uuid);
    atomic.set(["cards", c.uuid], { ...card, state: "owned", pack_id: null });
  }

  const res = await atomic.commit();
  if (!res.ok) return err("concurrent_modification", 409);

  // 生成 refund receipt
  const refundReceipt: any = {
    v: 1, alg: "hmac-sha256", type: "refund",
    receipt_id: uuid(), trade_id: null,
    device_id: deviceId, pack_id: cancelId,
    receive: giveCards, give_away: [],
    server_time: ts, mac: "",
  };
  refundReceipt.mac = await signReceipt(refundReceipt, dev.secret);

  await kv.set(["receipts", refundReceipt.receipt_id], {
    receipt_id: refundReceipt.receipt_id, device_id: deviceId,
    payload: JSON.stringify(refundReceipt), acked: 0, created_at: ts,
  });
  await kv.set(["receipts_unacked", deviceId, ts, refundReceipt.receipt_id], true);

  return json({ ok: true, state: "cancelled" }, 200);
}

// enroll: 后续注册卡
async function handleEnroll(pack: any, deviceId: string, dev: any, ts: number): Promise<Response> {
  const initial = pack.initial_cards || [];
  if (initial.length > 60) return err("too_many_initial_cards", 409);

  for (const c of initial) {
    const existing = await getCard(c.uuid);
    if (!existing) {
      await kv.set(["cards", c.uuid], {
        uuid: c.uuid, def: c.def, owner: deviceId,
        state: "owned", pack_id: null, created_at: ts,
      });
      await kv.set(["cards_by_owner", deviceId, c.uuid], true);
    }
  }

  await kv.set(["devices", deviceId], { ...dev, max_seq: pack.seq });
  return json({ ok: true, state: "enrolled" }, 201);
}

// ============ 3. 市场列表 ============

async function handleMarket(url: URL): Promise<Response> {
  const def = url.searchParams.get("def") || "";
  const wantDef = url.searchParams.get("want_def") || "";
  const page = parseInt(url.searchParams.get("page") || "1");
  const pageSize = 20;

  // 扫描 listed packs
  const packIds: string[] = [];
  const iter = kv.list({ prefix: ["packs_by_state", "listed"] });
  for await (const entry of iter) {
    packIds.push(entry.value as string);
  }

  // 排序: 按 created_at 降序（key 里存的是 created_at）
  // key = ["packs_by_state", "listed", created_at, pack_id]
  packIds.reverse(); // KV list 按 key 正序，reverse 即降序

  let items: any[] = [];
  for (const packId of packIds) {
    const pack = await getPack(packId);
    if (!pack || pack.state !== "listed") continue;

    const give = JSON.parse(pack.give_json);
    if (def && !give.some((c: any) => c.def === def)) continue;
    if (wantDef && pack.want_def !== wantDef) continue;

    const dev = await getDevice(pack.device_id);
    items.push({
      pack_id: pack.pack_id,
      nickname: dev?.nickname || pack.device_id.substring(0, 6),
      give,
      want_def: pack.want_def,
      created_at: pack.created_at,
    });

    if (items.length >= pageSize * page) break;
  }

  const offset = (page - 1) * pageSize;
  const paged = items.slice(offset, offset + pageSize);

  return json({ items: paged, page, page_size: pageSize });
}

// ============ 4. 接受交易 ============

async function handleAccept(req: Request, path: string): Promise<Response> {
  const parts = path.split("/");
  const packId = parts[parts.length - 2]; // /v1/packs/{pack_id}/accept

  const body = await req.json();
  const { device_id: buyerId, give_uuid } = body;
  if (!buyerId || !give_uuid) return err("bad_request", 400);

  const buyerDev = await getDevice(buyerId);
  if (!buyerDev) return err("buyer_not_found", 404);

  const macOk = await verifyMac(body, buyerDev.secret);
  if (!macOk) return err("bad_mac", 401);

  const pack = await getPack(packId);
  if (!pack) return err("pack_not_found", 404);
  if (pack.state !== "listed") return err("not_listed", 409);
  if (pack.device_id === buyerId) return err("self_accept", 409);

  const buyerCard = await getCard(give_uuid);
  if (!buyerCard) return err("dup_unknown_uuid", 409);
  if (buyerCard.owner !== buyerId) return err("card_not_owned", 409);
  if (buyerCard.state !== "owned") return err("card_locked", 409);
  if (buyerCard.def !== pack.want_def) return err("def_mismatch", 409);

  const sellerGive = JSON.parse(pack.give_json); // [{uuid, def}]
  const sellerCardUuid = sellerGive[0].uuid;
  const sellerCardDef = sellerGive[0].def;
  const sellerId = pack.device_id;
  const sellerDev = await getDevice(sellerId);

  const ts = now();
  const tradeId = uuid();

  // 原子事务: 卡归属交换 + pack → traded + trade 记录
  const atomic = kv.atomic()
    .set(["packs", packId], { ...pack, state: "traded" })
    .delete(["packs_by_state", "listed", pack.created_at, packId])
    .set(["packs_by_state", "traded", ts, packId], packId)
    .set(["trades", tradeId], {
      trade_id: tradeId, pack_id: packId,
      seller: sellerId, buyer: buyerId,
      def_given: sellerCardDef, def_received: pack.want_def,
      created_at: ts,
    });

  // 卖家的卡 → 买家, state = traded
  const sellerCard = await getCard(sellerCardUuid);
  atomic.set(["cards", sellerCardUuid], {
    ...sellerCard, owner: buyerId, state: "traded", pack_id: null,
  })
    .delete(["cards_by_owner", sellerId, sellerCardUuid])
    .set(["cards_by_owner", buyerId, sellerCardUuid], true);

  // 买家的卡 → 卖家, state = traded
  atomic.set(["cards", give_uuid], {
    ...buyerCard, owner: sellerId, state: "traded", pack_id: null,
  })
    .delete(["cards_by_owner", buyerId, give_uuid])
    .set(["cards_by_owner", sellerId, give_uuid], true);

  // 更新双方 max_seq
  atomic.set(["devices", sellerId], { ...sellerDev, max_seq: Math.max(sellerDev.max_seq + 1, sellerDev.max_seq) });
  atomic.set(["devices", buyerId], { ...buyerDev, max_seq: Math.max(buyerDev.max_seq + 1, buyerDev.max_seq) });

  const res = await atomic.commit();
  if (!res.ok) return err("concurrent_modification_trade", 409);

  // 生成两条 trade_done receipt
  // 卖家视角
  const sellerReceipt: any = {
    v: 1, alg: "hmac-sha256", type: "trade_done",
    receipt_id: uuid(), trade_id: tradeId,
    device_id: sellerId, pack_id: packId,
    receive: [{ uuid: give_uuid, def: pack.want_def }],
    give_away: [{ uuid: sellerCardUuid, def: sellerCardDef }],
    server_time: ts, mac: "",
  };
  sellerReceipt.mac = await signReceipt(sellerReceipt, sellerDev.secret);

  // 买家视角
  const buyerReceipt: any = {
    v: 1, alg: "hmac-sha256", type: "trade_done",
    receipt_id: uuid(), trade_id: tradeId,
    device_id: buyerId, pack_id: packId,
    receive: [{ uuid: sellerCardUuid, def: sellerCardDef }],
    give_away: [{ uuid: give_uuid, def: pack.want_def }],
    server_time: ts, mac: "",
  };
  buyerReceipt.mac = await signReceipt(buyerReceipt, buyerDev.secret);

  await kv.atomic()
    .set(["receipts", sellerReceipt.receipt_id], {
      receipt_id: sellerReceipt.receipt_id, device_id: sellerId,
      payload: JSON.stringify(sellerReceipt), acked: 0, created_at: ts,
    })
    .set(["receipts_unacked", sellerId, ts, sellerReceipt.receipt_id], true)
    .set(["receipts", buyerReceipt.receipt_id], {
      receipt_id: buyerReceipt.receipt_id, device_id: buyerId,
      payload: JSON.stringify(buyerReceipt), acked: 0, created_at: ts,
    })
    .set(["receipts_unacked", buyerId, ts, buyerReceipt.receipt_id], true)
    .commit();

  return json({ ok: true, trade_id: tradeId, receipt_id: buyerReceipt.receipt_id }, 200);
}

// ============ 5. 拉取未确认回执 ============

async function handleFetchReceipts(url: URL): Promise<Response> {
  const deviceId = url.searchParams.get("device_id") || "";
  if (!deviceId) return err("bad_request", 400);

  const items: any[] = [];
  const iter = kv.list({ prefix: ["receipts_unacked", deviceId] });
  for await (const entry of iter) {
    // key = ["receipts_unacked", device_id, created_at, receipt_id]
    const receiptId = (entry.key as any[])[3];
    const r = await kv.get(["receipts", receiptId]);
    if (r.value) {
      const payload = JSON.parse((r.value as any).payload);
      items.push(payload);
    }
  }

  return json({ receipts: items });
}

// ============ 6. 确认回执 ============

async function handleAckReceipt(req: Request, path: string): Promise<Response> {
  const parts = path.split("/");
  const receiptId = parts[parts.length - 2]; // /v1/receipts/{id}/ack

  const body = await req.json();
  const { device_id } = body;
  if (!device_id) return err("bad_request", 400);

  const r = await kv.get(["receipts", receiptId]);
  if (!r.value) return err("receipt_not_found", 404);
  const receipt = r.value as any;
  if (receipt.device_id !== device_id) return err("not_owner", 403);

  // 标记 acked + 删除未确认索引
  await kv.atomic()
    .set(["receipts", receiptId], { ...receipt, acked: 1 })
    .delete(["receipts_unacked", device_id, receipt.created_at, receiptId])
    .commit();

  return json({ ok: true });
}

// ============ 7. 对账同步 ============

async function handleSync(url: URL): Promise<Response> {
  const deviceId = url.searchParams.get("device_id") || "";
  const mac = url.searchParams.get("mac") || "";
  if (!deviceId || !mac) return err("bad_request", 400);

  const dev = await getDevice(deviceId);
  if (!dev) return err("device_not_found", 404);

  // 验 MAC: canonical({device_id, mac})
  const verifyObj = { device_id: deviceId, mac: mac };
  const macOk = await verifyMac(verifyObj, dev.secret);
  if (!macOk) return err("bad_mac", 401);

  // 该设备所有 pack
  const packs: any[] = [];
  const packIter = kv.list({ prefix: ["packs_by_device", deviceId] });
  for await (const entry of packIter) {
    const packId = (entry.key as any[])[2];
    const pack = await getPack(packId);
    if (pack) packs.push({ pack_id: pack.pack_id, state: pack.state });
  }

  // 未确认回执
  const unacked: any[] = [];
  const recvIter = kv.list({ prefix: ["receipts_unacked", deviceId] });
  for await (const entry of recvIter) {
    const receiptId = (entry.key as any[])[3];
    const r = await kv.get(["receipts", receiptId]);
    if (r.value) {
      unacked.push(JSON.parse((r.value as any).payload));
    }
  }

  return json({
    max_seq: dev.max_seq,
    packs,
    unacked_receipts: unacked,
  });
}