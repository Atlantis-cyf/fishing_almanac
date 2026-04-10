const { registerAdminSpeciesRoutes } = require('./routes/speciesRoutes');
const { registerAdminMergeRoutes } = require('./routes/mergeRoutes');
const { registerAdminSnapshotRoutes } = require('./routes/snapshotRoutes');
const { registerAdminAnalyticsRoutes } = require('./routes/analyticsRoutes');

function registerAdminRoutes(deps) {
  const {
    app,
    jsonError,
    isAdminOriginAllowed,
  } = deps;

  app.use('/v1/admin', (req, res, next) => {
    if (!isAdminOriginAllowed(req)) {
      return jsonError(res, 403, '当前来源域名不在后台白名单');
    }
    return next();
  });

  registerAdminSpeciesRoutes(deps);
  registerAdminMergeRoutes(deps);
  registerAdminSnapshotRoutes(deps);
  registerAdminAnalyticsRoutes(deps);
}

module.exports = {
  registerAdminRoutes,
};

