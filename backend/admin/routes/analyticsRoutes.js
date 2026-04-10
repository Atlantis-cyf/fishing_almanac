const {
  CONTRACT_VERSION,
  ANALYTICS_DASHBOARD_CONTRACT,
} = require('../contracts/analyticsDashboardContract');
const { parseAdminAnalyticsQuery } = require('../utils/adminAnalyticsQuery');
const {
  fetchOverviewAggregate,
  fetchUploadFunnelAggregate,
  fetchAiIdentifyAggregate,
  fetchCollectionGrowthAggregate,
} = require('../services/adminAnalyticsAggregate');

/**
 * 参数校验失败时返回 4xx，并附带稳定 error code 供前端区分。
 * @param {*} res Express res
 * @param {{ status: number, code: string, message: string }} err
 */
function analyticsQueryError(res, err) {
  return res.status(err.status).json({
    message: err.message,
    code: err.code,
  });
}

function registerAdminAnalyticsRoutes({ app, requireAdmin, jsonError, supabaseAdmin }) {
  app.get('/v1/admin/analytics/contract', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;

    return res.json({
      contract_version: CONTRACT_VERSION,
      contract: ANALYTICS_DASHBOARD_CONTRACT,
    });
  });

  // ---------- 聚合接口（第二部分）：读 analytics_* 视图 + 统一 filter ----------

  app.get('/v1/admin/analytics/overview', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const parsed = parseAdminAnalyticsQuery(req.query);
    if (!parsed.ok) return analyticsQueryError(res, parsed.error);
    try {
      const data = await fetchOverviewAggregate(supabaseAdmin, parsed.filter);
      return res.json({
        contract_version: CONTRACT_VERSION,
        endpoint: 'overview',
        filter: parsed.filter,
        data,
      });
    } catch (e) {
      return jsonError(res, 500, 'Analytics 概览查询失败', String(e?.message || e));
    }
  });

  app.get('/v1/admin/analytics/upload-funnel', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const parsed = parseAdminAnalyticsQuery(req.query);
    if (!parsed.ok) return analyticsQueryError(res, parsed.error);
    try {
      const data = await fetchUploadFunnelAggregate(supabaseAdmin, parsed.filter);
      return res.json({
        contract_version: CONTRACT_VERSION,
        endpoint: 'upload_funnel',
        filter: parsed.filter,
        data,
      });
    } catch (e) {
      return jsonError(res, 500, 'Analytics 上传漏斗查询失败', String(e?.message || e));
    }
  });

  app.get('/v1/admin/analytics/ai-identify', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const parsed = parseAdminAnalyticsQuery(req.query);
    if (!parsed.ok) return analyticsQueryError(res, parsed.error);
    try {
      const data = await fetchAiIdentifyAggregate(supabaseAdmin, parsed.filter);
      return res.json({
        contract_version: CONTRACT_VERSION,
        endpoint: 'ai_identify',
        filter: parsed.filter,
        data,
      });
    } catch (e) {
      return jsonError(res, 500, 'Analytics AI 识别查询失败', String(e?.message || e));
    }
  });

  app.get('/v1/admin/analytics/collection-growth', async (req, res) => {
    const user = await requireAdmin(req, res);
    if (!user) return;
    const parsed = parseAdminAnalyticsQuery(req.query);
    if (!parsed.ok) return analyticsQueryError(res, parsed.error);
    try {
      const data = await fetchCollectionGrowthAggregate(supabaseAdmin, parsed.filter);
      return res.json({
        contract_version: CONTRACT_VERSION,
        endpoint: 'collection_growth',
        filter: parsed.filter,
        data,
      });
    } catch (e) {
      return jsonError(res, 500, 'Analytics 图鉴增长查询失败', String(e?.message || e));
    }
  });
}

module.exports = {
  registerAdminAnalyticsRoutes,
};
