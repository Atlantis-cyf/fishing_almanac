function registerAdminSnapshotRoutes({
  app,
  supabaseAdmin,
  jsonError,
  requireAdmin,
  logSpeciesAdminAction,
  createSpeciesSnapshot,
}) {
  app.post('/v1/admin/species/snapshots', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    try {
      const note = String(req.body?.note || '').trim();
      const snap = await createSpeciesSnapshot({ note, actorUserId: user.id });
      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'create_species_snapshot',
        metadata: { snapshot_id: snap.id, note: snap.note || null },
      });
      return res.json({ snapshot: snap });
    } catch (e) {
      return jsonError(res, 500, '创建快照失败', String(e?.message || e));
    }
  });

  app.get('/v1/admin/species/snapshots', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    try {
      const { data, error } = await supabaseAdmin
        .from('species_catalog_snapshots')
        .select('id, note, created_by, created_at')
        .order('created_at', { ascending: false })
        .limit(100);
      if (error) return jsonError(res, 500, '读取快照列表失败', String(error.message || error));
      return res.json({ snapshots: data || [] });
    } catch (e) {
      return jsonError(res, 500, '读取快照列表失败', String(e?.message || e));
    }
  });

  app.post('/v1/admin/species/snapshots/:id/restore', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const snapshotId = String(req.params.id || '').trim();
    if (!snapshotId) return jsonError(res, 400, '缺少快照ID');

    try {
      const { data: restoreResult, error: restoreErr } = await supabaseAdmin.rpc(
        'admin_restore_species_snapshot',
        { p_snapshot_id: snapshotId }
      );
      if (restoreErr) return jsonError(res, 500, '回滚快照失败', String(restoreErr.message || restoreErr));

      await logSpeciesAdminAction({
        actorUserId: user.id,
        action: 'restore_species_snapshot',
        metadata: { snapshot_id: snapshotId, restored_rows: restoreResult?.restored_rows || 0 },
      });

      return res.json({
        ok: true,
        snapshot_id: snapshotId,
        restored_rows: restoreResult?.restored_rows || 0,
      });
    } catch (e) {
      return jsonError(res, 500, '回滚快照失败', String(e?.message || e));
    }
  });

  app.get('/v1/admin/species/audit-logs', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    try {
      const limit = Math.max(1, Math.min(200, Number(req.query.limit || 50)));
      const { data, error } = await supabaseAdmin
        .from('species_admin_audit_logs')
        .select('id, actor_user_id, action, species_id, species_scientific_name, before_data, after_data, metadata, created_at')
        .order('created_at', { ascending: false })
        .limit(limit);
      if (error) return jsonError(res, 500, '读取审计日志失败', String(error.message || error));
      return res.json({ logs: data || [] });
    } catch (e) {
      return jsonError(res, 500, '读取审计日志失败', String(e?.message || e));
    }
  });
}

module.exports = {
  registerAdminSnapshotRoutes,
};

