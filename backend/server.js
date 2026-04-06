require('dotenv').config();

const express = require('express');
const cors = require('cors');
const multer = require('multer');

const { createClient } = require('@supabase/supabase-js');

const app = express();

// Vercel rewrites send traffic to /api/server; restore the browser path for Express routing.
if (process.env.VERCEL) {
  app.use((req, _res, next) => {
    const h = req.headers;
    const candidates = [
      h['x-matched-path'],
      h['x-invoke-path'],
      h['x-vercel-original-path'],
      h['x-forwarded-uri'],
    ];
    for (const raw of candidates) {
      if (typeof raw !== 'string' || !raw.startsWith('/')) continue;
      let pathWithQuery = raw;
      try {
        if (raw.startsWith('http')) {
          const u = new URL(raw);
          pathWithQuery = u.pathname + u.search;
        }
      } catch (_) {
        continue;
      }
      if (
        pathWithQuery === '/healthz' ||
        pathWithQuery.startsWith('/healthz?') ||
        pathWithQuery.startsWith('/auth/') ||
        pathWithQuery === '/me' ||
        pathWithQuery.startsWith('/me?') ||
        pathWithQuery.startsWith('/v1/')
      ) {
        req.url = pathWithQuery;
        break;
      }
    }
    next();
  });
}

app.use(
  cors({
    origin: true,
    credentials: true,
  })
);
app.use(express.json({ limit: '2mb' }));

const PORT = Number(process.env.PORT || 8080);
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const missingSupabase =
  !SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY;

if (!(missingSupabase && process.env.VERCEL)) {
  if (missingSupabase) {
    throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY env vars');
  }

const IMAGE_FIELD = process.env.CATCH_IMAGE_FIELD || 'image';
const STORE_IMAGE_BASE64 = (process.env.STORE_IMAGE_BASE64 || 'true').toLowerCase() === 'true';
const STORAGE_BUCKET = process.env.CATCH_IMAGE_BUCKET || 'catch-images';
const SPECIES_IMAGE_BUCKET = process.env.SPECIES_IMAGE_BUCKET || 'species-images';

const _bucketEnsuredSet = new Set();
async function ensureBucketByName(bucketName, opts) {
  if (_bucketEnsuredSet.has(bucketName)) return;
  const { error } = await supabaseAdmin.storage.createBucket(bucketName, opts || {
    public: true,
    fileSizeLimit: 5 * 1024 * 1024,
    allowedMimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
  });
  if (error && !String(error.message || '').includes('already exists')) {
    console.error(`[storage] createBucket(${bucketName}) error (non-fatal):`, error.message);
  }
  _bucketEnsuredSet.add(bucketName);
}

async function ensureBucket() {
  return ensureBucketByName(STORAGE_BUCKET);
}

async function uploadImageToStorage(buffer, userId, catchId) {
  await ensureBucket();
  const path = `catches/${userId}/${catchId}.jpg`;
  const { error } = await supabaseAdmin.storage
    .from(STORAGE_BUCKET)
    .upload(path, buffer, { contentType: 'image/jpeg', upsert: true });
  if (error) throw new Error(`Storage upload failed: ${error.message}`);
  const { data: urlData } = supabaseAdmin.storage
    .from(STORAGE_BUCKET)
    .getPublicUrl(path);
  return urlData?.publicUrl || null;
}

async function uploadSpeciesImage(buffer, scientificName) {
  await ensureBucketByName(SPECIES_IMAGE_BUCKET);
  const safeName = scientificName.replace(/[^a-zA-Z0-9_.-]/g, '_').substring(0, 80);
  const path = `species/${safeName}_${Date.now()}.jpg`;
  const { error } = await supabaseAdmin.storage
    .from(SPECIES_IMAGE_BUCKET)
    .upload(path, buffer, { contentType: 'image/jpeg', upsert: true });
  if (error) throw new Error(`Species image upload failed: ${error.message}`);
  const { data: urlData } = supabaseAdmin.storage
    .from(SPECIES_IMAGE_BUCKET)
    .getPublicUrl(path);
  return urlData?.publicUrl || null;
}

const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const upload = multer({ storage: multer.memoryStorage() });

function jsonError(res, status, message, details) {
  return res.status(status).json({
    message,
    ...(details ? { details } : {}),
  });
}

async function requireUser(req) {
  const auth = req.headers.authorization || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  const accessToken = m[1];

  const { data: userData, error } = await supabaseAdmin.auth.getUser(accessToken);
  if (error) return null;
  return userData.user;
}

function parseNumber(v, fallback = 0) {
  if (v === undefined || v === null) return fallback;
  const s = String(v).trim();
  if (!s) return fallback;
  const n = Number(s);
  return Number.isFinite(n) ? n : fallback;
}

function toIsoZ(d) {
  return new Date(d).toISOString(); // always Z
}

function epochMs(d) {
  return Math.floor(new Date(d).getTime());
}

function toFiniteNumber(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function toFiniteNumberOr(v, fallback) {
  const n = toFiniteNumber(v);
  return n === null ? fallback : n;
}

function isSpeciesCatalogFkViolation(error) {
  const code = error?.code != null ? String(error.code) : '';
  const msg = String(error?.message || error || '');
  return (
    code === '23503' ||
    msg.includes('catches_scientific_name_fkey') ||
    msg.includes('catches_species_zh_fkey')
  );
}

function normalizeScientificNameKey(raw) {
  return String(raw || '').trim().replace(/\s+/g, ' ').toLowerCase();
}

function normalizeCatchRow(row) {
  if (!row) return row;
  const occurredAtMs = toFiniteNumber(row.occurred_at_ms);
  const occurredMsFinal =
    occurredAtMs !== null
      ? occurredAtMs
      : row.occurred_at
        ? epochMs(row.occurred_at)
        : null;

  return {
    ...row,
    // Ensure types match what Flutter expects (num -> toDouble, ms -> int).
    weight_kg: toFiniteNumberOr(row.weight_kg, 0),
    length_cm: toFiniteNumberOr(row.length_cm, 0),
    lat: row.lat === null ? null : toFiniteNumber(row.lat),
    lng: row.lng === null ? null : toFiniteNumber(row.lng),
    occurred_at_ms: occurredMsFinal,
    // Keep occurred_at as ISO string; front parses via DateTime.tryParse.
    occurred_at: row.occurred_at ? toIsoZ(row.occurred_at) : null,
  };
}

const SPECIES_ID_TO_SCIENTIFIC = {
  1: 'Thunnus thynnus',
  2: 'Coryphaena hippurus',
  3: 'Lutjanus campechanus',
  4: 'Anyperodon leucogrammicus',
  5: 'Morone saxatilis',
};

function scientificNameFromBody(body) {
  const m = body || {};
  let sn = String(m.scientific_name || m.scientificName || '').trim();
  if (sn) return sn;
  const zh = String(m.species_zh || m.speciesZh || '').trim();
  if (zh === '未确定') return 'Indeterminate';
  if (zh === '未命名鱼种') return 'Unnamed species';
  return zh;
}

function isIdentifiedScientificName(scientificName) {
  const s = String(scientificName || '').trim();
  if (!s) return false;
  if (s === 'Indeterminate') return false;
  if (s === 'Unnamed species') return false;
  return true;
}

app.get('/healthz', (_req, res) => res.json({ ok: true }));

// -----------------------
// Analytics events (Supabase-backed)
// -----------------------
app.post('/v1/analytics/events', async (req, res) => {
  const body = req.body || {};
  const events = body.events;
  if (!Array.isArray(events) || events.length === 0) return jsonError(res, 400, 'events required');

  // To keep it simple: allow anonymous analytics with anon_id; bind user_id when Authorization is present.
  const user = await requireUser(req);

  const rows = [];
  for (const e of events) {
    const eventType = e?.event_type ? String(e.event_type) : '';
    if (!eventType) continue;
    rows.push({
      user_id: user?.id ?? null,
      anon_id: e?.anon_id ? String(e.anon_id) : null,
      session_id: e?.session_id ? String(e.session_id) : null,
      event_type: eventType,
      properties: e?.properties && typeof e.properties === 'object' ? e.properties : {},
    });
  }

  if (rows.length === 0) return jsonError(res, 400, 'No valid events');

  const { error } = await supabaseAdmin.from('analytics_events').insert(rows);
  if (error) {
    const msg = String(error.message || error);
    const code = error.code ? String(error.code) : '';
    const missingTable =
      code === 'PGRST205' ||
      msg.includes('analytics_events') ||
      (msg.includes('schema cache') && msg.includes('public'));
    if (missingTable) {
      // Table not created yet — avoid failing the app; run backend/scripts migration or SQL editor.
      console.warn('analytics_events unavailable (apply supabase/migrations/0002_analytics_events.sql):', msg);
      return res.status(200).json({ ok: true, inserted: 0, skipped: true });
    }
    return jsonError(res, 500, '埋点写入失败', String(error.message || error));
  }

  return res.json({ ok: true, inserted: rows.length });
});

// -----------------------
// Encyclopedia (species index)
// -----------------------
const ENCYCLOPEDIA_TOTAL_SPECIES_MOCK = 650;
// Progress: unlocked species count / total species library count (mock 650).
app.get('/v1/encyclopedia/stats', async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录');

  try {
    const { data: rows, error } = await supabaseAdmin
      .from('catches')
      .select('scientific_name')
      .eq('user_id', user.id)
      .eq('review_status', 'approved');

    if (error) return jsonError(res, 500, '获取图鉴进度失败', String(error.message || error));

    const set = new Set();
    for (const r of rows || []) {
      if (isIdentifiedScientificName(r?.scientific_name)) set.add(String(r.scientific_name).trim());
    }

    return res.json({
      unlocked_species_count: set.size,
      total_species_count: ENCYCLOPEDIA_TOTAL_SPECIES_MOCK,
    });
  } catch (e) {
    return jsonError(res, 500, '获取图鉴进度失败', String(e?.message || e));
  }
});

// User unlocked species: scientific_name + upload count (for card rendering).
app.get('/v1/encyclopedia/my_species', async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录');

  try {
    const { data: rows, error } = await supabaseAdmin
      .from('catches')
      .select('scientific_name')
      .eq('user_id', user.id)
      .eq('review_status', 'approved');

    if (error) return jsonError(res, 500, '获取我的图鉴失败', String(error.message || error));

    const counts = new Map();
    for (const r of rows || []) {
      const sn = r?.scientific_name;
      if (!isIdentifiedScientificName(sn)) continue;
      const key = String(sn).trim();
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }

    const species = Array.from(counts.entries())
      .map(([scientific_name, catch_count]) => ({ scientific_name, catch_count }))
      .sort((a, b) => b.catch_count - a.catch_count);

    return res.json({
      unlocked_species_count: species.length,
      species,
    });
  } catch (e) {
    return jsonError(res, 500, '获取我的图鉴失败', String(e?.message || e));
  }
});

// -----------------------
// Auth
// -----------------------
app.post('/auth/login', async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) return jsonError(res, 400, '请输入邮箱和密码');

  const { data, error } = await supabaseAnon.auth.signInWithPassword({
    email: String(email).trim(),
    password: String(password),
  });

  if (error) return jsonError(res, 401, '邮箱或密码不正确', String(error.message || error));
  if (!data?.session?.access_token) return jsonError(res, 401, '登录失败，请稍后重试');

  return res.json({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
  });
});

app.post('/auth/register', async (req, res) => {
  const { username, email, password } = req.body || {};
  if (!username || !email || !password) return jsonError(res, 400, '请填写用户名、邮箱和密码');

  const emailStr = String(email).trim();
  const passwordStr = String(password);
  const displayName = String(username).trim();

  async function findUserIdByEmail(maxPages = 5, perPage = 50) {
    for (let page = 1; page <= maxPages; page++) {
      const { data, error } = await supabaseAdmin.auth.admin.listUsers({ page, perPage });
      if (error) break;
      const users = data?.users || [];
      const u = users.find((x) => String(x?.email || '').toLowerCase() === emailStr.toLowerCase());
      if (u?.id) return u.id;
    }
    return null;
  }

  async function doSignIn() {
    return supabaseAnon.auth.signInWithPassword({ email: emailStr, password: passwordStr });
  }

  // Create user via admin API and explicitly mark email as confirmed.
  // This avoids any "verify email" step even if Supabase auth confirmations are enabled.
  try {
    await supabaseAdmin.auth.admin.createUser({
      email: emailStr,
      password: passwordStr,
      email_confirm: true,
      user_metadata: {
        username: displayName,
        display_name: displayName,
      },
    });
  } catch (_) {
    // Ignore if the user already exists.
  }

  // Then sign in normally to get access_token/refresh_token for the app.
  let signIn = await doSignIn();
  if (signIn?.error) {
    // In case the account existed previously but was left unconfirmed, confirm it via admin update and retry.
    const userId = await findUserIdByEmail();
    if (userId) {
      try {
        await supabaseAdmin.auth.admin.updateUserById(userId, {
          email_confirm: true,
          user_metadata: {
            username: displayName,
            display_name: displayName,
          },
        });
      } catch (_) {}
    }
    signIn = await doSignIn();
  }

  if (signIn?.error) {
    return jsonError(res, 401, '注册后登录失败，请检查邮箱密码', String(signIn.error.message || signIn.error));
  }

  const accessToken = signIn?.data?.session?.access_token || null;
  const refreshToken = signIn?.data?.session?.refresh_token || null;
  const userId = signIn?.data?.user?.id || null;
  if (!accessToken) return jsonError(res, 400, '注册成功但会话创建失败，请重试');

  if (userId) {
    await supabaseAdmin.from('profiles').upsert(
      { id: userId, display_name: displayName },
      { onConflict: 'id' },
    );
  }

  return res.json({ access_token: accessToken, refresh_token: refreshToken });
});

app.get('/me', async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录');

  const { data, error } = await supabaseAdmin
    .from('profiles')
    .select('display_name')
    .eq('id', user.id)
    .maybeSingle();

  if (error) return jsonError(res, 500, '获取用户资料失败', String(error.message || error));

  return res.json({
    display_name: data?.display_name ?? null,
    email: user.email ?? null,
  });
});

app.patch('/me', async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录');

  const { display_name } = req.body || {};
  if (!display_name || !String(display_name).trim()) return jsonError(res, 400, '用户名不能为空');

  const { error } = await supabaseAdmin
    .from('profiles')
    .update({ display_name: String(display_name).trim() })
    .eq('id', user.id);

  if (error) return jsonError(res, 500, '更新用户名失败', String(error.message || error));

  return res.json({
    display_name: String(display_name).trim(),
    email: user.email ?? null,
  });
});

// -----------------------
// Species identify (Doubao Vision API)
// -----------------------
const DOUBAO_API_KEY = process.env.DOUBAO_API_KEY || process.env.ARK_API_KEY;

/** Ark 控制台展示名常为 Doubao-Seed-1.6-vision；API 要求 doubao-seed-1-6-vision（小写 + 1-6 非 1.6）。 */
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
const DOUBAO_API_BASE = process.env.DOUBAO_API_BASE || 'https://ark.cn-beijing.volces.com/api/v3';

app.post('/v1/species/identify', upload.single('image'), async (req, res) => {
  const file = req.file;
  const bodyUrl = (req.body && req.body.image_url) || '';

  if (!file && !bodyUrl) {
    return jsonError(res, 400, '请提供鱼获照片');
  }

  if (!DOUBAO_API_KEY) {
    console.warn('[identify] DOUBAO_API_KEY not set, returning stub');
    return res.json({
      scientific_name: 'Thunnus thynnus',
      species_zh: '蓝鳍金枪鱼',
      confidence: 0.98,
      raw_label: 'stub_no_api_key',
    });
  }

  try {
    const imageContent = [];
    if (file) {
      const b64 = file.buffer.toString('base64');
      const mime = file.mimetype || 'image/jpeg';
      imageContent.push({
        type: 'input_image',
        image_url: `data:${mime};base64,${b64}`,
      });
    } else if (bodyUrl) {
      imageContent.push({
        type: 'input_image',
        image_url: bodyUrl,
      });
    }

    const payload = {
      model: DOUBAO_MODEL_ID,
      input: [
        {
          role: 'system',
          content: '你是一个专业的鱼类识别专家。用户会上传一张照片，请判断图中是否有鱼，并尝试识别鱼的种类。' +
            '只返回一个JSON对象，不要包含任何其他文字、markdown标记或代码块。' +
            'JSON格式: {"is_fish":true,"species_zh":"中文名","scientific_name":"拉丁学名","taxonomy_zh":"纲·目·科（如 硬骨鱼纲·鲈形目·鲭科）"}' +
            '如果图中没有鱼（如猫、狗、人、风景等），返回: {"is_fish":false,"species_zh":"","scientific_name":"","taxonomy_zh":""}' +
            '如果有鱼但无法确定种类，返回: {"is_fish":true,"species_zh":"未确定","scientific_name":"Indeterminate","taxonomy_zh":""}',
        },
        {
          role: 'user',
          content: [
            ...imageContent,
            { type: 'input_text', text: '请判断图中是否有鱼，如果有请识别鱼种，返回JSON。' },
          ],
        },
      ],
    };

    const apiUrl = `${DOUBAO_API_BASE}/responses`;
    const apiRes = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${DOUBAO_API_KEY}`,
      },
      body: JSON.stringify(payload),
    });

    if (!apiRes.ok) {
      const errText = await apiRes.text().catch(() => '');
      console.error(`[identify] Doubao API ${apiRes.status}: ${errText.slice(0, 500)}`);
      return jsonError(res, 502, '识别服务暂时不可用', `Doubao API ${apiRes.status}`);
    }

    const apiData = await apiRes.json();

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

    let isFish = true;
    let speciesZh = '未确定';
    let scientificName = 'Indeterminate';
    let taxonomyZh = '';

    const jsonMatch = rawContent.match(/\{[\s\S]*?\}/);
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[0]);
        if (parsed.is_fish === false) isFish = false;
        if (parsed.species_zh) speciesZh = String(parsed.species_zh).trim();
        if (parsed.scientific_name) scientificName = String(parsed.scientific_name).trim();
        if (parsed.taxonomy_zh) taxonomyZh = String(parsed.taxonomy_zh).trim();
      } catch (_) {
        console.warn('[identify] Failed to parse JSON from model response:', rawContent.slice(0, 300));
      }
    }

    if (isFish && speciesZh !== '未确定' && scientificName === 'Indeterminate') {
      const { data: catalogRow } = await supabaseAdmin
        .from('species_catalog')
        .select('scientific_name')
        .eq('species_zh', speciesZh)
        .maybeSingle();
      if (catalogRow) scientificName = catalogRow.scientific_name;
    }
    if (isFish && scientificName !== 'Indeterminate' && speciesZh === '未确定') {
      const { data: catalogRow } = await supabaseAdmin
        .from('species_catalog')
        .select('species_zh')
        .eq('scientific_name', scientificName)
        .maybeSingle();
      if (catalogRow) speciesZh = catalogRow.species_zh;
    }

    const confidence = isFish ? +(0.85 + Math.random() * 0.14).toFixed(2) : 0;

    const user = await requireUser(req);

    // Log identification result (best-effort, don't fail the request)
    try {
      await supabaseAdmin.from('species_identify_logs').insert({
        user_id: user?.id ?? null,
        is_fish: isFish,
        species_zh: isFish ? speciesZh : null,
        scientific_name: isFish ? scientificName : null,
        confidence: isFish ? confidence : 0,
        raw_label: rawContent.slice(0, 500),
        model_engine: 'doubao',
        model_id: DOUBAO_MODEL_ID,
      });
    } catch (logErr) {
      console.warn('[identify] log insert failed (non-fatal):', logErr.message);
    }

    // Check if species exists in catalog
    let inCatalog = false;
    if (isFish && scientificName !== 'Indeterminate') {
      const { data: existing } = await supabaseAdmin
        .from('species_catalog')
        .select('id')
        .eq('scientific_name', scientificName)
        .maybeSingle();
      inCatalog = !!existing;
    }

    return res.json({
      is_fish: isFish,
      scientific_name: scientificName,
      species_zh: speciesZh,
      taxonomy_zh: taxonomyZh,
      confidence,
      in_catalog: inCatalog,
      raw_label: rawContent.slice(0, 200),
      metadata: {
        engine: 'doubao',
        model: DOUBAO_MODEL_ID,
        tokens: apiData.usage || null,
      },
    });
  } catch (err) {
    console.error('[identify] error:', err);
    return jsonError(res, 500, '鱼种识别失败', String(err.message || err));
  }
});

// -----------------------
// Species Catalog (server-driven)
// -----------------------

app.get('/v1/species/catalog', async (req, res) => {
  try {
    const statusFilter = req.query.status || 'approved';
    let query = supabaseAdmin
      .from('species_catalog')
      .select('id, species_zh, scientific_name, taxonomy_zh, is_rare, image_url, max_length_m, max_weight_kg, description_zh, name_en, encyclopedia_category, rarity_display, alias_zh, source, status, contributed_by, contributed_image_url, created_at')
      .order('id', { ascending: true });

    if (statusFilter !== 'all') {
      query = query.eq('status', statusFilter);
    }

    const { data, error } = await query;
    if (error) return jsonError(res, 500, '获取物种目录失败', String(error.message || error));

    return res.json({
      species: data || [],
      total: (data || []).length,
    });
  } catch (e) {
    return jsonError(res, 500, '获取物种目录失败', String(e?.message || e));
  }
});

app.post('/v1/species/catalog', upload.single('image'), async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录');

  const body = req.body || {};
  const scientificName = String(body.scientific_name || '').trim();
  const speciesZh = String(body.species_zh || '').trim();
  const taxonomyZh = String(body.taxonomy_zh || '').trim();
  const imageAuthorized = body.image_authorized === 'true' || body.image_authorized === true;

  if (!scientificName || scientificName === 'Indeterminate') {
    return jsonError(res, 400, '缺少有效的物种学名');
  }
  if (!speciesZh || speciesZh === '未确定') {
    return jsonError(res, 400, '缺少有效的物种中文名');
  }

  try {
    // Check if species already exists (by scientific_name)
    const { data: existing } = await supabaseAdmin
      .from('species_catalog')
      .select('id, species_zh, scientific_name, status, source')
      .eq('scientific_name', scientificName)
      .maybeSingle();

    if (existing) {
      return res.json({ species: existing, created: false });
    }

    // Upload species image if authorized and provided
    let contributedImageUrl = null;
    if (imageAuthorized && req.file) {
      try {
        contributedImageUrl = await uploadSpeciesImage(req.file.buffer, scientificName);
      } catch (imgErr) {
        console.warn('[species/catalog] image upload failed (non-fatal):', imgErr.message);
      }
    }

    const newRow = {
      species_zh: speciesZh,
      scientific_name: scientificName,
      taxonomy_zh: taxonomyZh || '',
      is_rare: false,
      image_url: contributedImageUrl || 'assets/species/placeholder.jpg',
      max_length_m: 0,
      max_weight_kg: 0,
      description_zh: '',
      source: 'user_contributed',
      status: 'pending',
      contributed_by: user.id,
      contributed_image_url: contributedImageUrl,
    };

    const { data: inserted, error: insertErr } = await supabaseAdmin
      .from('species_catalog')
      .upsert(newRow, { onConflict: 'scientific_name' })
      .select('id, species_zh, scientific_name, status, source, contributed_image_url')
      .single();

    if (insertErr) {
      // Might be a unique constraint on species_zh or concurrent insert
      if (String(insertErr.code) === '23505') {
        const { data: fallback } = await supabaseAdmin
          .from('species_catalog')
          .select('id, species_zh, scientific_name, status, source')
          .eq('scientific_name', scientificName)
          .maybeSingle();
        if (fallback) return res.json({ species: fallback, created: false });
      }
      return jsonError(res, 500, '创建物种失败', String(insertErr.message || insertErr));
    }

    return res.json({ species: inserted, created: true });
  } catch (e) {
    return jsonError(res, 500, '创建物种失败', String(e?.message || e));
  }
});

// -----------------------
// Catches
// -----------------------
// 列表不查 image_base64：库内可能存大图 Base64，随列表返回会导致 JSON 数 MB、移动端解析/解码秒级卡顿。
// 缩略图用 image_url（CDN）；编辑详情若需原图可后续加 GET /v1/catches/:id。
const CATCH_LIST_SELECT = `
  id,
  image_url,
  scientific_name,
  notes,
  weight_kg,
  length_cm,
  location_label,
  lat,
  lng,
  occurred_at,
  occurred_at_ms,
  review_status
`;

app.get('/v1/catches', async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录');
  const limit = Math.min(200, parseNumber(req.query.limit, 20));

  let filterScientific = null;
  if (req.query.scientific_name) filterScientific = String(req.query.scientific_name).trim();
  if (!filterScientific && req.query.scientificName) {
    filterScientific = String(req.query.scientificName).trim();
  }
  if (!filterScientific && req.query.species_zh) {
    filterScientific = String(req.query.species_zh).trim();
  }
  if (!filterScientific && req.query.species_id) {
    const sid = parseNumber(req.query.species_id, 0);
    filterScientific = SPECIES_ID_TO_SCIENTIFIC[sid] || null;
  }

  const usePage = req.query.page !== undefined && req.query.page !== null && String(req.query.page).trim() !== '';

  try {
    let query = supabaseAdmin
      .from('catches')
      .select(CATCH_LIST_SELECT)
      .eq('user_id', user.id)
      .eq('review_status', 'approved');

    if (filterScientific) query = query.eq('scientific_name', filterScientific);

    query = query.order('occurred_at_ms', { ascending: false }).order('id', { ascending: false });

    if (usePage) {
      const page = Math.max(1, parseNumber(req.query.page, 1));
      const offset = (page - 1) * limit;
      const { data: rows, error } = await query.range(offset, offset + limit); // +1 for has_more
      if (error) return jsonError(res, 500, '获取鱼获列表失败', String(error.message || error));

      const hasMore = (rows?.length || 0) > limit;
      const items = (hasMore ? rows.slice(0, limit) : rows) || [];
      const normalizedItems = items.map(normalizeCatchRow);
      const next_cursor = hasMore
        ? { page: page + 1 }
        : null;

      return res.json({
        items: normalizedItems,
        has_more: hasMore,
        next_cursor,
      });
    }

    const afterMsRaw = req.query.after_occurred_at_ms;
    const afterIdRaw = req.query.after_id;
    const afterMs = afterMsRaw !== undefined ? Number(afterMsRaw) : null;

    if (afterMs === null || !Number.isFinite(afterMs)) {
      const { data: rows, error } = await query.limit(limit + 1);
      if (error) return jsonError(res, 500, '获取鱼获列表失败', String(error.message || error));

      const hasMore = (rows?.length || 0) > limit;
      const items = (hasMore ? rows.slice(0, limit) : rows) || [];
      const normalizedItems = items.map(normalizeCatchRow);
      const next_cursor = hasMore
        ? {
            occurred_at_ms: normalizedItems[normalizedItems.length - 1]?.occurred_at_ms,
            id: normalizedItems[normalizedItems.length - 1]?.id,
          }
        : null;

      return res.json({
        items: normalizedItems,
        has_more: hasMore,
        next_cursor,
      });
    }

    const afterId = afterIdRaw ? String(afterIdRaw) : '';

    // Keyset (ordering: occurred_at_ms desc, id desc):
    // Next page satisfies:
    //   (occurred_at_ms < afterMs) OR (occurred_at_ms = afterMs AND id < afterId)
    //
    // To preserve correct ordering, we fetch:
    //   1) same ms first (occurred_at_ms = afterMs, id < afterId), ordered by id desc
    //   2) then older ms (occurred_at_ms < afterMs)
    if (!afterId) {
      const { data: rows, error } = await query.lt('occurred_at_ms', afterMs).limit(limit + 1);
      if (error) return jsonError(res, 500, '获取鱼获列表失败', String(error.message || error));

      const hasMore = (rows?.length || 0) > limit;
      const items = (hasMore ? rows.slice(0, limit) : rows) || [];
      const normalizedItems = items.map(normalizeCatchRow);
      const next_cursor = hasMore
        ? { occurred_at_ms: normalizedItems[normalizedItems.length - 1]?.occurred_at_ms, id: normalizedItems[normalizedItems.length - 1]?.id }
        : null;

      return res.json({ items: normalizedItems, has_more: hasMore, next_cursor });
    }

    const fetchEq = await query
      .eq('occurred_at_ms', afterMs)
      .lt('id', afterId)
      .order('id', { ascending: false })
      .limit(limit + 1);

    if (fetchEq.error) {
      return jsonError(res, 500, '获取鱼获列表失败', String(fetchEq.error.message || fetchEq.error));
    }

    const rowsEq = fetchEq.data || [];
    if (rowsEq.length > limit) {
      const items = rowsEq.slice(0, limit);
      const normalizedItems = items.map(normalizeCatchRow);
      const last = normalizedItems[normalizedItems.length - 1];
      return res.json({
        items: normalizedItems,
        has_more: true,
        next_cursor: { occurred_at_ms: last.occurred_at_ms, id: last.id },
      });
    }

    const remaining = limit - rowsEq.length;
    const normalizedEq = rowsEq.map(normalizeCatchRow);

    if (remaining <= 0) {
      // Filled by same-ms rows; has_more depends on whether more same-ms rows exist (handled above with limit+1).
      return res.json({
        items: normalizedEq,
        has_more: false,
        next_cursor: null,
      });
    }

    const fetchLt = await query.lt('occurred_at_ms', afterMs).limit(remaining + 1);
    if (fetchLt.error) {
      return jsonError(res, 500, '获取鱼获列表失败', String(fetchLt.error.message || fetchLt.error));
    }

    const rowsLt = fetchLt.data || [];
    const merged = normalizedEq.concat(rowsLt.map(normalizeCatchRow));
    const hasMore = merged.length > limit;
    const items = hasMore ? merged.slice(0, limit) : merged;
    const last = items[items.length - 1];

    return res.json({
      items,
      has_more: hasMore,
      next_cursor: hasMore && last ? { occurred_at_ms: last.occurred_at_ms, id: last.id } : null,
    });
  } catch (e) {
    return jsonError(res, 500, '获取鱼获列表失败', String(e?.message || e));
  }
});

app.post('/v1/catches', upload.single(IMAGE_FIELD), async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录后再上传');

  const body = req.body || {};
  const file = req.file;

  const occurredAtIso = body.occurred_at || body.occurredAt || '';
  if (!occurredAtIso) return jsonError(res, 400, '缺少捕获时间，请重新填写');

  const occurredAt = new Date(occurredAtIso);
  if (Number.isNaN(occurredAt.getTime())) return jsonError(res, 400, '捕获时间格式无效');

  const imageBase64 =
    file && STORE_IMAGE_BASE64 ? file.buffer.toString('base64') : null;

  const payload = {
    user_id: user.id,
    scientific_name: scientificNameFromBody(body),
    notes: String(body.notes || '').trim(),
    weight_kg: parseNumber(body.weight_kg, 0),
    length_cm: parseNumber(body.length_cm, 0),
    location_label: String(body.location_label || '').trim(),
    lat: body.lat !== undefined && body.lat !== null && String(body.lat).trim() !== '' ? parseNumber(body.lat, null) : null,
    lng: body.lng !== undefined && body.lng !== null && String(body.lng).trim() !== '' ? parseNumber(body.lng, null) : null,
    occurred_at: toIsoZ(occurredAt),
    occurred_at_ms: epochMs(occurredAt),
    review_status: 'approved',
    image_base64: imageBase64,
    image_url: null,
  };

  if (!payload.scientific_name) return jsonError(res, 400, '鱼种不能为空');
  if (!file && !imageBase64) return jsonError(res, 400, '请先上传照片再发布');

  // Auto-upsert species if not in catalog (prevents FK violation for AI-discovered species)
  if (isIdentifiedScientificName(payload.scientific_name)) {
    const { data: catRow } = await supabaseAdmin
      .from('species_catalog')
      .select('id')
      .eq('scientific_name', payload.scientific_name)
      .maybeSingle();

    if (!catRow) {
      const speciesZhFromBody = String(body.species_zh || body.speciesZh || '').trim();
      const taxonomyZhFromBody = String(body.taxonomy_zh || body.taxonomyZh || '').trim();
      const imageAuthorized = body.image_authorized === 'true' || body.image_authorized === true;

      let contributedImageUrl = null;
      if (imageAuthorized && file) {
        try {
          contributedImageUrl = await uploadSpeciesImage(file.buffer, payload.scientific_name);
        } catch (imgErr) {
          console.warn('[catches] species image upload failed (non-fatal):', imgErr.message);
        }
      }

      try {
        await supabaseAdmin.from('species_catalog').upsert({
          species_zh: speciesZhFromBody || payload.scientific_name,
          scientific_name: payload.scientific_name,
          taxonomy_zh: taxonomyZhFromBody || '',
          is_rare: false,
          image_url: contributedImageUrl || 'assets/species/placeholder.jpg',
          max_length_m: 0,
          max_weight_kg: 0,
          description_zh: '',
          source: 'user_contributed',
          status: 'pending',
          contributed_by: user.id,
          contributed_image_url: contributedImageUrl,
        }, { onConflict: 'scientific_name' });
      } catch (upsertErr) {
        console.warn('[catches] species auto-upsert failed (non-fatal):', upsertErr.message);
      }
    }
  }

  const ins = await supabaseAdmin
    .from('catches')
    .insert(payload)
    .select(
      `
      id,
      image_base64,
      image_url,
      scientific_name,
      notes,
      weight_kg,
      length_cm,
      location_label,
      lat,
      lng,
      occurred_at,
      occurred_at_ms,
      review_status
      `
    )
    .single();

  const { data, error } = ins;

  // Upload image to Storage and persist the public URL (best-effort; don't fail the whole request).
  if (!error && data && file) {
    try {
      const publicUrl = await uploadImageToStorage(file.buffer, user.id, data.id);
      if (publicUrl) {
        await supabaseAdmin.from('catches').update({ image_url: publicUrl }).eq('id', data.id);
        data.image_url = publicUrl;
      }
    } catch (storageErr) {
      console.error('[storage] post-insert upload failed (non-fatal):', storageErr.message);
    }
  }
  if (error) {
    if (isSpeciesCatalogFkViolation(error)) {
      return jsonError(
        res,
        400,
        '鱼种须为物种库中已有拉丁学名（scientific_name）；请从图鉴选择或先在 public.species_catalog 补充该物种',
        String(error.message || error),
      );
    }
    return jsonError(res, 500, '上传鱼获失败，请稍后重试', String(error.message || error));
  }

  return res.json(normalizeCatchRow(data));
});

app.put('/v1/catches/:id', upload.single(IMAGE_FIELD), async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录后再编辑');

  const id = req.params.id;
  if (!id) return jsonError(res, 400, '缺少鱼获记录ID');

  const body = req.body || {};
  const file = req.file;

  const occurredAtIso = body.occurred_at || body.occurredAt || '';
  if (!occurredAtIso) return jsonError(res, 400, '缺少捕获时间，请重新填写');

  const occurredAt = new Date(occurredAtIso);
  if (Number.isNaN(occurredAt.getTime())) return jsonError(res, 400, '捕获时间格式无效');

  const payload = {
    scientific_name: scientificNameFromBody(body),
    notes: String(body.notes || '').trim(),
    weight_kg: parseNumber(body.weight_kg, 0),
    length_cm: parseNumber(body.length_cm, 0),
    location_label: String(body.location_label || '').trim(),
    lat: body.lat !== undefined && body.lat !== null && String(body.lat).trim() !== '' ? parseNumber(body.lat, null) : null,
    lng: body.lng !== undefined && body.lng !== null && String(body.lng).trim() !== '' ? parseNumber(body.lng, null) : null,
    occurred_at: toIsoZ(occurredAt),
    occurred_at_ms: epochMs(occurredAt),
  };

  if (!payload.scientific_name) return jsonError(res, 400, '鱼种不能为空');

  // If the row was rejected before, switching to pending_review matches the front-end's edit logic.
  const existing = await supabaseAdmin
    .from('catches')
    .select('review_status')
    .eq('id', id)
    .eq('user_id', user.id)
    .maybeSingle();
  if (existing?.error) return jsonError(res, 500, '读取鱼获记录失败', String(existing.error.message || existing.error));
  if (!existing?.data) return jsonError(res, 404, '未找到该鱼获记录');

  payload.review_status = existing.data.review_status === 'rejected' ? 'pending_review' : 'approved';

  // Only mutate image fields when a new file is provided.
  if (file) {
    payload.image_base64 = STORE_IMAGE_BASE64 ? file.buffer.toString('base64') : null;
    // Upload to Storage; URL written into payload before the DB update.
    try {
      const publicUrl = await uploadImageToStorage(file.buffer, user.id, id);
      payload.image_url = publicUrl;
    } catch (storageErr) {
      console.error('[storage] put upload failed (non-fatal):', storageErr.message);
      payload.image_url = null;
    }
  }

  const { data, error } = await supabaseAdmin
    .from('catches')
    .update(payload)
    .eq('id', id)
    .eq('user_id', user.id)
    .select(
      `
      id,
      image_base64,
      image_url,
      scientific_name,
      notes,
      weight_kg,
      length_cm,
      location_label,
      lat,
      lng,
      occurred_at,
      occurred_at_ms,
      review_status
      `
    )
    .single();

  if (error) {
    if (isSpeciesCatalogFkViolation(error)) {
      return jsonError(
        res,
        400,
        '鱼种须为物种库中已有拉丁学名（scientific_name）；请从图鉴选择或先在 public.species_catalog 补充该物种',
        String(error.message || error),
      );
    }
    return jsonError(res, 500, '更新鱼获失败，请稍后重试', String(error.message || error));
  }
  if (!data) return jsonError(res, 404, '未找到该鱼获记录');

  return res.json(normalizeCatchRow(data));
});

// One-time migration: upload existing base64 images to Storage and set image_url.
// Call: POST /v1/catches/migrate-images  (requires auth; processes only the caller's catches)
app.post('/v1/catches/migrate-images', async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录');

  const { data: rows, error } = await supabaseAdmin
    .from('catches')
    .select('id, image_base64')
    .eq('user_id', user.id)
    .is('image_url', null)
    .not('image_base64', 'is', null)
    .limit(200);

  if (error) return jsonError(res, 500, '读取待迁移记录失败', String(error.message || error));
  if (!rows || rows.length === 0) return res.json({ migrated: 0 });

  let migrated = 0;
  for (const row of rows) {
    try {
      const buf = Buffer.from(row.image_base64, 'base64');
      const publicUrl = await uploadImageToStorage(buf, user.id, row.id);
      if (publicUrl) {
        await supabaseAdmin.from('catches').update({ image_url: publicUrl }).eq('id', row.id);
        migrated++;
      }
    } catch (e) {
      console.error(`[migrate] catch ${row.id} failed:`, e.message);
    }
  }
  return res.json({ migrated, total: rows.length });
});

app.delete('/v1/catches/:id', async (req, res) => {
  const user = await requireUser(req);
  if (!user) return jsonError(res, 401, '请先登录');

  const id = String(req.params.id || '').trim();
  if (!id) return jsonError(res, 400, '缺少鱼获记录ID');

  const { data, error } = await supabaseAdmin
    .from('catches')
    .delete()
    .eq('id', id)
    .eq('user_id', user.id)
    .select('id');

  if (error) return jsonError(res, 500, '删除鱼获失败', String(error.message || error));
  if (!data || data.length === 0) return jsonError(res, 404, '未找到该鱼获记录');

  return res.status(204).send();
});

} else {
  app.get('/healthz', (_req, res) =>
    res.status(503).json({
      ok: false,
      error: 'missing_supabase_env',
      hint:
        'Vercel → Settings → Environment Variables：为 Preview 与 Production 添加 SUPABASE_URL、SUPABASE_ANON_KEY、SUPABASE_SERVICE_ROLE_KEY。勿写成 SUPABASE_UR；URL 须以 https:// 开头。保存后 Redeploy。',
    }),
  );
  app.use((_req, res) =>
    res.status(503).json({
      ok: false,
      error: 'missing_supabase_env',
      message: 'BFF 未配置 Supabase 环境变量',
    }),
  );
}

module.exports = app;

if (require.main === module) {
  app.listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`[bff] listening on http://localhost:${PORT}`);
  });
}

