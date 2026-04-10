# 海钓图鉴 App 埋点实施文档（最小闭环）

## 1. 范围与目标

本次只覆盖核心链路：

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
- `identify_feedback`（预留接口，无强制 UI）

目标支撑以下分析：

1. 用户是否进入 App
2. 用户是否点击上传
3. 上传是否成功
4. AI 识别是否成功、耗时、识别结果
5. 是否解锁新鱼种
6. 是否查看图鉴与鱼种详情
7. 是否提交识别正确/错误反馈

## 2. 命名与结构规范

- 事件命名统一为 `lower_snake_case`
- 所有埋点统一入口：`AnalyticsClient.trackEvent(...)`
- 公共字段自动补齐：`timestamp`、`platform`、`app_version`、`user_id`
- 事件与属性常量集中定义：
  - `lib/analytics/analytics_events.dart`
  - `lib/analytics/analytics_props.dart`

## 3. 事件定义（MVP）

### app_launch
- 触发：应用启动
- 属性：`platform`、`app_version`、`device_id`（预留）、`user_id`（可空）

### home_view
- 触发：首页首次展示
- 属性：`user_id`、`timestamp`

### upload_click
- 触发：用户点击上传入口
- 属性：`entry_position`、`user_id`
- 典型 `entry_position`：
  - `bottom_nav_record`
  - `record_photo_picker`
  - `record_next_step`
  - `select_location_next`
  - `feed_detail_edit`

### upload_success
- 触发：鱼获发布成功
- 属性：`source`、`upload_duration_ms`、`image_id`、`file_size`、`user_id`

### ai_identify_start
- 触发：AI 识别请求发起
- 属性：`request_id`、`image_id`、`user_id`

### ai_identify_result
- 触发：AI 返回成功结果（含非鱼情况）
- 属性：`request_id`、`image_id`、`species_name`、`confidence`、`latency_ms`、`is_success=true`、`user_id`

### ai_identify_fail
- 触发：AI 调用失败或异常
- 属性：`request_id`、`image_id`、`error_code`、`error_message`、`latency_ms`、`is_success=false`、`user_id`

### species_unlock
- 触发：图鉴刷新后，某鱼种由未解锁变为已解锁
- 属性：`species_name`、`is_first_time=true`、`unlock_source=ai_identify`、`user_id`

### collection_view
- 触发：图鉴页首次加载完成
- 属性：`unlocked_species_count`、`total_species_count`、`completion_rate`、`user_id`

### species_detail_view
- 触发：进入鱼种详情页
- 属性：`species_name`、`unlocked`、`user_id`

### identify_feedback
- 触发：用户对识别结果反馈
- 属性：`request_id`、`image_id`、`species_id`、`is_correct`、`user_id`
- 当前状态：已提供 `AnalyticsClient.trackIdentifyFeedback(...)` 预留接口

## 4. 代码接入点

- App 启动：`lib/app.dart`
- 首页曝光：`lib/screens/home_screen.dart`
- 上传入口点击：`lib/widgets/bottom_nav.dart`、`lib/screens/record_screen.dart`、`lib/screens/select_location_screen.dart`、`lib/screens/feed_detail_screen.dart`
- 上传成功：`lib/screens/edit_catch_screen.dart`
- AI 识别开始/结果/失败：`lib/services/catch_draft_ai_identify.dart`
- 图鉴浏览与解锁：`lib/screens/encyclopedia_screen.dart`
- 鱼种详情曝光：`lib/screens/species_detail_screen.dart`

## 5. 扩展策略

当前保持轻量实现，后续可通过 adapter 平滑扩展到 Firebase / PostHog / 神策 / 自建埋点，无需改页面层调用方式。
