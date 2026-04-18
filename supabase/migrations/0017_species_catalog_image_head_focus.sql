-- 物种图鉴卡片：鱼头在图中的归一化中心 (0~1)，供 Flutter BoxFit.cover + alignment 裁切时优先露出鱼头。
ALTER TABLE public.species_catalog
  ADD COLUMN IF NOT EXISTS image_head_nx double precision,
  ADD COLUMN IF NOT EXISTS image_head_ny double precision;

COMMENT ON COLUMN public.species_catalog.image_head_nx IS '鱼头中心相对横坐标 0=left 1=right';
COMMENT ON COLUMN public.species_catalog.image_head_ny IS '鱼头中心相对纵坐标 0=top 1=bottom';
