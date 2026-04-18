'use strict';

/**
 * 物种参考图「鱼头」大致中心在图中的归一化坐标 (0~1)，供图鉴卡片 cover 裁切对齐。
 * 默认走豆包 / Ark 视觉模型（DOUBAO_API_KEY 或 ARK_API_KEY）；图片一律先转 base64 再以 data: URL 传入（与 server.js 物种识别一致），支持公网 URL、Supabase Storage、本机 assets/species/。
 * 豆包对单图有约 10MB / 3600 万像素等限制：若已安装 sharp，会在送豆包前自动缩小 JPEG 以规避 OversizeImage。
 * 未配置豆包密钥时，可回退 Gemini（GEMINI_API_KEY 等）；Gemini 429 时会按 Retry-After /「Please retry in Xs」重试若干次。
 */
const fs = require('fs');
const path = require('path');

/** 先读 fishing_almanac/.env 再读 backend/.env，后者同名变量覆盖前者（与脚本 cwd 无关）。 */
function loadEnvFiles() {
  const { config } = require('dotenv');
  const paths = [path.join(__dirname, '..', '.env'), path.join(__dirname, '.env')];
  for (const p of paths) {
    if (fs.existsSync(p)) config({ path: p, override: true });
  }
}
loadEnvFiles();

function getGeminiApiKey() {
  return (
    (process.env.GEMINI_API_KEY || '').trim() ||
    (process.env.GOOGLE_AI_API_KEY || '').trim() ||
    (process.env.GOOGLE_GENERATIVE_AI_API_KEY || '').trim() ||
    (process.env.GOOGLE_API_KEY || '').trim()
  );
}

const GEMINI_MODEL = (process.env.GEMINI_MODEL || 'gemini-2.0-flash').trim().replace(/^models\//, '');
const GEMINI_API_BASE = (process.env.GEMINI_API_BASE || 'https://generativelanguage.googleapis.com')
  .trim()
  .replace(/\/$/, '');

const DOUBAO_API_KEY = (process.env.DOUBAO_API_KEY || process.env.ARK_API_KEY || '').trim();

function normalizeDoubaoModelId(raw) {
  if (raw == null) return raw;
  let s = String(raw).trim();
  if (!s) return s;
  s = s.replace(/seed-1\.6-vision/gi, 'seed-1-6-vision');
  return s.toLowerCase();
}

const DOUBAO_MODEL_ID = normalizeDoubaoModelId(
  process.env.DOUBAO_MODEL_ID || process.env.ARK_MODEL_ID || 'doubao-seed-1-6-vision-250815',
);
const DOUBAO_API_BASE = (process.env.DOUBAO_API_BASE || 'https://ark.cn-beijing.volces.com/api/v3')
  .trim()
  .replace(/\/$/, '');

const HEAD_SYSTEM_PROMPT =
  '你是鱼类照片构图分析助手。给定一张鱼类物种参考照片，估算「鱼头」（眼与吻部区域）的中心在整幅图像中的相对位置。' +
  '只返回一个 JSON 对象，不要 markdown、不要代码块、不要其它文字。' +
  '字段 head_x、head_y 均为 0 到 1 的小数：(0,0) 为左上角，(1,1) 为右下角。' +
  '若有多条鱼，取画面中最大、最清晰的主体。若无鱼或完全无法判断，返回 {"head_x":0.5,"head_y":0.42}。';

const HEAD_USER_TEXT = '请分析图中鱼头的中心位置，只返回 JSON，例如 {"head_x":0.35,"head_y":0.48}。';

function clamp01(x) {
  const n = Number(x);
  if (!Number.isFinite(n)) return null;
  return Math.min(1, Math.max(0, n));
}

function mimeFromFilePath(absPath) {
  const lower = String(absPath).toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

/**
 * Flutter 打包路径 `assets/species/...` → 本机文件（仅脚本 / 有盘符环境可靠；Vercel 无此目录会失败）。
 */
function readLocalAssetImageBase64(imageUrl) {
  const raw = String(imageUrl || '').trim();
  if (!raw.startsWith('assets/')) return null;
  const root = (process.env.SPECIES_ASSETS_ROOT || path.join(__dirname, '..')).trim();
  const abs = path.normalize(path.join(root, raw.replace(/^\/+/, '')));
  if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) {
    throw new Error(
      `找不到本地物种图: ${abs}（请确认图片在 fishing_almanac/assets/species/，或设置 SPECIES_ASSETS_ROOT 为工程根目录）`,
    );
  }
  const buf = fs.readFileSync(abs);
  return { b64: buf.toString('base64'), mime: mimeFromFilePath(abs) };
}

function parseHeadJson(raw) {
  const s = String(raw || '').trim();
  const m = s.match(/\{[\s\S]*?\}/);
  if (!m) return { nx: 0.5, ny: 0.45 };
  try {
    const p = JSON.parse(m[0]);
    const nx = clamp01(p.head_x ?? p.headX ?? 0.5) ?? 0.5;
    const ny = clamp01(p.head_y ?? p.headY ?? 0.45) ?? 0.45;
    return { nx, ny };
  } catch (_) {
    return { nx: 0.5, ny: 0.45 };
  }
}

/**
 * 优先用 Service Role 走 Storage API（私有桶 / 非 public 直链时匿名 fetch 会失败，尤其在 Windows 脚本里）。
 */
async function fetchUrlToBase64(imageUrl) {
  const raw = String(imageUrl).trim();
  if (raw.startsWith('assets/')) {
    return readLocalAssetImageBase64(raw);
  }

  const supabaseUrl = (process.env.SUPABASE_URL || '').trim().replace(/\/$/, '');
  const serviceKey = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();

  if (supabaseUrl && serviceKey && raw.includes('/storage/v1/object/')) {
    try {
      const u = new URL(raw);
      let expectedHost;
      try {
        expectedHost = new URL(supabaseUrl).hostname;
      } catch (_) {
        expectedHost = null;
      }
      if (expectedHost && u.hostname === expectedHost) {
        const m = u.pathname.match(/\/storage\/v1\/object\/(?:public|sign|authenticated)\/([^/]+)\/(.+)$/);
        if (m) {
          const bucket = decodeURIComponent(m[1]);
          const objectPath = decodeURIComponent(m[2]);
          const { createClient } = require('@supabase/supabase-js');
          const client = createClient(supabaseUrl, serviceKey, {
            auth: { persistSession: false, autoRefreshToken: false },
          });
          const { data, error } = await client.storage.from(bucket).download(objectPath);
          if (error) {
            throw new Error(error.message || String(error));
          }
          if (data) {
            const ab = await data.arrayBuffer();
            const b64 = Buffer.from(ab).toString('base64');
            const mime =
              typeof data.type === 'string' && data.type && data.type !== 'application/octet-stream'
                ? data.type.split(';')[0].trim()
                : 'image/jpeg';
            return { b64, mime };
          }
        }
      }
    } catch (e) {
      console.warn('[species_image_head_focus_ai] Supabase storage download failed, trying HTTP:', e.message);
    }
  }

  let res;
  try {
    res = await fetch(raw, {
      headers: { 'User-Agent': 'fishing-almanac-species-head/1' },
    });
  } catch (e) {
    throw new Error(`拉取 image_url 网络失败: ${chainErrorDetail(e)}`);
  }
  if (!res.ok) throw new Error(`fetch image_url HTTP ${res.status}`);
  const ab = await res.arrayBuffer();
  const b64 = Buffer.from(ab).toString('base64');
  const ct = res.headers.get('content-type');
  const mime = (ct && ct.split(';')[0].trim()) || 'image/jpeg';
  return { b64, mime };
}

function sleepMs(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/** Node fetch 失败时常为 TypeError: fetch failed，真实原因在 cause 链里 */
function chainErrorDetail(err, maxDepth = 8) {
  const parts = [];
  let x = err;
  let depth = 0;
  while (x != null && depth < maxDepth) {
    const msg = typeof x.message === 'string' && x.message ? x.message : String(x);
    if (msg && (!parts.length || parts[parts.length - 1] !== msg)) parts.push(msg);
    if (x.code) parts.push(`code=${x.code}`);
    if (x.errno != null) parts.push(`errno=${x.errno}`);
    if (x.syscall) parts.push(`syscall=${x.syscall}`);
    x = x.cause;
    depth += 1;
  }
  return parts.join(' → ');
}

/** 429 时从响应体或 Retry-After 解析建议等待毫秒数 */
function gemini429WaitMs(apiRes, apiText) {
  const ra = apiRes && apiRes.headers && apiRes.headers.get && apiRes.headers.get('retry-after');
  if (ra) {
    const s = parseInt(String(ra).trim(), 10);
    if (Number.isFinite(s) && s > 0) return s * 1000 + 500;
  }
  const m = String(apiText || '').match(/Please retry in ([\d.]+)\s*s/i);
  if (m) return Math.ceil(parseFloat(m[1]) * 1000) + 800;
  return 22000;
}

async function callGeminiHead(imageUrl) {
  const { b64, mime } = await fetchUrlToBase64(imageUrl);
  const key = getGeminiApiKey();
  const url = `${GEMINI_API_BASE}/v1beta/models/${encodeURIComponent(GEMINI_MODEL)}:generateContent?key=${encodeURIComponent(key)}`;
  const body = {
    systemInstruction: { parts: [{ text: HEAD_SYSTEM_PROMPT }] },
    contents: [
      {
        role: 'user',
        parts: [{ text: HEAD_USER_TEXT }, { inlineData: { mimeType: mime, data: b64 } }],
      },
    ],
    generationConfig: { temperature: 0.15, maxOutputTokens: 256 },
  };

  const maxAttempts = 8;
  let apiRes;
  let apiText = '';
  let apiData = {};

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    apiRes = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    apiText = await apiRes.text().catch(() => '');
    try {
      apiData = apiText ? JSON.parse(apiText) : {};
    } catch (_) {
      apiData = {};
    }
    if (apiRes.ok) break;
    if (apiRes.status === 429 && attempt < maxAttempts - 1) {
      const waitMs = gemini429WaitMs(apiRes, apiText);
      console.warn(
        `[species_image_head_focus_ai] Gemini 429 配额/限速，等待 ${Math.round(waitMs / 1000)}s 后重试 (${attempt + 1}/${maxAttempts})…`,
      );
      await sleepMs(waitMs);
      continue;
    }
    const msg = (apiData.error && apiData.error.message) || apiText.slice(0, 400);
    throw new Error(`Gemini ${apiRes.status}: ${msg}`);
  }
  if (!apiRes.ok) {
    const msg = (apiData.error && apiData.error.message) || apiText.slice(0, 400);
    throw new Error(`Gemini ${apiRes.status}: ${msg}`);
  }
  const cand = apiData.candidates && apiData.candidates[0];
  if (!cand || !cand.content || !Array.isArray(cand.content.parts)) {
    throw new Error('Gemini 无有效 candidates');
  }
  let raw = '';
  for (const p of cand.content.parts) {
    if (p && typeof p.text === 'string') raw += p.text;
  }
  const { nx, ny } = parseHeadJson(raw);
  return { nx, ny, raw, engine: 'gemini' };
}

/**
 * 豆包 vision：约 10MB 解码体积、约 3600 万像素上限；大图用 sharp 压成 JPEG 再送。
 * 未安装 sharp 时原样返回（可能 400 OversizeImage）。
 */
async function downscaleForDoubaoIfNeeded(b64, mime) {
  let sharpMod;
  try {
    sharpMod = require('sharp');
  } catch (_) {
    return { b64, mime };
  }
  const input = Buffer.from(b64, 'base64');
  const MAX_BYTES = 9 * 1024 * 1024;
  const MAX_PIXELS = 33_000_000;
  const MAX_EDGE = 4000;

  let meta;
  try {
    meta = await sharpMod(input).metadata();
  } catch (e) {
    console.warn('[species_image_head_focus_ai] sharp 读图失败，原样送豆包:', e.message);
    return { b64, mime };
  }
  const w = meta.width || 1;
  const h = meta.height || 1;
  const pixels = w * h;
  if (input.length <= MAX_BYTES && pixels <= MAX_PIXELS && w <= MAX_EDGE && h <= MAX_EDGE) {
    return { b64, mime };
  }

  async function runResize(edge, quality) {
    return sharpMod(input)
      .rotate()
      .resize({ width: edge, height: edge, fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality, mozjpeg: true })
      .toBuffer();
  }

  let out = await runResize(MAX_EDGE, 86);
  if (out.length > MAX_BYTES) out = await runResize(2800, 78);
  if (out.length > MAX_BYTES) out = await runResize(2048, 72);
  if (out.length > MAX_BYTES) out = await runResize(1600, 68);

  return { b64: out.toString('base64'), mime: 'image/jpeg' };
}

async function callDoubaoHead(imageUrl) {
  if (!DOUBAO_API_KEY) {
    throw new Error('未配置 DOUBAO_API_KEY 或 ARK_API_KEY');
  }
  const rawB64 = await fetchUrlToBase64(imageUrl);
  const sized = await downscaleForDoubaoIfNeeded(rawB64.b64, rawB64.mime);
  const dataUrl = `data:${sized.mime};base64,${sized.b64}`;
  const payload = {
    model: DOUBAO_MODEL_ID,
    input: [
      { role: 'system', content: HEAD_SYSTEM_PROMPT },
      {
        role: 'user',
        content: [
          { type: 'input_image', image_url: dataUrl },
          { type: 'input_text', text: HEAD_USER_TEXT },
        ],
      },
    ],
  };
  const apiUrl = `${DOUBAO_API_BASE}/responses`;
  let apiRes;
  try {
    apiRes = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${DOUBAO_API_KEY}`,
      },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    throw new Error(
      `Doubao 网络请求失败: ${chainErrorDetail(e)}（目标 ${apiUrl}；请检查本机能否访问火山方舟、公司防火墙、系统/终端代理 HTTP_PROXY HTTPS_PROXY）`,
    );
  }
  if (!apiRes.ok) {
    const errText = await apiRes.text().catch(() => '');
    throw new Error(`Doubao ${apiRes.status}: ${errText.slice(0, 400)}`);
  }
  let apiData;
  try {
    apiData = await apiRes.json();
  } catch (e) {
    throw new Error(`Doubao 读取/解析响应失败: ${chainErrorDetail(e)}`);
  }
  let rawContent = '';
  if (apiData.output && Array.isArray(apiData.output)) {
    for (const item of apiData.output) {
      if (item.type === 'message' && Array.isArray(item.content)) {
        for (const c of item.content) {
          if (c.type === 'output_text' && c.text) {
            rawContent = c.text;
            break;
          }
        }
        if (rawContent) break;
      }
    }
  }
  if (!rawContent && apiData.choices && apiData.choices[0]) {
    rawContent = (apiData.choices[0].message && apiData.choices[0].message.content) || '';
  }
  const { nx, ny } = parseHeadJson(rawContent);
  return { nx, ny, raw: rawContent, engine: 'doubao' };
}

/**
 * @param {string} imageUrl 公网 URL，或 Flutter 资源路径 `assets/species/...`（本机需存在对应文件）
 * @returns {Promise<{ nx: number, ny: number, engine: string, raw?: string }>}
 */
async function analyzeSpeciesImageHeadFocus(imageUrl) {
  const url = String(imageUrl || '').trim();
  if (!url) {
    return { nx: 0.5, ny: 0.45, engine: 'default' };
  }

  if (DOUBAO_API_KEY) {
    const r = await callDoubaoHead(url);
    return { nx: r.nx, ny: r.ny, engine: r.engine, raw: r.raw };
  }

  if (getGeminiApiKey()) {
    const r = await callGeminiHead(url);
    return { nx: r.nx, ny: r.ny, engine: r.engine, raw: r.raw };
  }

  throw new Error('请配置 DOUBAO_API_KEY（或 ARK_API_KEY）；未配置豆包时可设置 GEMINI_API_KEY 作为回退');
}

module.exports = { analyzeSpeciesImageHeadFocus, parseHeadJson };
