require('dotenv').config();

const express = require('express');
const cors = require('cors');
const multer = require('multer');

const { createClient } = require('@supabase/supabase-js');

const app = express();

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

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY env vars');
}

const IMAGE_FIELD = process.env.CATCH_IMAGE_FIELD || 'image';
const STORE_IMAGE_BASE64 = (process.env.STORE_IMAGE_BASE64 || 'true').toLowerCase() === 'true';

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
// Species identify (stub)
// -----------------------
app.post('/v1/species/identify', async (req, res) => {
  // Keep minimal + stable: return a deterministic stub.
  // (Front-end will still work; later you can swap it to real ML.)
  return res.json({
    scientific_name: 'Thunnus thynnus',
    species_zh: '蓝鳍金枪鱼',
    confidence: 0.98,
    raw_label: 'stub_identification',
  });
});

// -----------------------
// Catches
// -----------------------
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
    payload.image_url = null;
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

module.exports = app;

if (require.main === module) {
  app.listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`[bff] listening on http://localhost:${PORT}`);
  });
}

