/**
 * 不依赖数据库里 image_url 长什么样：直接扫描本机
 *   {SPECIES_ASSETS_ROOT}/assets/species/*.{jpg,jpeg,png,webp}
 * 用「文件名去掉扩展名」与 species_catalog.species_zh 精确匹配，再调用 AI 写回 image_head_nx / image_head_ny。
 *
 * 约定：图片文件名应与图鉴中文种名一致，例如 五线雀鲷.jpg → species_zh = 五线雀鲷
 *
 * 环境变量（自动尝试 fishing_almanac/.env 与 backend/.env）：
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *   视觉 API（与 species_image_head_focus_ai 一致）：优先 DOUBAO_API_KEY 或 ARK_API_KEY；未配置豆包时可任选其一 Gemini 密钥作回退
 *   SPECIES_ASSETS_ROOT 可选，默认为本脚本所在目录上两级（fishing_almanac 根目录，内含 assets/species）
 *   SPECIES_HEAD_FOCUS_DELAY_MS 每条请求后的间隔（毫秒），默认 4000（大批量时可调大）
 *   豆包与 Supabase 均可能间歇性 fetch 失败：脚本对「查库 + 调模型 + 写库」带有限次自动重试；仍失败多为链路抖动，可整体重跑或换更稳网络
 *
 * 用法（在 backend 目录）：
 *   npm run species:head-focus-local
 *   npm run species:head-focus-local -- --dry-run   # 只打印将处理谁，不写库、不调 AI
 *   npm run species:head-focus-local -- --limit=5
 *   npm run species:head-focus-local-retry       # 只处理 scripts/species-head-focus-retry.txt 列出的文件
 *   或: node scripts/fill-species-head-focus-from-assets-dir.cjs --retry-file=scripts/species-head-focus-retry.txt
 *   只跑指定文件（逗号分隔，须与 assets/species 下文件名一致；与 --retry-file 同时传时优先 --files）：
 *   node scripts/fill-species-head-focus-from-assets-dir.cjs --files=甲.jpg,乙.png
 */
const fs = require('fs');
const path = require('path');

function loadEnvFiles() {
  const { config } = require('dotenv');
  const paths = [
    path.join(__dirname, '..', '..', '.env'),
    path.join(__dirname, '..', '.env'),
  ];
  for (const p of paths) {
    if (fs.existsSync(p)) config({ path: p, override: true });
  }
}
loadEnvFiles();

function resolveDoubaoKey() {
  return (process.env.DOUBAO_API_KEY || process.env.ARK_API_KEY || '').trim();
}

function resolveGeminiKey() {
  return (
    (process.env.GEMINI_API_KEY || '').trim() ||
    (process.env.GOOGLE_AI_API_KEY || '').trim() ||
    (process.env.GOOGLE_GENERATIVE_AI_API_KEY || '').trim() ||
    (process.env.GOOGLE_API_KEY || '').trim()
  );
}

const { createClient } = require('@supabase/supabase-js');
const { analyzeSpeciesImageHeadFocus } = require('../species_image_head_focus_ai');

const IMG_EXT = /\.(jpe?g|png|webp)$/i;

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function formatRunErr(e) {
  const msg = (e && e.message) || String(e);
  const parts = [msg];
  let c = e && e.cause;
  let depth = 0;
  while (c != null && depth < 5) {
    const cm = typeof c.message === 'string' && c.message ? c.message : String(c);
    if (cm && !parts.includes(cm)) parts.push(cm);
    c = c.cause;
    depth += 1;
  }
  return parts.join(' → ');
}

function isTransientFetchFailure(e) {
  const s = formatRunErr(e).toLowerCase();
  return (
    s.includes('fetch failed') ||
    s.includes('econnreset') ||
    s.includes('etimedout') ||
    s.includes('socket hang up') ||
    s.includes('econnrefused') ||
    s.includes('und_err') ||
    s.includes('enotfound') ||
    s.includes('network') ||
    s.includes('aborted')
  );
}

/** Supabase 返回的 { message } 或抛出的 Error 统一成可判重的 Error */
function errFromSupabaseMessage(msg) {
  const e = new Error(String(msg || 'unknown'));
  e.phase = 'Supabase';
  return e;
}

/**
 * 按中文名查 species_catalog；对间歇性 fetch 失败自动重试（与豆包链路一样会抖）。
 */
async function selectSpeciesCatalogByZh(supabase, stem, fileLabel) {
  const max = 8;
  let last = { data: null, error: null };
  for (let i = 0; i < max; i++) {
    const { data: rows, error } = await supabase
      .from('species_catalog')
      .select('id, species_zh, image_url')
      .eq('species_zh', stem)
      .limit(3);
    if (!error) {
      return { data: rows, error: null };
    }
    last = { data: rows, error };
    const synthetic = errFromSupabaseMessage(error.message);
    if (i < max - 1 && isTransientFetchFailure(synthetic)) {
      const wait = 3500 + i * 1500;
      console.warn(
        `[DB 查询] ${fileLabel} 暂失败，${Math.round(wait / 1000)}s 后重试 (${i + 2}/${max}): ${error.message}`,
      );
      await sleep(wait);
      continue;
    }
    return { data: rows, error };
  }
  return last;
}

function parseArgs() {
  const dryRun = process.argv.includes('--dry-run');
  let limit = 0;
  let retryFile = '';
  let onlyFiles = '';
  for (const a of process.argv) {
    if (a.startsWith('--limit=')) {
      const n = Number(a.slice('--limit='.length));
      if (Number.isFinite(n) && n > 0) limit = Math.floor(n);
    }
    if (a.startsWith('--retry-file=')) {
      retryFile = a.slice('--retry-file='.length).trim().replace(/^["']|["']$/g, '');
    }
    if (a.startsWith('--files=')) {
      onlyFiles = a.slice('--files='.length).trim().replace(/^["']|["']$/g, '');
    }
  }
  return { dryRun, limit, retryFile, onlyFiles };
}

/** --files=a.jpg,b.png → 目录内存在的文件名集合 */
function resolveFilesArgSet(dir, csv) {
  const names = String(csv || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const dirFiles = new Set(fs.readdirSync(dir).filter((f) => IMG_EXT.test(f)));
  const wanted = new Set();
  for (const n of names) {
    const base = n.replace(/^assets\/species\//i, '').replace(/\\/g, '/').split('/').pop();
    if (dirFiles.has(base)) {
      wanted.add(base);
      continue;
    }
    console.warn(`[--files] 目录中无此文件: ${base}`);
  }
  return wanted;
}

/**
 * 从 retry 清单解析出「目录内实际存在的」文件名集合；行可为 `xxx.jpg` 或仅中文种名（自动匹配扩展名）。
 */
function resolveRetryFileSet(dir, retryFilePath) {
  const abs = path.isAbsolute(retryFilePath)
    ? retryFilePath
    : path.resolve(process.cwd(), retryFilePath);
  if (!fs.existsSync(abs)) {
    console.error(`找不到 --retry-file: ${abs}`);
    process.exit(1);
  }
  const lines = fs
    .readFileSync(abs, 'utf8')
    .split(/\r?\n/)
    .map((s) => s.trim())
    .filter((s) => s && !s.startsWith('#'));
  const dirFiles = new Set(fs.readdirSync(dir).filter((f) => IMG_EXT.test(f)));
  const wanted = new Set();
  for (const line of lines) {
    const base = line.replace(/^assets\/species\//i, '').replace(/\\/g, '/').split('/').pop();
    if (dirFiles.has(base)) {
      wanted.add(base);
      continue;
    }
    if (IMG_EXT.test(base)) {
      console.warn(`[retry-file] 目录中无此文件: ${base}`);
      continue;
    }
    const hit = [...dirFiles].find((f) => path.parse(f).name === line);
    if (hit) wanted.add(hit);
    else console.warn(`[retry-file] 目录中无与「${line}」匹配的图片`);
  }
  return wanted;
}

async function main() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const doubao = resolveDoubaoKey();
  const gemini = resolveGeminiKey();
  if (!supabaseUrl || !serviceKey) {
    console.error('缺少 SUPABASE_URL 或 SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
  }
  if (!doubao && !gemini) {
    const tried = [
      path.join(__dirname, '..', '..', '.env'),
      path.join(__dirname, '..', '.env'),
    ];
    const found = tried.filter((p) => fs.existsSync(p));
    console.error('未读到可用的视觉 API 密钥。请在 .env 中配置其一（不要带引号、不要多空格）：');
    console.error('  推荐 DOUBAO_API_KEY=...（或 ARK_API_KEY，与 server 物种识别一致）');
    console.error('  或回退 GEMINI_API_KEY / GOOGLE_AI_API_KEY 等');
    console.error('已尝试加载的文件:', found.length ? found.join(' → ') : '（上述路径均不存在 .env）');
    process.exit(1);
  }

  // __dirname = backend/scripts → 两级上级才是 fishing_almanac（与 assets/species 位置一致）
  const root = (process.env.SPECIES_ASSETS_ROOT || path.join(__dirname, '..', '..')).trim();
  const dir = path.join(root, 'assets', 'species');
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    console.error(`找不到物种图目录: ${dir}`);
    console.error('若工程不在默认位置，请设置 SPECIES_ASSETS_ROOT 为 fishing_almanac 根目录（含 assets/species）');
    process.exit(1);
  }

  const { dryRun, limit, retryFile, onlyFiles } = parseArgs();
  const delayRaw = process.env.SPECIES_HEAD_FOCUS_DELAY_MS;
  const delayParsed = delayRaw != null && String(delayRaw).trim() !== '' ? Number(delayRaw) : NaN;
  const delayMs =
    Number.isFinite(delayParsed) && delayParsed >= 0 ? Math.floor(delayParsed) : 4000;
  const files = fs
    .readdirSync(dir)
    .filter((f) => IMG_EXT.test(f) && fs.statSync(path.join(dir, f)).isFile())
    .sort();

  let todoFiles = files;
  let subsetTag = '';
  if (onlyFiles) {
    if (retryFile) {
      console.warn('同时传了 --retry-file 与 --files，本次仅按 --files 处理，忽略 --retry-file。');
    }
    const only = resolveFilesArgSet(dir, onlyFiles);
    if (!only.size) {
      console.error('[--files] 未匹配到任何目录内图片，请检查逗号分隔的文件名是否与 assets/species 下完全一致。');
      process.exit(1);
    }
    todoFiles = files.filter((f) => only.has(f));
    subsetTag = '（--files 子集）';
    console.log(`--files: 指定 ${only.size} 个文件名 → 目录内待处理 ${todoFiles.length} 个`);
  } else if (retryFile) {
    const only = resolveRetryFileSet(dir, retryFile);
    todoFiles = files.filter((f) => only.has(f));
    subsetTag = '（retry 子集）';
    console.log(`--retry-file: ${retryFile} → 目录内待处理 ${todoFiles.length} 个（清单中共 ${only.size} 个有效文件名）`);
  }
  if (limit > 0) {
    todoFiles = todoFiles.slice(0, limit);
  }

  console.log(`物种图目录: ${dir}`);
  console.log(
    `共 ${files.length} 个图片文件，将处理 ${todoFiles.length} 个${dryRun ? '（dry-run）' : ''}${subsetTag}；条间间隔 ${delayMs}ms（SPECIES_HEAD_FOCUS_DELAY_MS）`,
  );

  const supabase = createClient(supabaseUrl, serviceKey);
  let ok = 0;
  let skip = 0;
  let fail = 0;

  for (const file of todoFiles) {
    const stem = path.parse(file).name;
    const relUrl = `assets/species/${file}`.replace(/\\/g, '/');

    const { data: rows, error } = await selectSpeciesCatalogByZh(supabase, stem, file);

    if (error) {
      console.error(`[DB] ${file}: ${formatRunErr(errFromSupabaseMessage(error.message))}`);
      fail += 1;
      continue;
    }
    if (!rows || rows.length === 0) {
      console.log(`跳过（无 species_zh 匹配）: ${file} → 期望中文名「${stem}」`);
      skip += 1;
      continue;
    }
    if (rows.length > 1) {
      console.warn(`警告（多条同名）只更新第一条: ${stem} id=${rows.map((r) => r.id).join(',')}`);
    }
    const id = rows[0].id;

    if (dryRun) {
      console.log(`[dry-run] #${id} ${stem} ← ${file}`);
      ok += 1;
      continue;
    }

    const aiMax = 8;
    process.stdout.write(`#${id} ${stem} (${file}) … `);
    let done = false;
    for (let t = 0; t < aiMax && !done; t++) {
      try {
        const { nx, ny, engine } = await analyzeSpeciesImageHeadFocus(relUrl);
        const { error: upErr } = await supabase
          .from('species_catalog')
          .update({ image_head_nx: nx, image_head_ny: ny })
          .eq('id', id);
        if (upErr) {
          const err = errFromSupabaseMessage(upErr.message || String(upErr));
          throw err;
        }
        console.log(`OK (${engine}) (${nx.toFixed(3)},${ny.toFixed(3)})`);
        ok += 1;
        done = true;
      } catch (e) {
        const transient = t < aiMax - 1 && isTransientFetchFailure(e);
        if (transient) {
          const wait = 4500 + t * 1500;
          console.log(
            `\n  网络波动${e && e.phase ? `（${e.phase}）` : ''}，${Math.round(wait / 1000)}s 后重试 (${t + 2}/${aiMax})…`,
          );
          await sleep(wait);
          process.stdout.write(`#${id} ${stem} (${file}) … `);
          continue;
        }
        const phase = e && e.phase ? `[${e.phase}] ` : '';
        console.log(`FAIL: ${phase}${formatRunErr(e)}`);
        fail += 1;
        done = true;
      }
    }
    await sleep(delayMs);
  }

  console.log(`完成: 成功/模拟 ${ok}, 跳过 ${skip}, 失败 ${fail}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
