/**
 * Applies supabase/migrations/0002_analytics_events.sql to the remote Postgres database.
 *
 * Requires one of:
 *   - DATABASE_URL (Supabase Dashboard → Settings → Database → Connection string → URI)
 *   - SUPABASE_DB_PASSWORD (database user password) + SUPABASE_URL (same as backend .env)
 *
 * Usage: npm run migrate:analytics
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

  const sqlPath = path.join(__dirname, '..', '..', 'supabase', 'migrations', '0002_analytics_events.sql');
  if (!fs.existsSync(sqlPath)) {
    console.error('Migration file not found:', sqlPath);
    process.exit(1);
  }
  const sql = fs.readFileSync(sqlPath, 'utf8');

  const client = new Client({ connectionString: databaseUrl, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    await client.query(sql);
    console.log('OK: analytics_events migration applied.');
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
