# Admin Dashboard Contract Phase 2 验收记录（1.4~1.5）

> 范围：`define-kpi-contract` 第二部分（异常/空值策略、合同评审与版本冻结）。

## 交付物

- 合同容错策略：`backend/admin/contracts/analyticsDashboardContract.js` 的 `data_quality_rules`
- 合同变更模板：`backend/admin/contracts/analyticsDashboardContract.js` 的 `changelog_template`
- 前端版本常量（持续对齐）：`lib/admin/analytics/dashboard_contract.dart`

## 1.4 异常/空值策略（验收通过）

### 已交付

- 合同新增 `data_quality_rules`，集中定义查询层容错行为：
  - `missing_properties_field`: 缺字段按 `null` 处理
  - `type_mismatch`: 安全转换失败后回落 `null`
  - `zero_denominator`: 比率分母为 0 时返回 `0`
  - `request_id_dedup`: 优先按 `request_id` 去重
  - `null_platform`: 归档到 `__unknown__` 桶

### 验收点

- 查询层面对脏数据具备明确且统一的回退语义，不会因字段缺失/类型错误导致接口直接报错。

## 1.5 合同评审与版本冻结（验收通过）

### 已交付

- 合同固化 `contract_version`，并由接口统一返回：
  - 后端常量：`CONTRACT_VERSION = 2026-04-mvp-v1`
  - 接口字段：`GET /v1/admin/analytics/contract` 返回 `contract_version`
- 合同新增 `changelog_template`，约束后续改动必须提供：
  - `contract_version`
  - `change_summary`
  - `owner`
  - `reviewers`
  - `compatible_since`
  - `breaking_change`
- 前端提供 `AdminDashboardContract.contractVersion` 作为版本对齐点。

### 验收点

- 后端接口与前端常量均引用同一版本号；后续变更具备标准化记录模板，可按版本追踪。
