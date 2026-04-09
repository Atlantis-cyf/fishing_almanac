import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/auth/auth_repository.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';
import 'package:fishing_almanac/api/api_client.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
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
      await context.read<AuthRepository>().login(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;

      // Double-check admin permission after login.
      await context.read<ApiClient>().get<dynamic>(AdminSpeciesEndpoints.list, queryParameters: const {'status': 'all'});
      if (!mounted) return;

      final next = GoRouterState.of(context).uri.queryParameters['redirect'];
      if (next != null && next.startsWith('/')) {
        context.go(next);
      } else {
        context.go('/admin-species');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.statusCode == 403 ? '当前账号没有后台管理权限' : e.message;
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
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('后台管理登录', style: AppFont.manrope(fontWeight: FontWeight.w800, fontSize: 30)),
                  const SizedBox(height: 6),
                  Text('仅管理员可访问', style: TextStyle(color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: '邮箱'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入邮箱' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: '密码'),
                    obscureText: true,
                    validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录后台'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

