import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/repositories/persistence_exception.dart';
import 'package:fishing_almanac/auth/auth_repository.dart';
import 'package:fishing_almanac/data/image_urls.dart';
import 'package:fishing_almanac/state/catch_draft.dart';
import 'package:fishing_almanac/state/user_profile.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/widgets/app_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _showEditDisplayName(BuildContext context, UserProfile profile) async {
    final c = TextEditingController(text: profile.displayName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('修改用户名', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(color: AppColors.onSurface),
          decoration: InputDecoration(
            hintText: '首页横幅将显示此名称',
            hintStyle: TextStyle(color: AppColors.onSurfaceVariant.withValues(alpha: 0.6)),
            filled: true,
            fillColor: AppColors.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await profile.setDisplayName(c.text);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('昵称已保存')),
          );
        }
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      } on PersistenceException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
    }
    c.dispose();
  }

  Future<void> _showChangePassword(BuildContext context, UserProfile profile) async {
    final current = TextEditingController();
    final n1 = TextEditingController();
    final n2 = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceContainerHigh,
          title: Text('修改密码', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (profile.hasPassword) ...[
                  TextField(
                    controller: current,
                    obscureText: true,
                    style: const TextStyle(color: AppColors.onSurface),
                    decoration: const InputDecoration(labelText: '原密码'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: n1,
                  obscureText: true,
                  style: const TextStyle(color: AppColors.onSurface),
                  decoration: const InputDecoration(
                    labelText: '新密码',
                    helperText: '至少 6 位',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: n2,
                  obscureText: true,
                  style: const TextStyle(color: AppColors.onSurface),
                  decoration: const InputDecoration(labelText: '确认新密码'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                try {
                  await profile.changePassword(
                    newPassword: n1.text,
                    confirmPassword: n2.text,
                    currentPassword: profile.hasPassword ? current.text : null,
                  );
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('密码已更新')),
                    );
                  }
                } on PersistenceException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                } catch (e) {
                  final msg = e is StateError ? e.message : '$e';
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  }
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    current.dispose();
    n1.dispose();
    n2.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<UserProfile>(
          builder: (context, profile, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back, color: AppColors.cyanNav),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 128,
                        height: 128,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryContainer, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryContainer.withValues(alpha: 0.35),
                              blurRadius: 15,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: AppNetworkImage(url: ImageUrls.profileAvatar, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: FloatingActionButton.small(
                          onPressed: () {},
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimaryContainer,
                          child: const Icon(Icons.edit, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '船员档案',
                    style: GoogleFonts.manrope(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryFixed.withValues(alpha: 0.1),
                        ),
                        child: Text(
                          '状态：在线',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: AppColors.secondaryFixed,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '编号: ABYSS-9920-X',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '账户详情',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: AppColors.surfaceContainerLow,
                    child: InkWell(
                      onTap: () => _showEditDisplayName(context, profile),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          border: Border(left: BorderSide(color: AppColors.primaryContainer, width: 2)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '用户名',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    profile.displayName,
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.edit_outlined, size: 18, color: AppColors.primary.withValues(alpha: 0.4)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      border: const Border(left: BorderSide(color: AppColors.outlineVariant, width: 2)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '电子邮箱',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                profile.email,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.lock, size: 18, color: AppColors.onSurfaceVariant),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '安全设置',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      border: Border(
                        top: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.1)),
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.password, color: AppColors.primaryContainer),
                      title: const Text('修改密码'),
                      subtitle: profile.hasPassword
                          ? Text('已设置本地密码', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant))
                          : const Text('首次设置需输入两次新密码', style: TextStyle(fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
                      onTap: () => _showChangePassword(context, profile),
                    ),
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: () async {
                      await context.read<AuthRepository>().logout();
                      await context.read<UserProfile>().onSessionEnded();
                      if (!context.mounted) return;
                      context.read<CatchDraft>().clearForNewRecord();
                      context.go('/login');
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withValues(alpha: 0.3), width: 2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.logout),
                        const SizedBox(width: 8),
                        Text(
                          '退出登录 (断开连接)',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, letterSpacing: 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '版本 4.2.0-稳定版 // 加密连接',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
