# Admin/User 界面隔离部署清单

本仓库已实现双入口：

- 用户端入口：`lib/main.dart`
- 管理端入口：`lib/admin/main_admin.dart`

## 1) 你需要手工完成（我无法在你线上直接操作）

1. **域名与托管分离**
   - 用户端：`app.your-domain.com`
   - 管理端：`admin.your-domain.com`
2. **分别构建并部署两套前端**
   - 用户端：`flutter build web -t lib/main.dart`
   - 管理端：`flutter build web -t lib/admin/main_admin.dart`
3. **同一 GitHub 仓库在 Vercel 上建两个 Project（根目录均为仓库根 `./`）时**
   - 根目录 [`vercel.json`](../vercel.json) 会固定 Install/Build/Output（界面里可能显示为灰显，来自配置文件），**两个 Project 可共用同一套命令**。
   - **用户端 Project**：不要设置 `FLUTTER_WEB_TARGET`（或留空），构建结果与用户端 `lib/main.dart` 一致，**与改动前行为相同**。
   - **管理端 Project**：在 Vercel → Project → Settings → Environment Variables 新增：
     - `FLUTTER_WEB_TARGET` = `admin`（触发 [`scripts/vercel-build.sh`](../scripts/vercel-build.sh) 使用 `-t lib/admin/main_admin.dart`）
     - `API_BASE_URL` = 你的 BFF 根地址（`https://...`，无末尾 `/`），便于管理端与 API 不同域名时请求打到正确后端
   - 后端 BFF 上仍需：`ADMIN_ALLOWED_ORIGINS` = 管理端站点 origin（与浏览器地址一致）。

   **Vercel 用哪份配置？（避免和 `backend/vercel.json` 搞混）**

   Vercel **只会**读取「你在该项目里设置的 Root Directory」下的 `vercel.json`，**不会**同时混用两份。

   | Vercel 里 Root Directory | 生效的文件 | 典型用途 |
   |--------------------------|------------|----------|
   | 留空或 `./`（仓库根，含 `pubspec.yaml`） | 根目录 [`vercel.json`](../vercel.json) + 本脚本 | 用户端 / 管理端 **两个** Flutter Web 项目都可设为此根目录；**仅**用环境变量 `FLUTTER_WEB_TARGET` 区分入口 |
   | `backend` | [`backend/vercel.json`](../backend/vercel.json) | **仅**部署 Node BFF（无 Flutter、`buildCommand: true`），与用户端/管理端静态站 **分开** |

4. **后端环境变量设置后台来源白名单**
   - `ADMIN_ALLOWED_ORIGINS=https://admin.your-domain.com`
   - 可多个，逗号分隔
5. **确认管理员列表**
   - `ADMIN_EMAILS` / `ADMIN_USER_IDS`

## 2) 回归测试（上线前）

1. 访问用户端，个人页不再出现“物种后台管理”入口
2. 访问管理端，必须登录后才能进入 `/admin-species`
3. 非管理员登录管理端，调用 admin API 返回 403
4. 从非白名单 Origin 调 admin API 返回 403
5. 管理端功能链路：
   - 新增物种
   - 编辑物种（含俗名替换、图片更新）
   - B→A 合并
   - 快照恢复 / 审计日志

## 3) 额外建议

- 生产环境给 `/v1/admin/*` 再加一层网关白名单/WAF
- 管理端独立监控告警（4xx/5xx）避免与用户端混在一起

