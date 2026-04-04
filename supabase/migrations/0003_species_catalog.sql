-- 图鉴物种库（与 App 内 `SpeciesCatalog` mock 字段对齐；执行 `supabase db push` 或 SQL 编辑器运行）。
-- 位置：本仓库 `fishing_almanac/supabase/migrations/`。

create table if not exists public.species_catalog (
  id smallserial primary key,
  species_zh text not null unique,
  scientific_name text not null,
  taxonomy_zh text not null default '',
  is_rare boolean not null default false,
  image_url text not null,
  max_length_m numeric not null,
  max_weight_kg numeric not null,
  description_zh text not null,
  name_en text,
  encyclopedia_category text,
  rarity_display text,
  created_at timestamptz not null default now()
);

comment on table public.species_catalog is '物种编号/中文名/学名/分类/稀有种/配图/最大尺寸/描述等；catches.species_zh 经外键强绑定本表（见 0004）。';

create index if not exists species_catalog_zh_idx on public.species_catalog (species_zh);

alter table public.species_catalog enable row level security;

create policy "species_catalog_select_all"
  on public.species_catalog for select
  using (true);

insert into public.species_catalog (
  id, species_zh, scientific_name, taxonomy_zh, is_rare, image_url,
  max_length_m, max_weight_kg, description_zh, name_en, encyclopedia_category, rarity_display
) values
  (1, '蓝鳍金枪鱼', 'Thunnus thynnus', '硬骨鱼纲 · 鲈形目 · 鲭科', true,
   'https://lh3.googleusercontent.com/aida-public/AB6AXuDUUhNpUHCjj1aSmC8lmt-mr5XKR0iEo-FDabChHlRaF7mSO1u2qQqZ-3L3aIgX5_5L84LolksWSXcXFw3p0Q64CWLUD4pSuFyYs4Eosjt3bAkpHMjOTxWPPi8q3TG5K-zNP8LtuIBOaY6gXBqqbe_UwpO3wbnEIS0EkMXIA8-T7HoNCk4mMeiHRo6Yb8UAX_qlDDaYuP6hLM9Da51N6UPg96KMMefSlEj5xKzDlIsI74KtD9RK_eA281Ql9xdvqZ1DRyUbNTHO7A',
   3.0, 680,
   '蓝鳍金枪鱼是海洋中最强大的掠食者之一，以其惊人的速度和远洋迁徙能力而闻名。它们拥有流线型的银蓝色身体，能够在深海寒冷的水域中保持体温，这使其成为真正的深海王者。',
   'Bluefin Tuna', 'deep', 'SSR'),
  (2, '鲯鳅', 'Coryphaena hippurus', '硬骨鱼纲 · 鲈形目 · 鲯鳅科', false,
   'https://lh3.googleusercontent.com/aida-public/AB6AXuAurWNajs7A3t_AKXOoQpLMWbUjM1u6Uk0ryMSIAN0lMR44ixgyR1g4mNxImR66quq3En7mQTOF616OnsUuc4KlvqNXr4pUSjf8G2zv1LlERuNDe4VMthoU7rCLDrw_MnmIhxK0Rd7bUne0wCqLC6syTeVt7GVzbCduAkq6zD7xhOTiiaq5rDumj8nGpwXx5dtRBpjthjr3W5PAOkctXoFSBu3mRUCGRGgnAnF4FFpvCruxK3NpZUKlIvBJifQBMj9J1gUAdIKjaA',
   2.1, 40,
   '鲯鳅色彩艳丽，常见于热带、亚热带外海，游速快，是路亚与拖钓的热门对象鱼。',
   'Mahi Mahi', 'nearshore', null),
  (3, '红鲷鱼', 'Lutjanus campechanus', '硬骨鱼纲 · 鲈形目 · 笛鲷科', false,
   'https://lh3.googleusercontent.com/aida-public/AB6AXuDWcuqHOW0t0wvzvzbcDK85mLhM1nArA1z2XYdCRxVBu1ZkYqcCxJHrz9zSZSom5r3zEtyQQmmZyWaEb15qHff_RgRXbCJjtTOeIghPUvFC6okhPRo_awBsZcD7hcHVicf_VYAheaTnkmrsJwXD5EMonJFRDYULUQzW8DI3Kuv5Jlk9wfY6-r599bQ42sExMxoEylBG-inX2AFEFttot6pgIYR2ulUx2cJSvl7XVWkCj5eBOm8At4_i0O0FImjn3H_J6mzOgZNqbA',
   0.9, 22,
   '红鲷鱼分布广泛，肉质鲜美，常栖息于岩礁与沙泥底环境，是近海休闲钓的常见目标。',
   'Red Snapper', 'nearshore', null),
  (4, '石斑鱼', 'Epinephelus spp.', '硬骨鱼纲 · 鲈形目 · 鮨科', false,
   'https://lh3.googleusercontent.com/aida-public/AB6AXuCrKCKkEFYZps_FBnY7el-lo6Et0Nrp-9jjnnjNq7Wv-yoTjlnnJMpHqgvWBCMdte7RUuX9xvVPuNYhk4vXR2X4KcLS5rWKW8QnW0Aq6QihuYu5q67K-4OwCxkxloMIBD4jUotzqSjt5zjTTJyMS3pK7B-mzbKgs0mEa_xWhnSb_FoQRxe39f9AlYSn613sbRJ8IO8WNFpnLJVtNUmRTv5X_u5jzFrlK_BqLVtkmOsjcqwH2OreDmm8QRQEUBSlvKUqQMai28zEoQ',
   2.0, 150,
   '石斑鱼种类众多，多栖息于珊瑚礁与岩礁区，体型结实，是深海与矶钓中极具挑战的鱼种。',
   'Grouper', 'deep', null),
  (5, '条纹鲈', 'Morone saxatilis', '硬骨鱼纲 · 鲈形目 · 狼鲈科', true,
   'https://lh3.googleusercontent.com/aida-public/AB6AXuBw7_ycnbiI1GlnxVamFIs24zkE63z7wq1U5N7ef3mIa6ABw_v2ZUqLyI4RwOAj-dmMO7g3zoE4F1IdKX5G9nKQ3RzfFQK9wDG_w0XgvYgHzNLsiXgNotEGaOadJ4GwufA_qEdWfnBczKAQKp3i-LbWI636NlKklOZahIMWNclIbKo7qD0vYE2NBe8X-OfRsDrhZZGgdosZzNXSs7iGmMENoNFM0tsQGMc6C3Zhhma3A3wJNxB6rUX0Cg4AkQxASjW49W2Xphnzkw',
   1.2, 35,
   '条纹鲈适应力强，多见于河口与近岸，掠食积极，是北美东岸极具代表性的游钓鱼种之一。',
   'Striped Bass', 'rare', 'SSR')
on conflict (species_zh) do update set
  scientific_name = excluded.scientific_name,
  taxonomy_zh = excluded.taxonomy_zh,
  is_rare = excluded.is_rare,
  image_url = excluded.image_url,
  max_length_m = excluded.max_length_m,
  max_weight_kg = excluded.max_weight_kg,
  description_zh = excluded.description_zh,
  name_en = excluded.name_en,
  encyclopedia_category = excluded.encyclopedia_category,
  rarity_display = excluded.rarity_display;

select setval(
  pg_get_serial_sequence('public.species_catalog', 'id'),
  (select coalesce(max(id), 1) from public.species_catalog)
);
