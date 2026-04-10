/**
 * Applies analytics-related SQL migrations to the remote Postgres database.
 *
 * 默认按顺序执行：
 * - 0002_analytics_events.sql
 * - 0012_analytics_event_flat_view.sql
 * - 0013_analytics_daily_kpi_view.sql
 * - 0014_analytics_topic_views_and_checks.sql
 * - 0015_analytics_overview_daily_and_uv_fn.sql
 * - 0016_analytics_window_summary_rpc.sql
 *
 * 也支持传参只执行单个 migration：
 *   npm run migrate:analytics -- 0012_analytics_event_flat_view.sql
 *
 * Requires one of:
 *   - DATABASE_URL
 *   - SUPABASE_DB_PASSWORD + SUPABASE_URL
 */
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

function buildDatabaseUrlFromSupabaseEnv() {
  const direct = process.env.DATABASE_URL;
  if (direct && String(direct).trim()) return String(direct).trim();

  const pw = process.env.SUPABASE_DB_PASSWORD;
  const supabaseUrl = process.env.SUPABASE_URL;
  if (!pw || !supabaseUrl) return null;

  const m = String(supabaseUrl).match(/https:\/\/([^.]+)\.supabase\.co/i);
  if (!m) return null;
  const ref = m[1];
  const encoded = encodeURIComponent(String(pw));
  return `postgresql://postgres:${encoded}@db.${ref}.supabase.co:5432/postgres`;
}

async function main() {
  const databaseUrl = buildDatabaseUrlFromSupabaseEnv();
  if (!databaseUrl) {
    console.error(
      [
        'Missing database credentials.',
        'Set DATABASE_URL in backend/.env, or set SUPABASE_DB_PASSWORD (and keep SUPABASE_URL).',
        'Password: Supabase Dashboard → Project Settings → Database → Database password.',
      ].join('\n')
    );
    process.exit(1);
  }

  // 中文注释：优先执行 analytics 相关 migration，确保第一步视图可直接落地。
  const defaultMigrations = [
    '0002_analytics_events.sql',
    '0012_analytics_event_flat_view.sql',
    '0013_analytics_daily_kpi_view.sql',
    '0014_analytics_topic_views_and_checks.sql',
    '0015_analytics_overview_daily_and_uv_fn.sql',
    '0016_analytics_window_summary_rpc.sql',
  ];
  const specifiedMigration = process.argv[2];
  const migrationFiles = specifiedMigration ? [specifiedMigration] : defaultMigrations;

  const client = new Client({ connectionString: databaseUrl, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    for (const file of migrationFiles) {
      const sqlPath = path.join(__dirname, '..', '..', 'supabase', 'migrations', file);
      if (!fs.existsSync(sqlPath)) {
        console.error('Migration file not found:', sqlPath);
        process.exit(1);
      }
      const sql = fs.readFileSync(sqlPath, 'utf8');
      await client.query(sql);
      console.log(`OK: ${file} applied.`);
    }
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
