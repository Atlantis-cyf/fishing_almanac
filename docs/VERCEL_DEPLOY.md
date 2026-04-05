# Vercel 部署说明（Flutter Web + Express BFF）

本文档汇总本项目在 Vercel 上部署时**踩过的坑**与**当前推荐做法**，供下次发布对照。

---

## 1. 架构说明

| 层级 | 作用 | 在 Vercel 中的位置 |
|------|------|-------------------|
| 静态站点 | Flutter Web 构建产物 | `vercel.json` 的 `outputDirectory`: `build/web` |
| BFF（API） | Express，对接 Supabase | `api/server.js` → `require('../backend/server.js')` |
| 路由 | 浏览器路径 → 静态页或 Serverless | `vercel.json` 的 `rewrites` |

构建流程：

1. **安装**：`scripts/vercel-install.sh` — `npm install`（含 workspace 的 `backend` 依赖）+ 克隆 Flutter stable 并 `precache --web`。
2. **构建**：`scripts/vercel-build.sh` — `flutter build web --release`，并注入 `USE_REMOTE_CATCH_REPOSITORY=true`、`USE_REMOTE_SPECIES_IDENTIFICATION=true`（与联调 BFF 一致）；可选再加 `API_BASE_URL`。
3. **运行**：静态资源由 CDN 提供；`/healthz`、`/auth/*`、`/me`、`/v1/*` 被 rewrite 到 **同一** Serverless 函数 `api/server.js`。

---

## 2. Vercel 项目设置（重要）

### 2.1 全栈部署（推荐：一个项目搞定 Web + API）

- **Root Directory**：留空（仓库根目录即 `fishing_almanac`，与 `vercel.json` 同级）。
- **Framework Preset**：Other / 无框架亦可，以 `vercel.json` 为准。
- **不要在 Dashboard 里随意覆盖** `Output Directory`、`Build Command`、`Install Command` 为与仓库不一致的值（例如误填 `dist`、`npm run build` 指向错误脚本），否则易出现 **404 / NOT_FOUND** 或构建失败。

### 2.2 仅部署后端（可选）

若单独把 Vercel 项目的 **Root Directory** 设为 `backend`，则使用 `backend/vercel.json`（仅安装依赖、无 Flutter）。此时需另有一处托管前端，并在前端构建参数里把 `API_BASE_URL` 指向该 BFF 域名。

---

## 3. 环境变量（必配）

在 Vercel → Project → **Settings → Environment Variables** 中配置，**Production** 与 **Preview** 按需要分别勾选（预览环境也要测登录时，Preview 也必须配齐）。

| 变量名 | 说明 |
|--------|------|
| `SUPABASE_URL` | 项目 URL，必须以 `https://` 开头 |
| `SUPABASE_ANON_KEY` | Supabase Dashboard → Project Settings → API → `anon` `public` |
| `SUPABASE_SERVICE_ROLE_KEY` | 同上 → `service_role` **secret**，仅服务端，勿进客户端 |

### 3.1 历史上因此出过的问题

- **缺少任一变量**：旧代码在加载 `backend/server.js` 时直接 `throw`，Vercel 函数初始化失败，浏览器只看到 **`{ code: 500, message: A server error has occurred }`**，难以排查。
- **变量名写错**：例如 `SUPABASE_UR` 少了 `L`，应用仍视为未配置。
- **URL 写错**：例如 `ttps://...` 少了 `h`，或复制时截断。

**当前代码行为**：在 Vercel 上若仍缺上述三项，BFF 会以降级模式启动，**`/healthz` 返回 503** 及 JSON（含 `missing_supabase_env` 与中文提示），便于区分「环境变量问题」与其它 500。

配置正确并重新部署后，`GET /healthz` 应返回 **`{"ok":true}`**（200）。

### 3.2 可选：`API_BASE_URL`

- **默认不设置**：全栈 Web 构建**不**注入 `API_BASE_URL`，前端在浏览器里使用 **`Uri.base.origin`**（与当前访问域名同源），避免下面「多域名」问题。
- **需要固定指向外部 API 时**：在 Vercel 中设置 `API_BASE_URL=https://你的-BFF-域名`，构建脚本会追加 `--dart-define=API_BASE_URL=...`。

### 3.3 鱼获信息流必须用远端仓库（构建已默认打开）

`lib/app.dart` 里 `USE_REMOTE_CATCH_REPOSITORY` 默认 **`false`**。若线上 Web 构建**未**打开该开关，会使用 **`LocalCatchRepository`**，鱼获只读浏览器本地存储，与「已登录 + 服务端鱼获」预期不一致，且列表常为空。

**当前**：`vercel-build.sh` 已固定传入 `--dart-define=USE_REMOTE_CATCH_REPOSITORY=true`（及物种识别远端开关）。本地若未加该参数，模拟器/桌面仍可能是本地仓库，表现为「本机能刷出流、线上不行」。

### 3.4 Web 上信息流「黑屏」与 `ScrollablePositionedList`

若数据已加载但列表区域一片黑/空白，常见 **不是**单纯网络超时（网络问题多会走「加载失败 / 重试」文案）。Flutter Web 上 **`ScrollablePositionedList` 在异步出数据后配合非零 `initialScrollIndex`** 有已知空白视口问题（如 [flutter.widgets#418](https://github.com/google/flutter.widgets/issues/418)）。

**当前**：`FeedDetailScreen` 在 Web 上 **`initialScrollIndex` 固定为 0**，再通过已有 `scrollTo` 跳到锚点，降低黑屏概率。

---

## 4. 多域名是正常的（不要误以为部署了三份）

同一次部署在 Vercel 上常见 **多个 Domains**，含义不同，**内容一致**：

| 类型 | 示例形态 | 用途 |
|------|-----------|------|
| 生产主域名 | `项目名.vercel.app` | 对外主入口，指向最新生产部署 |
| 分支 URL | `项目名-git-main-团队.vercel.app` | 对应分支的最新部署，便于预览 |
| 单次部署 URL | `项目名-随机串-团队.vercel.app` | 钉死某一次构建，便于分享与排错 |

无需强制「只保留一个」；对外可只宣传生产主域名或自定义域名。

---

## 5. 历史上「能登录 / 不能登录」与域名相关的问题

### 5.1 原因

曾在构建脚本里把 `API_BASE_URL` 默认设为 **`https://${VERCEL_URL}`**。而 **`VERCEL_URL` 往往是当次部署独有的主机名**（即上面表格第三行那种），会被**编译进** Flutter Web。

结果：

- 用**单次部署 URL** 打开页面时：页面与 API 请求**同源** → 登录正常。
- 用 **`项目名.vercel.app`** 或 **分支 URL** 打开时：页面在一个主机，API 却请求**另一个子域名** → 浏览器跨域或表现为「无法连接后端」。

### 5.2 当前做法

- `scripts/vercel-build.sh`：**不再**默认把 `API_BASE_URL` 设为 `$VERCEL_URL`。
- `lib/api/api_config.dart`：Web 端在未传 `dart-define` 时使用 **`Uri.base.origin`**，保证「在哪个域名打开，就打哪个域名的 API」。

---

## 6. 其它历史踩坑（简表）

| 现象 | 可能原因 | 处理方向 |
|------|-----------|----------|
| 整站 404 / NOT_FOUND | Dashboard 覆盖输出目录、Root Directory 错误、无 `vercel.json` | 以仓库 `vercel.json` 为准，Root 指向前端+API 根目录 |
| 线上鱼获信息流黑屏/空白、模拟器正常 | Web 未打开 `USE_REMOTE_CATCH_REPOSITORY` 或 `ScrollablePositionedList` Web 缺陷 | 构建脚本已默认远端仓库；Web 上 `initialScrollIndex` 用 0 + `scrollTo` |
| API 只有笼统 500 | Supabase 环境变量缺失或加载时抛错 | 配齐三变量；看 `/healthz` 与 Function Logs |
| Flutter 构建失败 | 安装脚本过长或命令非法 | 使用 `scripts/vercel-install.sh` / `vercel-build.sh` 文件，避免单行超长 |
| 依赖装不全 | 未在仓库根执行 `npm install`（workspace） | 根目录 `package.json` 已含 `workspaces: ["backend"]`，安装脚本在根目录执行 |

---

## 7. 部署后检查清单

1. **环境变量**：`SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` 名称与值正确，`https://` 完整。
2. **健康检查**：浏览器访问 `https://你的域名/healthz` → 期望 `{"ok":true}`。
3. **登录**：在生产主域名与（如需）分支 URL 各测一次，确认不再依赖「某次部署专属 URL」才能登录。
4. **Supabase Auth**：Redirect URL / Site URL 若使用自定义域名或 `*.vercel.app`，需在 Supabase 控制台与白名单一致。

---

## 8. 本地调试 BFF

在仓库内：

```bash
cd fishing_almanac/backend
npm install
npm start
```

本地 Flutter 默认 `API_BASE_URL` 为 `http://127.0.0.1:8080`（非 Web 或需显式传参时见 `lib/api/api_config.dart`）。

Web 指定后端示例：

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

---

## 9. 关键文件索引

| 文件 | 作用 |
|------|------|
| `vercel.json` | 安装/构建命令、`outputDirectory`、API rewrites |
| `scripts/vercel-install.sh` | Node + Flutter 安装与 precache |
| `scripts/vercel-build.sh` | `flutter build web`，可选 `API_BASE_URL` |
| `api/server.js` | Vercel Serverless 入口，挂载 `backend/server.js` |
| `backend/server.js` | Express 应用与 Supabase 逻辑 |
| `lib/api/api_config.dart` | 前端 `API_BASE_URL` / 同源策略 |
| `backend/vercel.json` | 仅当 Root Directory=`backend` 时使用 |

---

## 10. 官方参考

- [Vercel Project Configuration](https://vercel.com/docs/project-configuration)
- [Supabase API Settings](https://supabase.com/dashboard/project/_/settings/api)（密钥所在位置）

如有新的部署问题，建议在本文件末尾追加 **「日期 + 现象 + 原因 + 解决办法」** 一行记录，形成团队备忘。
