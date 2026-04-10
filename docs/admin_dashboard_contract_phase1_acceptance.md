# Admin Dashboard Contract Phase 1 验收记录（1.1~1.3）

> 范围：只覆盖 `define-kpi-contract` 的第一部分（事件字段清单、指标公式、筛选器规范）。

## 交付物

- 后端合同常量：`backend/admin/contracts/analyticsDashboardContract.js`
- 后端合同接口：`GET /v1/admin/analytics/contract`
- 前端共享版本常量：`lib/admin/analytics/dashboard_contract.dart`

## 1.1 统一事件与字段清单（验收通过）

### 已交付

- 合同内新增 `event_catalog`，覆盖 Dashboard 相关核心事件：
  - `app_launch`
  - `home_view`
  - `upload_click`
  - `upload_success`
  - `ai_identify_start`
  - `ai_identify_result`
  - `ai_identify_fail`
  - `species_unlock`
  - `collection_view`
  - `species_detail_view`
- 每个事件都显式定义字段依赖（`event_type`、`occurred_at`、`properties.*`、`user_id/anon_id` 等）。
- 保留 `event_field_dependencies`，用于按图表追溯 required fields。

### 验收点

- 4 个 Dashboard（Overview / Upload Funnel / AI Identify / Collection Growth）的 KPI 与图表均可追溯到具体 `event_type + 字段`。

## 1.2 冻结指标公式与分母规则（验收通过）

### 已交付

- 合同内新增 `metric_rules`，冻结统一计算口径：
  - `identity_key = coalesce(user_id::text, anon_id)`
  - `uv_rule = count(distinct identity_key)`
  - `ai_request_dedup = distinct properties->>'request_id'`
  - `conversion_denominator = same_time_window_previous_step_count`
  - `denominator_zero_behavior`（rate/uv 均返回 0）
  - `time_window_alignment`（分子分母同窗口、同筛选条件）
- 各 Dashboard KPI 保留显式 `formula`，避免同一指标出现多口径。

### 验收点

- 不存在同名指标多套算法，成功率/转化率/UV 的计算规则可在单一合同中查到。

## 1.3 冻结筛选器规范（验收通过）

### 已交付

- 合同内新增 `filter_schema`：
  - `time_range` 统一支持 `today/7d/30d/custom`
  - `platform`、`entry_position` 统一为可空字符串筛选键
  - `custom_time_range` 固定 `from/to` + `ISO-8601` + `UTC`
- `dashboards.*.filters` 继续按统一键组合声明。

### 验收点

- 4 个 Dashboard 可复用同一套筛选解析逻辑，不需要各自定义独立参数语义。

## 备注

- 第二部分（1.4 异常/空值策略、1.5 评审与版本冻结）不在本次验收范围，将在下一阶段补齐。
