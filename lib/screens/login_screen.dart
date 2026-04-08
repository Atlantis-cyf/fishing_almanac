import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/repositories/persistence_exception.dart';
import 'package:fishing_almanac/auth/auth_repository.dart';
import 'package:fishing_almanac/router/feed_detail_route_args.dart';
import 'package:fishing_almanac/state/user_profile.dart';
import 'package:fishing_almanac/data/image_urls.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthRepository>().login(
            email: _email.text,
            password: _password.text,
          );
      if (!mounted) return;
      await context.read<UserProfile>().syncFromServer();
      if (!mounted) return;
      context.read<AnalyticsClient>().trackFireAndForget(
            'auth_login_success',
            properties: <String, dynamic>{
              'email_domain': (() {
                final s = _email.text.trim();
                final parts = s.split('@');
                if (parts.length == 2) return parts[1];
                return 'unknown';
              })(),
            },
          );
      if (!mounted) return;
      setState(() => _loading = false);
      final next = sanitizePostLoginRedirectQuery(
        GoRouterState.of(context).uri.queryParameters['redirect'],
      );
      if (next != null) {
        context.go(next);
      } else {
        context.go('/home');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } on PersistenceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            ImageUrls.loginBg,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppColors.surface),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.surface.withValues(alpha: 0.4),
                  AppColors.surface.withValues(alpha: 0.85),
                  AppColors.surface,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      Text(
                        '海钓图鉴',
                        textAlign: TextAlign.center,
                        style: AppFont.manrope(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          shadows: [
                            Shadow(
                              color: AppColors.primaryContainer.withValues(alpha: 0.4),
                              blurRadius: 15,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '深海观察员 — 探索深海奥秘，记录每一次伟大捕获',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 36),
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222a3d).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black54)],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('登录', style: AppFont.manrope(fontSize: 24, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(
                                '验证您的身份以进入系统',
                                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
                              ),
                              const SizedBox(height: 24),
                              if (_error != null)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: AppColors.errorContainer.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ),
                              Text(
                                '电子邮箱',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w500),
                                decoration: _inputDecoration(
                                  hint: 'your@email.com',
                                  icon: Icons.alternate_email,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return '请输入邮箱';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '密码',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {},
                                    child: Text(
                                      '忘记密码？',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _password,
                                obscureText: true,
                                style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w500),
                                decoration: _inputDecoration(
                                  hint: '••••••••',
                                  icon: Icons.lock_outline,
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return '请输入密码';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _loading ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    backgroundColor: AppColors.primaryContainer,
                                    foregroundColor: AppColors.onPrimary,
                                    shape: const StadiumBorder(),
                                  ),
                                  child: _loading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '登录',
                                              style: AppFont.manrope(
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 3,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.arrow_forward, size: 20),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Center(
                                child: Text.rich(
                                  TextSpan(
                                    text: '新观察员？ ',
                                    style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
                                    children: [
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.baseline,
                                        baseline: TextBaseline.alphabetic,
                                        child: GestureDetector(
                                          onTap: () => context.push('/register'),
                                          child: Text(
                                            '注册账号',
                                            style: TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w700,
                                              decoration: TextDecoration.underline,
                                              decorationColor: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.outline.withValues(alpha: 0.5)),
      prefixIcon: Icon(icon, color: AppColors.primary.withValues(alpha: 0.7)),
      filled: true,
      fillColor: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: AppColors.primaryContainer.withValues(alpha: 0.5)),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
    );
  }
}
