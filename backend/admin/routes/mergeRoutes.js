function registerAdminMergeRoutes({
  app,
  supabaseAdmin,
  jsonError,
  requireAdmin,
  logSpeciesAdminAction,
  createSpeciesSnapshot,
  normKey,
}) {
  app.post('/v1/admin/species/merge/preview', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const targetId = Number(req.body?.target_species_id);
    const sourceId = Number(req.body?.source_species_id);
    if (!Number.isFinite(targetId) || !Number.isFinite(sourceId)) {
      return jsonError(res, 400, 'target_species_id / source_species_id 无效');
    }
    if (targetId === sourceId) return jsonError(res, 400, 'A 与 B 不能相同');

    try {
      const { data: speciesRows, error: speciesErr } = await supabaseAdmin
        .from('species_catalog')
        .select('id, species_zh, scientific_name, status, merged_into_species_id')
        .in('id', [targetId, sourceId]);
      if (speciesErr) return jsonError(res, 500, '读取物种失败', String(speciesErr.message || speciesErr));
      const target = (speciesRows || []).find((s) => s.id === targetId);
      const source = (speciesRows || []).find((s) => s.id === sourceId);
      if (!target) return jsonError(res, 404, '主物种 A 不存在');
      if (!source) return jsonError(res, 404, '被合并物种 B 不存在');
      if (target.merged_into_species_id) return jsonError(res, 409, 'A 已被合并，请选择未被合并的主物种');
      if (source.merged_into_species_id) return jsonError(res, 409, 'B 已被合并，请刷新后重试');
      if (source.scientific_name === 'Other' || target.scientific_name === 'Other') {
        return jsonError(res, 400, '“其它”系统物种不允许参与合并');
      }

      const [catchRes, srcAliasRes, tgtAliasRes, srcSynRes, tgtSynRes] = await Promise.all([
        supabaseAdmin
          .from('catches')
          .select('id', { count: 'exact', head: true })
          .eq('scientific_name', source.scientific_name),
        supabaseAdmin
          .from('species_aliases')
          .select('id, alias_zh')
          .eq('species_id', sourceId),
        supabaseAdmin
          .from('species_aliases')
          .select('id, alias_zh')
          .eq('species_id', targetId),
        supabaseAdmin
          .from('species_synonyms')
          .select('id, synonym')
          .eq('canonical_scientific_name', source.scientific_name),
        supabaseAdmin
          .from('species_synonyms')
          .select('id, synonym')
          .eq('canonical_scientific_name', target.scientific_name),
      ]);

      if (catchRes.error) return jsonError(res, 500, '统计关联鱼获失败', String(catchRes.error.message || catchRes.error));
      if (srcAliasRes.error || tgtAliasRes.error) {
        const e = srcAliasRes.error || tgtAliasRes.error;
        return jsonError(res, 500, '统计俗名失败', String(e.message || e));
      }
      if (srcSynRes.error || tgtSynRes.error) {
        const e = srcSynRes.error || tgtSynRes.error;
        return jsonError(res, 500, '统计异名失败', String(e.message || e));
      }

      const targetAliasSet = new Set((tgtAliasRes.data || []).map((a) => normKey(a.alias_zh)));
      const targetSynSet = new Set((tgtSynRes.data || []).map((s) => normKey(s.synonym)));
      const sourceAliasRows = srcAliasRes.data || [];
      const sourceSynRows = srcSynRes.data || [];
      const aliasesToMove = sourceAliasRows.filter((a) => !targetAliasSet.has(normKey(a.alias_zh))).length;
      const synonymsToMove = sourceSynRows.filter((s) => !targetSynSet.has(normKey(s.synonym))).length;
      const sourceScientificWillBecomeSynonym =
        normKey(source.scientific_name) !== normKey(target.scientific_name) &&
        !targetSynSet.has(normKey(source.scientific_name));

      return res.json({
        preview: {
          merge_direction: 'B_into_A',
          target_species: target,
          source_species: source,
          impact: {
            catches_relink_count: catchRes.count || 0,
            aliases_source_count: sourceAliasRows.length,
            aliases_to_move_count: aliasesToMove,
            synonyms_source_count: sourceSynRows.length,
            synonyms_to_move_count: synonymsToMove,
            source_scientific_will_become_synonym: sourceScientificWillBecomeSynonym,
          },
        },
      });
    } catch (e) {
      return jsonError(res, 500, '预览合并失败', String(e?.message || e));
    }
  });

  app.post('/v1/admin/species/merge', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const targetId = Number(req.body?.target_species_id);
    const sourceId = Number(req.body?.source_species_id);
    const createSnapshot = req.body?.create_snapshot !== false;
    const addSourceScientificAsSynonym = req.body?.add_source_scientific_as_synonym !== false;
    const note = String(req.body?.note || '').trim();
    if (!Number.isFinite(targetId) || !Number.isFinite(sourceId)) {
      return jsonError(res, 400, 'target_species_id / source_species_id 无效');
    }
    if (targetId === sourceId) return jsonError(res, 400, 'A 与 B 不能相同');

    try {
      let snapshot = null;
      if (createSnapshot) {
        snapshot = await createSpeciesSnapshot({
          note: note || `merge B(${sourceId}) into A(${targetId})`,
          actorUserId: user.id,
        });
      }

      const { data: mergeResult, error: mergeErr } = await supabaseAdmin.rpc(
        'admin_merge_species_b_into_a',
        {
          p_target_species_id: targetId,
          p_source_species_id: sourceId,
          p_actor_user_id: user.id,
          p_add_source_scientific_as_synonym: addSourceScientificAsSynonym,
        }
      );
      if (mergeErr) return jsonError(res, 500, '执行合并失败', String(mergeErr.message || mergeErr));

      const targetScientific = mergeResult?.target_scientific_name || null;
      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'merge_species_b_into_a',
        speciesId: targetId,
        speciesScientificName: targetScientific,
        metadata: {
          merge_direction: 'B_into_A',
          snapshot_id: snapshot?.id || null,
          note: note || null,
          result: mergeResult || null,
        },
      });

      return res.json({
        ok: true,
        merge_direction: 'B_into_A',
        snapshot: snapshot || null,
        result: mergeResult || null,
      });
    } catch (e) {
      return jsonError(res, 500, '执行合并失败', String(e?.message || e));
    }
  });
}

module.exports = {
  registerAdminMergeRoutes,
};

