# fishing_almanac BFF (Supabase-backed)

这个后端实现了你 Flutter 前端里写死的 API 契约：

- `POST /auth/login`
- `POST /auth/register`
- `GET /me`
- `PATCH /me`
- `GET /v1/catches`
- `POST /v1/catches`（multipart，字段名默认 `image`）
- `PUT /v1/catches/:id`
- `POST /v1/species/identify`（当前为 stub）

数据使用 Supabase Postgres（`fishing_almanac/supabase/migrations/0001_init.sql` 创建的表）。
为降低配置复杂度，当前把图片用 `image_base64` 存入数据库（不依赖 Storage bucket）。

## 运行（本地开发）
1. 配好 `backend/.env`（见 `backend/.env.example`）
2. 在 `backend/` 执行：
   - `npm i`
   - `npm run dev`
3. Flutter 侧使用：
   - `--dart-define=API_BASE_URL=http://localhost:8080`
   - 打开联调开关：
     - `--dart-define=USE_REMOTE_CATCH_REPOSITORY=true`
     - `--dart-define=USE_REMOTE_SPECIES_IDENTIFICATION=true`

## Supabase 额外要求
- 确保 Supabase 启用了 `Email and Password` 认证方式。
- 即使 Supabase 保持开启邮箱验证，本后端 `POST /auth/register` 也会直接使用 `admin.createUser({ email_confirm: true })` 来跳过验证流程，并立即用邮箱/密码签入拿到 token。

