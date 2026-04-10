# Admin Analytics：数据质量风险、开关依赖与分阶段验收

本文拆成两部分：**第一部分**聚焦数据质量与依赖开关；**第二部分**聚焦分阶段上线与验收标准。与当前实现（`analytics_*` 视图、RPC、`/v1/admin/analytics/*`、Flutter Admin 看板）对齐。

---

## 第一部分：数据质量风险与开关依赖

### 1.1 数据质量风险（按优先级）

| 风险项 | 表现 / 根因 | 对看板的影响 | 缓解与记录方式 |
|--------|-------------|--------------|----------------|
| **埋点开关关闭** | 客户端显式设置 `ENABLE_ANALYTICS=false`（当前代码默认开启）或构建参数与环境预期不一致 | 表 `analytics_events` 无增量或极少；summary/daily 接近空 | 上线清单中明确「生产包是否打开埋点」；空态视为预期而非接口故障 |
| **properties 弱模式** | `jsonb` 缺字段、类型错误、枚举拼写不一致 | 扁平视图将字段视为 `null` 或无法 cast，计数偏少、UV 偏低 | 已在视图层做安全提取；定期跑「必填字段缺失率」SQL（按 `event_type`） |
| **时间与重试** | `occurred_at` 为服务端入库时间；客户端重试导致重复事件 | 事件数偏高；AI 侧依赖 `request_id` 去重 | 整窗 KPI 用 `summary.dedup_request_count`（AI）；禁止对 `daily.dedup` 相加解释成整窗 |
| **跨端同一用户** | 仅 `coalesce(user_id::text, anon_id)`，未做跨设备 ID 打通 | UV 可能被高估（多设备多 anon） | 合同已冻结口径；进阶需账号体系与 device 关联（非 MVP） |
| **platform / entry 空值** | 未传 `platform` 时落入 `__unknown__` | 「未知平台」桶占比过高时，分平台报表失真 | 监控 `platform='__unknown__'` 占比；客户端保证补 `platform` |
| **request_id 缺失** | AI 事件无 `request_id` | `dedup_request_count` 仅统计非空 `request_id`；与原始 `identify_start_count` 可能不一致 | 文档标明口径；推动客户端必带 `request_id` |
| **Collection 日 UV vs 窗 UV** | 单日多平台多行 `daily` | 若误将 `daily.collection_view_uv` 求和会得到错误整窗 UV | UI 已提示；整窗必须以 `summary` 中 RPC 结果为准 |
| **迁移未齐或 RPC 未部署** | 缺 `0015`/`0016` 或 `GRANT` 未生效 | BFF 查视图/RPC 报错 500 | 部署前用 `npm run migrate:analytics` 或 SQL 清单核对 |

### 1.2 开关与依赖（必须对齐的环境与配置）

| 类别 | 开关 / 配置项 | 作用 | 若不满足 |
|------|----------------|------|----------|
| **客户端埋点** | Flutter（当前默认开启；可用 `--dart-define=ENABLE_ANALYTICS=false` 显式关闭） | 是否向 `/v1/analytics/events` 写事件 | 看板无数据或仅历史数据 |
| **服务端写库** | BFF 已部署且可连 Supabase；`analytics_events` 存在 | 事件可持久化 | 上报失败或写库错误 |
| **管理端读库** | `SUPABASE_SERVICE_ROLE_KEY` + `SUPABASE_URL`（及库密码或 `DATABASE_URL` 用于迁移） | BFF 用 service role 读视图与 RPC | Admin 接口 5xx |
| **管理员身份** | `ADMIN_EMAILS` / `ADMIN_USER_IDS` | `requireAdmin` 通过 | 403 |
| **浏览器来源（可选）** | `ADMIN_ALLOWED_ORIGINS` 非空时 | 仅列出的 Origin 可访问 `/v1/admin/*` | 浏览器端 403；curl 无 Origin 通常仍放行 |
| **Admin Flutter** | `API_BASE_URL`（或等价 dart-define）指向正确 BFF | 看板请求打到含 Analytics 路由的实例 | 404 / 连错环境 |
| **合同版本** | `backend/.../analyticsDashboardContract.js` 与 `lib/admin/analytics/dashboard_contract.dart` 中 `contract_version` | 前后端口径一致 | 客户端 SnackBar 提示版本不一致 |

### 1.3 第一部分验收（文档与流程）

- [ ] 风险表已评审，已知「空数据」与 `ENABLE_ANALYTICS` 的因果关系。  
- [ ] 上线负责人手中有一份「环境变量检查表」（含上表开关）。  
- [ ] 数据/后端约定：整窗 UV、AI dedup **只认** `summary`，不认 `daily` 累加。

---

## 第二部分：分阶段上线与验收标准

### 2.1 阶段划分建议

| 阶段 | 范围 | 目标 |
|------|------|------|
| **P0** | DB：`0002`～`0016` 已应用；BFF：Admin Analytics 路由可用 | 接口与视图/RPC 连通，管理员可拉取 JSON |
| **P1** | 生产 App 保持默认开启或未显式关闭埋点（可小流量灰度） | 有持续事件写入，看板非空 |
| **P2** | Flutter Admin 看板给运营使用 | 四 Tab 可用，合同版本校验生效 |
| **P3（可选）** | 对账与性能 | 核心指标 SQL/API/UI 抽样一致；慢查询可接受 |

### 2.2 各阶段验收标准（可勾选）

**P0 — 基础设施与接口**

- [ ] `select 1 from analytics_event_flat_v limit 1;` 可执行（无则先确认 `0012`）。  
- [ ] `select 1 from analytics_overview_daily_v limit 1;`、`analytics_daily_kpi_v`、`analytics_ai_daily_v`、`analytics_collection_daily_v` 可执行。  
- [ ] `select public.admin_analytics_active_uv(current_date-7, current_date, null);` 等 RPC 可执行（service 角色与 BFF 一致）。  
- [ ] 使用管理员 Bearer：`GET /v1/admin/analytics/contract` 返回 200 且含 `contract_version`。  
- [ ] `GET /v1/admin/analytics/overview?time_range=7d` 返回 200，`data.summary` 与 `data.daily` 结构存在（允许全 0）。  
- [ ] 非管理员 403；未登录 401。

**P1 — 埋点与数据**

- [ ] 生产（或预发）构建未显式设置 `ENABLE_ANALYTICS=false`。  
- [ ] 抽样用户在 24h 内产生 `app_launch` 或核心业务事件，`analytics_events` 行数增长。  
- [ ] Overview `summary` 中 `active_users_uv` 与「仅打开埋点」预期一致（>0 或符合测试账号行为）。  
- [ ] AI Tab：`summary.dedup_request_count` 与「有 request_id 的 AI 事件」语义一致（不强行等于 start 行数）。

**P2 — Admin 看板产品化**

- [ ] Admin App 可登录并进入四 Tab，筛选 `7d` 后「应用」可刷新。  
- [ ] 合同版本不一致时出现 SnackBar（或等价提示），且不阻塞只读展示。  
- [ ] Collection / AI Tab 文案或界面提示与「summary 整窗、daily 分面」一致（与实现注释对齐）。

**P3 — 质量与性能（建议 1～2 周内补）**

- [ ] 任选 1 个时间窗，Overview 的 `upload_success_count`（summary 聚合逻辑）与 `analytics_event_flat_v` 手工 count 误差为 0。  
- [ ] `explain` 或 Supabase 慢查询：主要 Analytics 查询无全表 seq scan 失控（视数据量调整索引后再验收）。  
- [ ] 记录已知残留风险（如跨设备 UV、空 `request_id` 比例）。

### 2.3 回滚与降级

| 场景 | 动作 |
|------|------|
| 看板接口异常影响主站 | Admin 路由独立，一般无需关主站；可临时在网关禁用 `/v1/admin/analytics/*` |
| 埋点造成压力或隐私争议 | 发版设置 `ENABLE_ANALYTICS=false` 或后端对 `/v1/analytics/events` 限流（若已实现） |
| 错误数据污染 | 保留 `analytics_events` 审计策略；严重时可停写 + 后续清理分区/表（需 DBA 方案） |

### 2.4 第二部分验收（组织层面）

- [ ] P0～P2 勾选项责任到人、有执行日期。  
- [ ] P3 项有排期或明确「MVP 不做」。  
- [ ] 回滚表已同步到发布 checklist（可与 `docs/ADMIN_SPLIT_DEPLOY_CHECKLIST.md` 交叉引用）。

---

## 与现有文档的关系

- 合同与 Phase1/2 验收：`docs/admin_dashboard_contract_phase1_acceptance.md`、`docs/admin_dashboard_contract_phase2_acceptance.md`。  
- 埋点事件定义：`docs/analytics_implementation.md`。  
- 本文件：**上线前风险、开关、分阶段验收** 的单一入口，随版本迭代增补行即可。
