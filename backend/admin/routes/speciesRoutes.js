function registerAdminSpeciesRoutes({
  app,
  supabaseAdmin,
  upload,
  jsonError,
  requireAdmin,
  logSpeciesAdminAction,
  toFiniteNumberOr,
  uploadSpeciesImage,
}) {
  app.get('/v1/admin/species', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    try {
      const statusFilter = String(req.query.status || 'all');
      let query = supabaseAdmin
        .from('species_catalog')
        .select('id, species_zh, scientific_name, taxonomy_zh, is_rare, image_url, max_length_m, max_weight_kg, description_zh, name_en, encyclopedia_category, rarity_display, alias_zh, source, status, contributed_by, contributed_image_url, merged_into_species_id, merged_at, merge_note, created_at')
        .order('id', { ascending: true });
      if (statusFilter !== 'all') query = query.eq('status', statusFilter);
      const { data, error } = await query;
      if (error) return jsonError(res, 500, '读取物种列表失败', String(error.message || error));
      return res.json({ species: data || [], total: (data || []).length });
    } catch (e) {
      return jsonError(res, 500, '读取物种列表失败', String(e?.message || e));
    }
  });

  app.post('/v1/admin/species', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const body = req.body || {};
    const speciesZh = String(body.species_zh || '').trim();
    const scientificName = String(body.scientific_name || '').trim();
    if (!speciesZh) return jsonError(res, 400, 'species_zh 不能为空');
    if (!scientificName) return jsonError(res, 400, 'scientific_name 不能为空');

    const payload = {
      species_zh: speciesZh,
      scientific_name: scientificName,
      taxonomy_zh: String(body.taxonomy_zh || '').trim(),
      is_rare: body.is_rare === true,
      image_url: String(body.image_url || '').trim() || 'assets/species/placeholder.jpg',
      max_length_m: toFiniteNumberOr(body.max_length_m, 0),
      max_weight_kg: toFiniteNumberOr(body.max_weight_kg, 0),
      description_zh: String(body.description_zh || '').trim(),
      name_en: String(body.name_en || '').trim() || null,
      encyclopedia_category: String(body.encyclopedia_category || '').trim() || null,
      rarity_display: String(body.rarity_display || '').trim() || null,
      alias_zh: String(body.alias_zh || '').trim() || null,
      source: String(body.source || 'official').trim() || 'official',
      status: String(body.status || 'approved').trim() || 'approved',
      contributed_by: body.contributed_by || null,
      contributed_image_url: String(body.contributed_image_url || '').trim() || null,
    };

    try {
      const { data: inserted, error } = await supabaseAdmin
        .from('species_catalog')
        .insert(payload)
        .select('*')
        .single();
      if (error) return jsonError(res, 500, '新增物种失败', String(error.message || error));
      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'create_species',
        speciesId: inserted.id,
        speciesScientificName: inserted.scientific_name,
        afterData: inserted,
      });
      return res.json({ species: inserted });
    } catch (e) {
      return jsonError(res, 500, '新增物种失败', String(e?.message || e));
    }
  });

  app.get('/v1/admin/species/:id', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) return jsonError(res, 400, '无效物种ID');
    try {
      const { data: species, error } = await supabaseAdmin
        .from('species_catalog')
        .select('*')
        .eq('id', id)
        .maybeSingle();
      if (error) return jsonError(res, 500, '读取物种失败', String(error.message || error));
      if (!species) return jsonError(res, 404, '物种不存在');

      const [{ data: aliases }, { data: synonyms }] = await Promise.all([
        supabaseAdmin.from('species_aliases').select('*').eq('species_id', id).order('alias_zh', { ascending: true }),
        supabaseAdmin
          .from('species_synonyms')
          .select('*')
          .eq('canonical_scientific_name', species.scientific_name)
          .order('synonym', { ascending: true }),
      ]);

      return res.json({
        species: {
          ...species,
          aliases: aliases || [],
          synonyms: synonyms || [],
        },
      });
    } catch (e) {
      return jsonError(res, 500, '读取物种失败', String(e?.message || e));
    }
  });

  app.patch('/v1/admin/species/:id', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) return jsonError(res, 400, '无效物种ID');
    const body = req.body || {};
    const allowed = [
      'species_zh',
      'scientific_name',
      'taxonomy_zh',
      'is_rare',
      'image_url',
      'max_length_m',
      'max_weight_kg',
      'description_zh',
      'name_en',
      'encyclopedia_category',
      'rarity_display',
      'alias_zh',
      'source',
      'status',
    ];
    const patch = {};
    for (const k of allowed) {
      if (Object.prototype.hasOwnProperty.call(body, k)) patch[k] = body[k];
    }
    if (Object.keys(patch).length === 0) return jsonError(res, 400, '没有可更新字段');

    try {
      const { data: before, error: beforeErr } = await supabaseAdmin
        .from('species_catalog')
        .select('*')
        .eq('id', id)
        .maybeSingle();
      if (beforeErr) return jsonError(res, 500, '读取物种失败', String(beforeErr.message || beforeErr));
      if (!before) return jsonError(res, 404, '物种不存在');

      const { data: updated, error: upErr } = await supabaseAdmin
        .from('species_catalog')
        .update(patch)
        .eq('id', id)
        .select('*')
        .single();
      if (upErr) return jsonError(res, 500, '更新物种失败', String(upErr.message || upErr));

      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'update_species',
        speciesId: id,
        speciesScientificName: updated.scientific_name,
        beforeData: before,
        afterData: updated,
      });

      return res.json({ species: updated });
    } catch (e) {
      return jsonError(res, 500, '更新物种失败', String(e?.message || e));
    }
  });

  app.post('/v1/admin/species/:id/image', upload.single('image'), async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) return jsonError(res, 400, '无效物种ID');
    if (!req.file || !req.file.buffer) return jsonError(res, 400, '请上传图片');

    try {
      const { data: before, error: beforeErr } = await supabaseAdmin
        .from('species_catalog')
        .select('*')
        .eq('id', id)
        .maybeSingle();
      if (beforeErr) return jsonError(res, 500, '读取物种失败', String(beforeErr.message || beforeErr));
      if (!before) return jsonError(res, 404, '物种不存在');

      const imageUrl = await uploadSpeciesImage(req.file.buffer, before.scientific_name);
      const { data: updated, error: upErr } = await supabaseAdmin
        .from('species_catalog')
        .update({ image_url: imageUrl })
        .eq('id', id)
        .select('*')
        .single();
      if (upErr) return jsonError(res, 500, '更新物种图片失败', String(upErr.message || upErr));

      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'replace_species_image',
        speciesId: id,
        speciesScientificName: updated.scientific_name,
        beforeData: { image_url: before.image_url },
        afterData: { image_url: updated.image_url },
      });

      return res.json({ species: updated });
    } catch (e) {
      return jsonError(res, 500, '更新物种图片失败', String(e?.message || e));
    }
  });

  app.post('/v1/admin/species/:id/aliases', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) return jsonError(res, 400, '无效物种ID');
    const aliasZh = String(req.body?.alias_zh || '').trim();
    const region = String(req.body?.region || '').trim();
    if (!aliasZh) return jsonError(res, 400, 'alias_zh 不能为空');

    try {
      const { data: species } = await supabaseAdmin
        .from('species_catalog')
        .select('id, scientific_name')
        .eq('id', id)
        .maybeSingle();
      if (!species) return jsonError(res, 404, '物种不存在');

      const { data: inserted, error } = await supabaseAdmin
        .from('species_aliases')
        .upsert({ species_id: id, alias_zh: aliasZh, region: region || null }, { onConflict: 'alias_zh,species_id' })
        .select('*')
        .single();
      if (error) return jsonError(res, 500, '添加俗名失败', String(error.message || error));

      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'add_species_alias',
        speciesId: id,
        speciesScientificName: species.scientific_name,
        afterData: inserted,
      });

      return res.json({ alias: inserted });
    } catch (e) {
      return jsonError(res, 500, '添加俗名失败', String(e?.message || e));
    }
  });

  app.post('/v1/admin/species/:id/aliases/replace', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) return jsonError(res, 400, '无效物种ID');
    const aliasesRaw = req.body?.aliases;
    const aliases = Array.isArray(aliasesRaw)
      ? aliasesRaw.map((e) => String(e || '').trim()).filter((e) => e.length > 0)
      : [];
    try {
      const { data: species, error: speciesErr } = await supabaseAdmin
        .from('species_catalog')
        .select('id, scientific_name')
        .eq('id', id)
        .maybeSingle();
      if (speciesErr) return jsonError(res, 500, '读取物种失败', String(speciesErr.message || speciesErr));
      if (!species) return jsonError(res, 404, '物种不存在');

      const { data: result, error } = await supabaseAdmin.rpc('admin_replace_species_aliases', {
        p_species_id: id,
        p_aliases: aliases,
      });
      if (error) return jsonError(res, 500, '替换俗名失败', String(error.message || error));

      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'replace_species_aliases',
        speciesId: id,
        speciesScientificName: species.scientific_name,
        metadata: { aliases, result },
      });
      return res.json({ ok: true, result: result || null });
    } catch (e) {
      return jsonError(res, 500, '替换俗名失败', String(e?.message || e));
    }
  });

  app.patch('/v1/admin/species/:id/aliases/:aliasId', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const id = Number(req.params.id);
    const aliasId = Number(req.params.aliasId);
    if (!Number.isFinite(id) || !Number.isFinite(aliasId)) return jsonError(res, 400, '无效ID');
    const aliasZh = String(req.body?.alias_zh || '').trim();
    const region = String(req.body?.region || '').trim();
    if (!aliasZh) return jsonError(res, 400, 'alias_zh 不能为空');
    try {
      const { data: updated, error } = await supabaseAdmin
        .from('species_aliases')
        .update({ alias_zh: aliasZh, region: region || null })
        .eq('id', aliasId)
        .eq('species_id', id)
        .select('*')
        .maybeSingle();
      if (error) return jsonError(res, 500, '更新俗名失败', String(error.message || error));
      if (!updated) return jsonError(res, 404, '俗名不存在');
      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'update_species_alias',
        speciesId: id,
        afterData: updated,
      });
      return res.json({ alias: updated });
    } catch (e) {
      return jsonError(res, 500, '更新俗名失败', String(e?.message || e));
    }
  });

  app.delete('/v1/admin/species/:id/aliases/:aliasId', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const id = Number(req.params.id);
    const aliasId = Number(req.params.aliasId);
    if (!Number.isFinite(id) || !Number.isFinite(aliasId)) return jsonError(res, 400, '无效ID');
    try {
      const { data: before } = await supabaseAdmin
        .from('species_aliases')
        .select('*')
        .eq('id', aliasId)
        .eq('species_id', id)
        .maybeSingle();
      if (!before) return jsonError(res, 404, '俗名不存在');
      const { error } = await supabaseAdmin.from('species_aliases').delete().eq('id', aliasId).eq('species_id', id);
      if (error) return jsonError(res, 500, '删除俗名失败', String(error.message || error));
      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'delete_species_alias',
        speciesId: id,
        beforeData: before,
      });
      return res.json({ ok: true });
    } catch (e) {
      return jsonError(res, 500, '删除俗名失败', String(e?.message || e));
    }
  });
}

module.exports = {
  registerAdminSpeciesRoutes,
};

