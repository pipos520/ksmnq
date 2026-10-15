// canonical JSON 序列化 + HMAC-SHA256
// 见 card-trade-spec.md §4.1
// 用于 Deno Deploy

/** 递归按 key 字典序排序、无空白、UTF-8 原文禁止 \uXXXX 转义 */
export function canonicalJson(v: any): string {
  if (v === null || v === undefined) return "null";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number") {
    if (Number.isInteger(v)) return String(v);
    return String(v);
  }
  if (typeof v === "string") return jsonString(v);
  if (Array.isArray(v)) {
    return "[" + v.map(canonicalJson).join(",") + "]";
  }
  if (typeof v === "object") {
    const keys = Object.keys(v).filter(k => v[k] !== undefined).sort();
    return "{" + keys.map(k => jsonString(k) + ":" + canonicalJson(v[k])).join(",") + "}";
  }
  return "null";
}

/** JSON 字符串转义，但保持非 ASCII 原文（禁止 \uXXXX） */
function jsonString(s: string): string {
  let out = '"';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 0x22) out += '\\"';        // "
    else if (c === 0x5c) out += '\\\\';   // backslash
    else if (c === 0x0a) out += '\\n';
    else if (c === 0x0d) out += '\\r';
    else if (c === 0x09) out += '\\t';
    else if (c === 0x08) out += '\\b';
    else if (c === 0x0c) out += '\\f';
    else if (c < 0x20) out += '\\u' + c.toString(16).padStart(4, '0');
    else out += s[i];  // UTF-8 原文，不转义
  }
  return out + '"';
}

/** HMAC-SHA256 → base64 */
export async function hmacSha256Base64(secretHex: string, data: string): Promise<string> {
  const key = hexToBytes(secretHex);
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw", key.buffer as ArrayBuffer, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(data));
  return bytesToBase64(new Uint8Array(sig));
}

/** 验证 pack 的 MAC（去掉 mac 字段后算 canonical HMAC） */
export async function verifyMac(obj: any, secretHex: string): Promise<boolean> {
  const expectMac: string = obj.mac || "";
  if (!expectMac) return false;
  const copy = { ...obj };
  delete copy.mac;
  const canonical = canonicalJson(copy);
  const computed = await hmacSha256Base64(secretHex, canonical);
  return computed === expectMac;
}

/** 生成 receipt 的 MAC */
export async function signReceipt(obj: any, secretHex: string): Promise<string> {
  const copy = { ...obj };
  delete copy.mac;
  const canonical = canonicalJson(copy);
  return await hmacSha256Base64(secretHex, canonical);
}

// ---- helpers ----

function hexToBytes(hex: string): Uint8Array {
  const buf = new ArrayBuffer(hex.length / 2);
  const out = new Uint8Array(buf);
  for (let i = 0; i < hex.length; i += 2) {
    out[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return out;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

export function uuid(): string {
  return crypto.randomUUID();
}

export function now(): number {
  return Math.floor(Date.now() / 1000);
}
