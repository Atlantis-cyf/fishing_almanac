# 深度链接与分享（信息流 `feed-detail`）

应用使用 [go_router](https://pub.dev/packages/go_router)；信息流页支持 **query**、**path 参数** 与导航时的 **`FeedDetailExtra`**，三者合并规则见 [`feed_detail_route_args.dart`](feed_detail_route_args.dart) 内注释。

## 支持的 URL 形态

### 1. Query（推荐 H5 / 推送）

| 参数 | 说明 |
|------|------|
| `scientific_name` / `scientificName`，或兼容 `species` / `species_zh` / `speciesFilterZh` | 按物种筛选信息流（解析为拉丁学名，与 `FeedDetailScreen.speciesScientificName` 一致） |
| `index` / `i` | 初始滚动到的条目索引（默认 `0`） |

示例（需对中文与空格做 **UTF-8 百分号编码**）：

```text
https://你的域名/feed-detail?species=%E9%AF%AF%E9%B2%8C&index=0
```

本地 / 自定义 scheme 示例：

```text
fishingalmanac://feed-detail?species=%E9%AF%AF%E9%B2%8C
```

### 2. Path（单段鱼种名，便于分享短链）

```text
https://你的域名/feed-detail/%E9%AF%AF%E9%B2%8C
```

第二段为 **URL 编码** 后的物种片段（中文名或拉丁学名，路由参数名为 `scientificName`，解析后存为规范化学名）。仍可与 query 组合，例如：`.../feed-detail/%E9%AF%AF%E9%B2%8C?index=2`。

### 3. 应用内 `extra`

`context.push('/feed-detail', extra: FeedDetailExtra(initialIndex: 3, speciesScientificName: 'Coryphaena hippurus'))`（也可传中文名，会解析为学名）；与 URL 并存时 **extra 优先决定 `initialIndex`**；**`speciesScientificName` 以 extra 非空为准，否则回落到 path/query**。

## 未登录冷启动

访问需登录路径时，`auth_redirect` 会跳到 `/login?redirect=…`，`redirect` 为原始 **path + query**（由 `Uri` 编码为单个 query 值）。登录成功后客户端 **`context.go(redirect)`**，可恢复带 `species` 的信息流页。

## H5 打开 App

1. **Universal Links（iOS）/ App Links（Android）**  
   - 在域名下放 `apple-app-site-association` / `assetlinks.json`。  
   - 将上述 `https://你的域名/feed-detail?...` 作为 `<a href>` 或 `window.location`。  
   - 在工程内配置与 manifest / Info.plist 中相同的 host 与 pathPrefix（示例见下）。

2. **URL Scheme**  
   - 注册自定义 scheme（如 `fishingalmanac://`），由 H5 `intent://` 或 `window.location = schemeUrl` 调起（各浏览器策略不同，需实测）。

3. **Web 端**  
   - 若部署 Flutter Web，同一 path + query 由浏览器直接打开即可，无需调起原生 App。

## Android 示例（`AndroidManifest.xml`）

在 `MainActivity` 的 `<activity>` 内增加（**请替换 `your.host` 为实际域名**）：

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="https"
        android:host="your.host"
        android:pathPrefix="/feed-detail" />
</intent-filter>
```

## 推送（FCM / 厂商通道）

Payload 中携带 **可点击的完整 HTTPS 链接**（与已配置的 App Links 一致），用户点击通知后由系统打开 App 并传入相同 URI；Flutter 引擎将该 URI 交给 `GoRouter`，即可落到 `feed-detail` 并应用 `species` / `index` 筛选。
