import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({this.isGate = false, super.key});

  /// When true, this screen is the app's root and must not pop on success.
  final bool isGate;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegisterMode = false;
  bool _isPasswordVisible = false;
  bool _isBusy = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isBusy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isBusy = true);

    try {
      final auth = ref.read(authServiceProvider);
      if (_isRegisterMode) {
        await auth.signUp(
          username: _usernameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }

      ref.read(guestModeProvider.notifier).state = false;
      if (mounted && !widget.isGate && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(_friendlyAuthError(error));
    } catch (_) {
      _showMessage(
        'Hesap işlemi tamamlanamadı. İnternet bağlantınızı ve Firebase ayarlarını kontrol edin.',
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final credential = await ref.read(authServiceProvider).signInWithGoogle();
      if (credential == null) return;
      ref.read(guestModeProvider.notifier).state = false;
      if (mounted && !widget.isGate && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(_friendlyAuthError(error));
    } catch (_) {
      _showMessage(
        'Google ile giriş yapılamadı. Bağlantınızı ve Firebase ayarlarınızı kontrol edin.',
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _continueAsGuest() {
    ref.read(guestModeProvider.notifier).state = true;
    if (!widget.isGate && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Önce geçerli bir e-posta adresi girin.');
      return;
    }

    setState(() => _isBusy = true);
    try {
      await ref.read(authServiceProvider).resetPassword(email);
      _showMessage('Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_friendlyAuthError(error));
    } catch (_) {
      _showMessage('Şifre sıfırlama isteği gönderilemedi. Tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => 'E-posta adresi geçerli görünmüyor.',
      'email-already-in-use' => 'Bu e-posta adresiyle kayıtlı bir hesap var.',
      'weak-password' => 'Şifreniz en az 6 karakter olmalı.',
      'user-not-found' => 'Bu e-posta adresiyle kayıtlı hesap bulunamadı.',
      'wrong-password' || 'invalid-credential' =>
        'E-posta veya şifre hatalı. Bilgilerinizi kontrol edin.',
      'user-disabled' => 'Bu hesap kullanıma kapatılmış.',
      'too-many-requests' =>
        'Çok fazla deneme yapıldı. Biraz sonra tekrar deneyin.',
      'operation-not-allowed' =>
        'E-posta/şifre girişi Firebase Console’da etkin değil.',
      'network-request-failed' =>
        'İnternet bağlantınızı kontrol edip tekrar deneyin.',
      _ => 'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('ReadToon hesabı'),
        automaticallyImplyLeading: !widget.isGate,
        leading: widget.isGate
            ? null
            : IconButton(
                tooltip: 'Geri',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: AppColors.accent,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isRegisterMode
                            ? 'Topluluğa katıl'
                            : 'Tekrar hoş geldin',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Puanlarını ve incelemelerini ReadToon topluluğuyla eşitle.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _AuthModeSelector(
                        isRegisterMode: _isRegisterMode,
                        onChanged: (value) => setState(() {
                          _isRegisterMode = value;
                          _formKey.currentState?.reset();
                        }),
                      ),
                      const SizedBox(height: 24),
                      if (_isRegisterMode) ...[
                        TextFormField(
                          controller: _usernameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.nickname],
                          decoration: const InputDecoration(
                            labelText: 'Kullanıcı adı',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (value) {
                            final username = value?.trim() ?? '';
                            if (username.length < 3) {
                              return 'Kullanıcı adı en az 3 karakter olmalı.';
                            }
                            if (username.length > 24) {
                              return 'Kullanıcı adı en fazla 24 karakter olabilir.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'E-posta',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (!email.contains('@') || email.endsWith('@')) {
                            return 'Geçerli bir e-posta adresi girin.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy ? null : _signInWithGoogle,
                          icon: const Icon(
                            Icons.g_mobiledata_rounded,
                            size: 25,
                          ),
                          label: const Text('Google ile Devam Et'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'veya e-posta ile',
                                style: TextStyle(
                                  color: AppColors.textDisabled,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        textInputAction: TextInputAction.done,
                        autofillHints: _isRegisterMode
                            ? const [AutofillHints.newPassword]
                            : const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _isPasswordVisible
                                ? 'Şifreyi gizle'
                                : 'Şifreyi göster',
                            onPressed: () => setState(
                              () => _isPasswordVisible = !_isPasswordVisible,
                            ),
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final password = value ?? '';
                          if (password.length < 6) {
                            return 'Şifre en az 6 karakter olmalı.';
                          }
                          return null;
                        },
                      ),
                      if (!_isRegisterMode)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isBusy ? null : _sendPasswordReset,
                            child: const Text('Şifremi unuttum'),
                          ),
                        )
                      else
                        const SizedBox(height: 18),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _isBusy ? null : _submit,
                          child: _isBusy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.background,
                                  ),
                                )
                              : Text(
                                  _isRegisterMode
                                      ? 'Hesap oluştur'
                                      : 'Giriş yap',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _isBusy ? null : _continueAsGuest,
                        icon: const Icon(Icons.explore_outlined, size: 19),
                        label: const Text('Konuk Olarak Devam Et'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.divider),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Konuk modunda yerel kitaplığını okuyabilir ve Keşfet’te gezebilirsin.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textDisabled,
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
    );
  }
}

class _AuthModeSelector extends StatelessWidget {
  const _AuthModeSelector({
    required this.isRegisterMode,
    required this.onChanged,
  });

  final bool isRegisterMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          _AuthModeButton(
            label: 'Giriş Yap',
            selected: !isRegisterMode,
            onTap: () => onChanged(false),
          ),
          _AuthModeButton(
            label: 'Kayıt Ol',
            selected: isRegisterMode,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _AuthModeButton extends StatelessWidget {
  const _AuthModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.accent : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
