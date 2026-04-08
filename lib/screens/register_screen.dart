import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/repositories/persistence_exception.dart';
import 'package:fishing_almanac/auth/auth_repository.dart';
import 'package:fishing_almanac/state/user_profile.dart';
import 'package:fishing_almanac/data/image_urls.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      final loggedIn = await context.read<AuthRepository>().register(
            username: _username.text,
            email: _email.text,
            password: _password.text,
          );
      if (!mounted) return;
      if (loggedIn) {
        await context.read<UserProfile>().syncFromServer();
        context.read<AnalyticsClient>().trackFireAndForget(
              'auth_register_success',
              properties: <String, dynamic>{
                'logged_in': true,
                'email_domain': (() {
                  final s = _email.text.trim();
                  final parts = s.split('@');
                  if (parts.length == 2) return parts[1];
                  return 'unknown';
                })(),
              },
            );
        if (!mounted) return;
      }
      setState(() => _loading = false);
      if (loggedIn) {
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('注册成功，请登录')),
        );
        context.read<AnalyticsClient>().trackFireAndForget(
              'auth_register_success',
              properties: <String, dynamic>{
                'logged_in': false,
              },
            );
        context.go('/login');
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
          Positioned.fill(
            child: Image.network(
              ImageUrls.registerBg,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0b1326),
                  AppColors.surfaceContainerLowest.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF22d3ee)),
                      ),
                      Text(
                        'DEEP SEA',
                        style: AppFont.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF22d3ee),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
                            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.15)),
                            boxShadow: const [BoxShadow(blurRadius: 40, color: Colors.black54)],
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '注册新观察员',
                                  style: AppFont.manrope(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '加入深海航行，记录未知的海洋奇迹',
                                  style: TextStyle(
                                    color: AppColors.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                if (_error != null)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorContainer.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _error!,
                                            style: const TextStyle(color: AppColors.error, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                _LabeledField(
                                  label: '用户名',
                                  icon: Icons.person_outline,
                                  hint: '输入您的观察员代号',
                                  controller: _username,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return '请输入用户名';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),
                                _LabeledField(
                                  label: '电子邮箱',
                                  icon: Icons.mail_outline,
                                  hint: 'example@abyssal.com',
                                  keyboard: TextInputType.emailAddress,
                                  controller: _email,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return '请输入邮箱';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),
                                _LabeledField(
                                  label: '设置密码',
                                  icon: Icons.lock_outline,
                                  hint: '••••••••',
                                  obscure: true,
                                  controller: _password,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return '请输入密码';
                                    if (v.length < 6) return '密码至少 6 位';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),
                                _LabeledField(
                                  label: '确认密码',
                                  icon: Icons.lock_person_outlined,
                                  hint: '再次输入密码',
                                  obscure: true,
                                  controller: _confirmPassword,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return '请再次输入密码';
                                    if (v != _password.text) return '两次输入的密码不一致';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _loading ? null : _submit,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 20),
                                      backgroundColor: AppColors.primaryContainer,
                                      foregroundColor: AppColors.onPrimaryContainer,
                                      shape: const RoundedRectangleBorder(),
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
                                                '开启深海之旅',
                                                style: AppFont.manrope(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(Icons.arrow_forward),
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.icon,
    required this.hint,
    required this.controller,
    this.keyboard,
    this.obscure = false,
    this.validator,
  });

  final String label;
  final IconData icon;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final bool obscure;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          validator: validator,
          style: const TextStyle(color: AppColors.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.outline),
            filled: true,
            fillColor: AppColors.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(0),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(0),
              borderSide: const BorderSide(color: AppColors.primaryContainer),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
        ),
      ],
    );
  }
}
