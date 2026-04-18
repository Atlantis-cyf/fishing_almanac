/**
 * 批量为 species_catalog 写入 image_head_nx / image_head_ny（AI 估算鱼头中心）。
 *
 * - image_url 为 https（如 Supabase Storage）：从网络或 Storage API 取图。
 * - image_url 为 `assets/species/xxx.jpg`：从本机 Flutter 工程读图（默认根目录为 backend 上一级，即 fishing_almanac）；
 *   若你的工程不在默认相对位置，可设置环境变量 SPECIES_ASSETS_ROOT=绝对路径\fishing_almanac。
 * - 本地 assets 路径：先读图再调视觉 API；优先豆包（DOUBAO_API_KEY / ARK_API_KEY），未配置时可用 Gemini。
 *
 * 依赖 .env：SUPABASE_URL、SUPABASE_SERVICE_ROLE_KEY，以及 DOUBAO_API_KEY（推荐）或 GEMINI_API_KEY 等。
 *
 * 用法（在 backend 目录）：
 *   npm run species:head-focus
 *   npm run species:head-focus -- --force   # 已写过坐标的也重算
 *   npm run species:head-focus -- --limit=20
 */
const fs = require('fs');
const path = require('path');
{
  const { config } = require('dotenv');
  for (const p of [path.join(__dirname, '..', '..', '.env'), path.join(__dirname, '..', '.env')]) {
    if (fs.existsSync(p)) config({ path: p, override: true });
  }
}

const { createClient } = require('@supabase/supabase-js');
const { analyzeSpeciesImageHeadFocus } = require('../species_image_head_focus_ai');

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function parseArgs() {
  const force = process.argv.includes('--force');
  let limit = 0;
  for (const a of process.argv) {
    if (a.startsWith('--limit=')) {
      const n = Number(a.slice('--limit='.length));
      if (Number.isFinite(n) && n > 0) limit = Math.floor(n);
    }
  }
  return { force, limit };
}

async function main() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error('缺少 SUPABASE_URL 或 SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
  }

  const { force, limit } = parseArgs();
  const supabase = createClient(url, key);

  let q = supabase
    .from('species_catalog')
    .select('id, image_url, image_head_nx, image_head_ny')
    .order('id', { ascending: true });

  if (!force) {
    q = q.is('image_head_nx', null);
  }

  const { data: rows, error } = await q;
  if (error) {
    console.error('查询失败:', error.message);
    process.exit(1);
  }

  const list = (rows || []).filter((r) => {
    const u = String(r.image_url || '').trim();
    if (!u || u.includes('placeholder')) return false;
    return (
      u.startsWith('http://') ||
      u.startsWith('https://') ||
      u.startsWith('assets/species/')
    );
  });

  const todo = limit > 0 ? list.slice(0, limit) : list;
  console.log(`待处理 ${todo.length} 条（共 ${list.length} 条可分析：公网 URL 或 assets/species/）`);

  let ok = 0;
  let fail = 0;
  for (const row of todo) {
    const id = row.id;
    const imageUrl = String(row.image_url).trim();
    process.stdout.write(`#${id} ${imageUrl.slice(0, 60)}... `);
    try {
      const { nx, ny, engine } = await analyzeSpeciesImageHeadFocus(imageUrl);
      const { error: upErr } = await supabase
        .from('species_catalog')
        .update({ image_head_nx: nx, image_head_ny: ny })
        .eq('id', id);
      if (upErr) throw new Error(upErr.message);
      console.log(`OK (${engine}) head=(${nx.toFixed(3)},${ny.toFixed(3)})`);
      ok += 1;
    } catch (e) {
      const extra = e && e.cause ? ` (${e.cause})` : '';
      console.log(`FAIL: ${e.message || e}${extra}`);
      fail += 1;
    }
    await sleep(650);
  }

  console.log(`完成: 成功 ${ok}, 失败 ${fail}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
