import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

const int emailOtpCodeLength = 6;

enum EmailOtpPurpose { signup, passwordMfa }

class EmailOtpRouteData {
  final String email;
  final EmailOtpPurpose purpose;

  const EmailOtpRouteData({required this.email, required this.purpose});
}

class EmailOtpScreen extends ConsumerStatefulWidget {
  final EmailOtpRouteData data;

  const EmailOtpScreen({super.key, required this.data});

  @override
  ConsumerState<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends ConsumerState<EmailOtpScreen> {
  final _codeController = TextEditingController();
  // v7: 6 separate OTP boxes are a view layer that writes the joined digits
  // back into [_codeController] — the locked verify path still reads it.
  final List<TextEditingController> _boxControllers = List.generate(
    emailOtpCodeLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _boxFocusNodes = List.generate(
    emailOtpCodeLength,
    (_) => FocusNode(),
  );
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    for (final controller in _boxControllers) {
      controller.dispose();
    }
    for (final node in _boxFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Recompute [_codeController] from the 6 boxes after any edit.
  void _syncCode() {
    _codeController.text = _boxControllers.map((c) => c.text).join();
  }

  void _onBoxChanged(int index, String value) {
    if (value.isNotEmpty && index < emailOtpCodeLength - 1) {
      FocusScope.of(context).requestFocus(_boxFocusNodes[index + 1]);
    }
    _syncCode();
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    } else {
      setState(() {});
    }
    final joined = _codeController.text.trim();
    if (joined.length == emailOtpCodeLength && !_isLoading) {
      _verifyCode();
    }
  }

  KeyEventResult _onBoxKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _boxControllers[index].text.isEmpty &&
        index > 0) {
      _boxControllers[index - 1].clear();
      FocusScope.of(context).requestFocus(_boxFocusNodes[index - 1]);
      _syncCode();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != emailOtpCodeLength) {
      _showError('Введите 6 цифр из письма');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final service = ref.read(magicAuthServiceProvider);
      if (widget.data.purpose == EmailOtpPurpose.signup) {
        await service.verifySignupOtp(email: widget.data.email, token: code);
        if (mounted) context.go('/login');
      } else {
        final response = await service.verifyEmailOtp(
          email: widget.data.email,
          token: code,
        );
        if (mounted) {
          if (!response.hasSession) {
            _showError('Не удалось завершить вход. Запросите новый код.');
          } else {
            context.go('/');
          }
        }
      }
    } on MagicApiException catch (error) {
      if (mounted) _showError(_mapAuthError(error.message));
    } catch (_) {
      if (mounted) _showError('Не удалось проверить код.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(magicAuthServiceProvider);
      if (widget.data.purpose == EmailOtpPurpose.signup) {
        await service.resendSignupOtp(email: widget.data.email);
      } else {
        await service.sendEmailOtp(
          email: widget.data.email,
          shouldCreateUser: false,
        );
      }
      if (mounted) {
        MagicToast.show(
          context,
          'Новый код отправлен на почту',
          type: MagicToastType.success,
        );
      }
    } on MagicApiException catch (error) {
      if (mounted) _showError(_mapAuthError(error.message));
    } catch (_) {
      if (mounted) _showError('Не удалось отправить новый код.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(String message) {
    if (message.contains('Token has expired')) {
      return 'Код истек. Запросите новый.';
    }
    if (message.contains('Invalid token')) {
      return 'Неверный код.';
    }
    if (message.contains('Too many requests')) {
      return 'Слишком много попыток. Подождите немного.';
    }
    return message;
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = 'Подтверждение кода';
    final description = switch (widget.data.purpose) {
      EmailOtpPurpose.signup =>
        'Мы отправили код подтверждения регистрации на\n${widget.data.email}',
      EmailOtpPurpose.passwordMfa =>
        'Мы отправили одноразовый код входа на\n${widget.data.email}',
    };

    return Scaffold(
      backgroundColor: AppColor.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -1.0),
            radius: 1.1,
            colors: [AppColor.selectionBg, AppColor.bg],
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: ResponsiveConstraint(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.xxl,
                    vertical: 30,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBrand(subtitle),
                      const SizedBox(height: AppSpace.xxl),
                      _buildDescription(description),
                      const SizedBox(height: AppSpace.lg),
                      _buildOtpBoxes(),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: AppSpace.lg),
                        _buildErrorPill(_errorMessage!),
                      ],
                      const SizedBox(height: AppSpace.lg),
                      AuthPrimaryButton(
                        label: 'Подтвердить',
                        loading: _isLoading,
                        onPressed: _isLoading ? null : _verifyCode,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      _buildResendRow(),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColor.gold,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.all(AppSpace.sm),
                          minimumSize: const Size(0, 0),
                        ),
                        child: const Text('Назад ко входу'),
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

  Widget _buildBrand(String subtitle) {
    return Column(
      children: [
        const AppLogo(size: 84),
        const SizedBox(height: AppSpace.xs),
        Text(
          subtitle,
          style: const TextStyle(color: AppColor.text2, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _buildDescription(String description) {
    // The description is "lead\nemail"; bold the email substring per .auth-note.
    final parts = description.split('\n');
    final lead = parts.first;
    final email = parts.length > 1 ? parts.sublist(1).join('\n') : '';

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: email.isEmpty ? lead : '$lead\n'),
          if (email.isNotEmpty)
            TextSpan(
              text: email,
              style: const TextStyle(
                color: AppColor.menuItemText,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppColor.text2,
        fontSize: 12.5,
        height: 1.5,
      ),
    );
  }

  Widget _buildOtpBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < emailOtpCodeLength; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.sm),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 50),
              child: SizedBox(
                height: 54,
                child: Focus(
                  onKeyEvent: (node, event) => _onBoxKey(i, event),
                  child: TextField(
                    controller: _boxControllers[i],
                    focusNode: _boxFocusNodes[i],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      color: AppColor.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    onChanged: (value) => _onBoxChanged(i, value),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: AppColor.input,
                      contentPadding: EdgeInsets.zero,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: const BorderSide(color: AppColor.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: const BorderSide(
                          color: AppColor.goldLine,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorPill(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        border: Border.all(color: AppColor.danger),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColor.danger, fontSize: 12),
      ),
    );
  }

  Widget _buildResendRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Не получили код?',
          style: TextStyle(color: AppColor.text2, fontSize: 13),
        ),
        TextButton(
          onPressed: _isLoading ? null : _resendCode,
          style: TextButton.styleFrom(
            foregroundColor: AppColor.gold,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.all(AppSpace.sm),
            minimumSize: const Size(0, 0),
          ),
          child: const Text('Отправить снова'),
        ),
      ],
    );
  }
}
