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
3. **后端环境变量设置后台来源白名单**
   - `ADMIN_ALLOWED_ORIGINS=https://admin.your-domain.com`
   - 可多个，逗号分隔
4. **确认管理员列表**
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

