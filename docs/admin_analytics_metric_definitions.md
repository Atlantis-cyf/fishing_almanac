# Admin Analytics 指标计算口径（统一版）

本文定义管理端四个看板（Overview / Upload / AI / Collection）的字段口径，作为产品、研发、数据三方统一标准。

## 1. 总原则

- `用户数` = UV（去重用户数，按 `identity_key` 去重）。
- `次数` = 事件条数（count）。
- `请求数（去重）` = 以业务请求主键去重后的请求量（例如 AI 用 `request_id`）。
- `summary` 表示整窗汇总；`daily` 表示按日拆分。除明确说明外，整窗指标以 `summary` 为准，不用 `daily` 直接累加替代。
- 本文时间窗由筛选条件决定（`7d / 14d / custom`）。

## 2. 关键去重规则

### 2.1 DAU（Overview）

- 定义：`DAU = 当天触发过 app_launch 的去重用户数`
- 去重键：`identity_key`
- 说明：Overview 的 DAU 读取 `active_users_uv`，其实现口径对应当日 `app_launch` UV。

### 2.2 upload_click（Upload / Overview 漏斗）

- 定义：上传点击次数 = `upload_click` 的短时重复点击去重后次数。
- 去重窗口：`600ms`
- 去重键：`identity_key + platform + entry_position`
- 规则：同一去重键在 `600ms` 内连续上报只记 1 次。

### 2.3 AI 请求去重（AI）

- 定义：`识别发起/成功/失败请求数` 以 `request_id` 去重统计。
- 事件集合：
  - 发起：`ai_identify_start`
  - 成功：`ai_identify_result`
  - 失败：`ai_identify_fail`
- 说明：无 `request_id` 的事件不计入去重请求数口径。

## 3. Overview 口径

### 3.1 KPI 卡片

- `DAU`：当天 `app_launch` UV。
- `上传用户数`：时间窗内触发 `upload_click` 的 UV（`upload_click_uv`）。
- `上传成功用户数`：时间窗内触发 `upload_success` 的 UV（`upload_success_uv`）。
- `AI识别成功用户数`：时间窗内 AI 成功用户 UV（`ai_identify_success_uv`）。
- `新增解锁用户数`：时间窗内触发 `species_unlock` 的 UV（`species_unlock_user_uv`）。
- `每活跃用户新增解锁数`：`species_unlock_count / active_users_uv`（分母为 0 时显示 `-`）。
- `图鉴访问用户数`：时间窗内 `collection_view` UV（`collection_view_uv`）。
- `识别成功率`：`ai_identify_success_request_count / ai_identify_start_request_count`。

### 3.2 漏斗（全 UV）

- `app_launch_uv` -> `upload_click_uv` -> `upload_success_uv` -> `ai_identify_success_uv` -> `species_unlock_user_uv`
- 要求：同一漏斗仅使用 UV 口径，禁止 UV / 次数混用。

## 4. Upload 口径

- `上传点击用户数`：`upload_click_uv`
- `上传点击次数`：`upload_click_count`（600ms 去重后）
- `上传成功用户数`：`upload_success_uv`
- `上传成功次数`：`upload_success_count`
- `上传成功率`：`upload_success_count / upload_click_count`
- `平均上传耗时`：`upload_avg_duration_ms`（毫秒）
- `camera / album 占比`：按 `entry_position_click_mix` 聚合展示（计数口径）

## 5. AI 口径

- `识别发起请求数`：`identify_start_count`（按 `request_id` 去重）
- `识别成功请求数`：`identify_result_count`（按 `request_id` 去重）
- `识别失败请求数`：`identify_fail_count`（按 `request_id` 去重）
- `识别成功率`：`identify_result_count / identify_start_count`
- `平均延迟`：`identify_latency_avg_ms`
- `平均置信度`：`identify_confidence_avg`
- `失败原因分布`：`fail_reason_breakdown`

## 6. Collection 口径

- `图鉴访问用户数`：`collection_view_uv`
- `图鉴访问次数`：`collection_view_count`
- `鱼种详情访问用户数`：`species_detail_view_uv`
- `鱼种详情访问次数`：`species_detail_view_count`
- `人均图鉴查看次数`：`collection_view_count / collection_view_uv`（分母为 0 时不展示）
- `人均详情查看次数`：`species_detail_view_count / species_detail_view_uv`（分母为 0 时不展示）
- `新增解锁用户数`：`species_unlock_user_uv`
- `每活跃用户新增解锁数`：`species_unlock_count / active_users_uv`（分母为 0 时显示 `-`）

## 7. 命名规范（UI）

- UV 类统一用“`用户数`”。
- 计数类统一用“`次数`”或“`请求数（去重）`”。
- 解锁类统一用“`新增解锁用户数`”“`新增解锁次数`”。
- 只在“历史累计”语义下使用“`累计...`”前缀，不与新增口径混用。

## 8. 排错建议

- 看板“全 0”优先检查：客户端埋点开关、时间窗、过滤条件。
- 若怀疑重复上报，先核验 `upload_click` 的 600ms 去重是否命中，再检查客户端是否存在重复触发。
- 整窗对账一律以 `summary` 字段为主，避免误把 `daily` 相加作为最终口径。
