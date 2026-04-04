# API 层说明

## `CatchRepository` 与联调开关

界面只依赖 `CatchRepository`（`lib/repositories/`），不在 Widget 中 `jsonDecode` SharedPreferences。

| 实现 | 说明 |
|------|------|
| `LocalCatchRepository` | 默认；持久化键 `published_catches_v1`；时间线为 `CatchFeedPage` 单页 |
| `RemoteCatchRepository` | `GET` 列表 + `publish` multipart（见下）；未登录列表见 `FeedDetailScreen` fallback；`upsertLocal` 仍无操作 |

切换方式：`FishingAlmanacApp(useRemoteCatchRepository: true)`，或构建参数  
`--dart-define=USE_REMOTE_CATCH_REPOSITORY=true`（默认 `false`）。

### 鱼种识别（`SpeciesIdentifyEndpoints`）

| 实现 | 说明 |
|------|------|
| `StubSpeciesIdentificationService` | 默认；无网开发，无照片时返回占位 `—` |
| `RemoteSpeciesIdentificationService` | `POST` [SpeciesIdentifyEndpoints.path]；有本地字节走 **multipart**（字段名 `SPECIES_IDENTIFY_IMAGE_FIELD`，默认 `image`），仅 URL 时 **JSON** `{"image_url":"..."}`；Bearer 与 [ApiClient] 一致 |

切换：`FishingAlmanacApp(useRemoteSpeciesIdentification: true)` 或  
`--dart-define=USE_REMOTE_SPECIES_IDENTIFICATION=true`（默认 `false`）。

成功响应解析见 `SpeciesIdentifyPayload`：优先根级或 `data` 内 `scientific_name` / `scientificName`；仍可读 `species_zh` / `speciesZh` 并映射为学名。`confidence` 支持 0–1 或 0–100。

### 用户资料（`UserMeEndpoints`）

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `USER_ME_PATH`（默认 `/me`） | [UserProfile.syncFromServer] 登录后/冷启动恢复 token 时拉取展示名 |
| `PATCH` | 同上 | 请求体 `{"display_name":"..."}`；[UserProfile.setDisplayName] 在已登录时调用 |

响应解析见 `UserMeDto`：支持根级、`data` 包裹或 `user` 嵌套下的 `display_name` / `displayName` / `nickname` / `username` 等。本地 `SharedPreferences` 键 `user_display_name_v1` 为缓存；**已登录时以服务端成功响应为准**，`GET` 失败则保留缓存。登出时 [UserProfile.onSessionEnded] 清除展示名缓存。

### 列表 GET（`CatchListEndpoints`）

| `dart-define` | 含义 | 默认 |
|---------------|------|------|
| `CATCH_LIST_PATH` | 路径 | `/v1/catches` |
| `CATCH_LIST_LIMIT` | `limit` | `20` |
| `CATCH_LIST_USE_PAGE_PARAM` | `true` 时用 `page`，否则 `after_occurred_at_ms` + `after_id` | `false` |
| `CATCH_LIST_USE_SPECIES_ID` | 物种筛选优先 `species_id`（内置学名→id 映射） | `false` |

Query 常用：`limit`、`scientific_name` 或 `species_id`（兼容 `species_zh`）、`page` 或游标字段。

响应解析见 `CatchListPageParser`：`items` / `records` / `results`，`has_more`，`next_cursor`（`occurred_at_ms`+`id` 或 `page`）。

### 发布鱼获（multipart）

- **POST** `CATCH_PUBLISH_PATH`（默认 `/v1/catches`），`multipart/form-data`。
- **PUT** `CATCH_CATCH_DETAIL_BASE` + `/{id}`，仅当 `updateId` 为 UUID 且处于编辑模式时。
- 图片字段名：`CATCH_PUBLISH_IMAGE_FIELD`（默认 `image`），JPEG 字节。
- 文本字段：`scientific_name`（主）、`notes`、`weight_kg`、`length_cm`、`location_label`、`lat`、`lng`、`occurred_at`（UTC ISO8601）；兼容旧字段 `species_zh`（BFF 会尽量映射占位）。

图片发布前处理（`CatchPublishImagePrepare`）：

| `dart-define` | 含义 | 默认 |
|---------------|------|------|
| `CATCH_IMAGE_MAX_EDGE` | 长边像素上限 | `2048` |
| `CATCH_PUBLISH_JPEG_QUALITY` | JPEG 质量 1–100 | `85` |
| `CATCH_PUBLISH_SKIP_IMAGE_REENCODE` | 跳过压缩/转 JPEG | `false` |
| `CATCH_IMAGE_PICKER_QUALITY` | `ImagePicker.imageQuality` | `85` |

---

## 鱼获：`CatchRecordDto` ↔ 应用模型

后端 JSON 使用 **snake_case**；应用内 `PublishedCatch` / `CatchFeedItem` 保持 **camelCase** 字段名不变。  
在边界只做一次转换：`CatchRecordDto.fromJson` / `toJson`，再用 `lib/api/mappers/catch_record_mapper.dart` 映射。

### 字段对照表

| 后端 JSON 键 | `CatchRecordDto` (Dart) | `PublishedCatch` / `CatchFeedItem` |
|--------------|-------------------------|--------------------------------------|
| `id` | `id` (`String`，UUID 或数字转字符串) | `id` |
| `image_base64` | `imageBase64` | `imageBase64` / 解码为 `CatchFeedItem.imageBytes` |
| `image_url` | `imageUrl` | `imageUrlFallback` / `imageUrl` |
| `species_zh` | `speciesZh` | `speciesZh` |
| `notes` | `notes` | `notes` |
| `weight_kg` | `weightKg` | `weightKg` |
| `length_cm` | `lengthCm` | `lengthCm` |
| `location_label` | `locationLabel` | `locationLabel` |
| `lat` | `lat` | `lat` |
| `lng` | `lng` | `lng` |
| `occurred_at` | `occurredAt` | `occurredAt` |
| `review_status`（可选，兼容根级 `status`） | `reviewStatus` | `reviewStatus`（`pending_review` / `rejected` / `approved`） |
| `occurred_at_ms`（可选） | 解析为 `occurredAt` | 仅 DTO 读入；`toJson` 仍只写 `occurred_at` |

列表项缺 `review_status` 时按已上线处理（`approved`）。**创建/更新接口**返回体缺该字段时，解析侧默认 `pending_review`，与发布后待审核衔接（见 `tryParsePublishedCatchResponse`）。

### 时间约定

- **序列化**：`occurred_at` 为 **UTC** ISO-8601（`toUtc().toIso8601String()`）。
- **反序列化**：优先 `occurred_at_ms`（UTC 毫秒）；否则解析 `occurred_at` 字符串（`DateTime.tryParse`）。

详见 `lib/api/dto/catch_record_dto.dart` 类注释。

### 最小请求/响应样例（JSON）

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "image_base64": null,
  "image_url": "https://cdn.example.com/a.jpg",
  "scientific_name": "Thunnus thynnus",
  "notes": "",
  "weight_kg": 12.5,
  "length_cm": 100,
  "location_label": "东海",
  "lat": 30.0,
  "lng": 122.0,
  "occurred_at": "2024-06-15T08:30:00.000Z"
}
```
