#!/usr/bin/env node
/**
 * One-time migration: read catches with image_base64 but no image_url,
 * upload to Supabase Storage, and update image_url.
 *
 * Run from backend/:  node scripts/migrate-images-to-storage.cjs
 */
require('dotenv').config({ path: require('path').resolve(__dirname, '..', '.env') });

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET = process.env.CATCH_IMAGE_BUCKET || 'catch-images';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

async function ensureBucket() {
  const { error } = await supabase.storage.createBucket(BUCKET, {
    public: true,
    fileSizeLimit: 5 * 1024 * 1024,
    allowedMimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
  });
  if (error && !String(error.message || '').includes('already exists')) {
    console.error('createBucket error:', error.message);
    process.exit(1);
  }
  console.log(`Bucket "${BUCKET}" ready.`);
}

async function main() {
  await ensureBucket();

  const { data: rows, error } = await supabase
    .from('catches')
    .select('id, user_id, image_base64')
    .is('image_url', null)
    .not('image_base64', 'is', null)
    .limit(500);

  if (error) {
    console.error('Query error:', error.message);
    process.exit(1);
  }

  console.log(`Found ${rows.length} records to migrate.`);
  if (rows.length === 0) return;

  let ok = 0;
  let fail = 0;

  for (const row of rows) {
    const path = `catches/${row.user_id}/${row.id}.jpg`;
    try {
      const buf = Buffer.from(row.image_base64, 'base64');
      const { error: upErr } = await supabase.storage
        .from(BUCKET)
        .upload(path, buf, { contentType: 'image/jpeg', upsert: true });
      if (upErr) throw new Error(upErr.message);

      const { data: urlData } = supabase.storage.from(BUCKET).getPublicUrl(path);
      const publicUrl = urlData?.publicUrl;
      if (!publicUrl) throw new Error('getPublicUrl returned null');

      const { error: updErr } = await supabase
        .from('catches')
        .update({ image_url: publicUrl })
        .eq('id', row.id);
      if (updErr) throw new Error(updErr.message);

      ok++;
      console.log(`  ✓ ${row.id} → ${publicUrl}`);
    } catch (e) {
      fail++;
      console.error(`  ✗ ${row.id}: ${e.message}`);
    }
  }

  console.log(`\nDone. migrated=${ok}, failed=${fail}, total=${rows.length}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
