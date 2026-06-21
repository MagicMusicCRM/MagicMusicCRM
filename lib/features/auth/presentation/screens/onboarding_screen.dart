// The shared v7 auth helpers (_V7Field / _V7PrimaryButton) are pasted
// byte-for-byte identically across all 6 auth screens per the v7 spec, so a
// few of their parameters are intentionally unused on this particular screen.
// ignore_for_file: unused_element_parameter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

/// One v7 onboarding slide (presentation-only — no service binding).
class _ObSlide {
  const _ObSlide({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;
}

const List<_ObSlide> _obSlides = [
  _ObSlide(
    icon: Icons.groups_outlined,
    title: 'Все клиенты в одном месте',
    text:
        'Лиды и ученики на доске с перетаскиванием, фильтрами и историей касаний.',
  ),
  _ObSlide(
    icon: Icons.calendar_month_outlined,
    title: 'Расписание без накладок',
    text:
        'Год → месяц → день. Залы, преподаватели, переносы и отметка посещаемости.',
  ),
  _ObSlide(
    icon: Icons.insights_outlined,
    title: 'Аналитика и финансы',
    text:
        'Воронка, выручка, должники и аудит действий команды — на одном экране.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;

  /// Presentation-only carousel cursor. `0..._obSlides.length-1` show a slide;
  /// `_obSlides.length` shows the profile form that owns `_submit()`.
  int _step = 0;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final service = ref.read(releaseGateServiceProvider);
      await service.completeOnboarding(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      try {
        await service.ensureAdminChatThread();
      } catch (error) {
        debugPrint('Не удалось создать чат администрации: $error');
      }
      ref.invalidate(releaseGateStatusProvider);

      if (mounted) context.go('/legal-consent');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось сохранить данные: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _nextSlide() {
    setState(() => _step += 1);
  }

  void _skipSlides() {
    setState(() => _step = _obSlides.length);
  }

  @override
  Widget build(BuildContext context) {
    final showForm = _step >= _obSlides.length;

    return Scaffold(
      backgroundColor: AppColor.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -1.0),
            radius: 1.1,
            colors: [Color(0x1AC5A059), AppColor.bg],
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.xxl,
                  vertical: 30,
                ),
                child: showForm ? _buildForm() : _buildSlide(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlide() {
    final slide = _obSlides[_step];
    final isLast = _step == _obSlides.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2418), Color(0xFF1D1A12)],
              ),
              border: Border.all(color: AppColor.goldLine),
            ),
            child: Icon(slide.icon, color: AppColor.gold, size: 40),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        Text(
          slide.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColor.text,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          slide.text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColor.text2,
            fontSize: 13.5,
            height: 1.55,
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        _ObDots(count: _obSlides.length, active: _step),
        const SizedBox(height: AppSpace.xl),
        _V7PrimaryButton(
          label: isLast ? 'Продолжить' : 'Далее',
          icon: Icons.arrow_forward,
          onPressed: _nextSlide,
        ),
        if (!isLast) ...[
          const SizedBox(height: AppSpace.sm),
          Center(
            child: TextButton(
              onPressed: _skipSlides,
              style: TextButton.styleFrom(
                foregroundColor: AppColor.gold,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                padding: const EdgeInsets.all(AppSpace.sm),
                minimumSize: const Size(0, 0),
              ),
              child: const Text('Пропустить'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2A2418), Color(0xFF1D1A12)],
                  ),
                  border: Border.all(color: AppColor.goldLine),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: AppColor.gold,
                  size: 30,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Magic',
                      style: TextStyle(
                        color: AppColor.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 21,
                        letterSpacing: -0.4,
                      ),
                    ),
                    TextSpan(
                      text: 'Music',
                      style: TextStyle(
                        color: AppColor.gold,
                        fontWeight: FontWeight.w800,
                        fontSize: 21,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              const Text(
                'Заполните профиль',
                style: TextStyle(color: AppColor.text2, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          const Text(
            'Эти данные нужны школе для связи и корректной работы CRM.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColor.text2,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          _V7Field(
            controller: _firstNameController,
            label: 'Имя',
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Укажите имя' : null,
          ),
          const SizedBox(height: AppSpace.lg),
          _V7Field(
            controller: _lastNameController,
            label: 'Фамилия',
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.familyName],
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Укажите фамилию'
                : null,
          ),
          const SizedBox(height: AppSpace.lg),
          _V7Field(
            controller: _phoneController,
            label: 'Номер телефона',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            validator: (value) => value == null || value.trim().length < 6
                ? 'Укажите номер телефона'
                : null,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpace.xxl),
          _V7PrimaryButton(
            label: 'Продолжить',
            icon: Icons.arrow_forward,
            loading: _isSaving,
            onPressed: _isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// v7 onboarding pagination dots (`.ob-dots` / `.ob-dot`).
class _ObDots extends StatelessWidget {
  const _ObDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.ease,
            width: i == active ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == active ? AppColor.gold : AppColor.divider,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ],
      ],
    );
  }
}

class _V7Field extends StatelessWidget {
  const _V7Field({
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.autocorrect = true,
    this.suffix,
    this.validator,
    this.inputFormatters,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final bool autocorrect;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColor.text2),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColor.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.goldLine, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.divider),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.danger, width: 2),
      ),
    );

    final field = (validator != null)
        ? TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            enabled: enabled,
            autocorrect: autocorrect,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onFieldSubmitted: onSubmitted,
            style: const TextStyle(color: AppColor.text),
            decoration: decoration,
            validator: validator,
          )
        : TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            enabled: enabled,
            autocorrect: autocorrect,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onSubmitted: onSubmitted,
            style: const TextStyle(color: AppColor.text),
            decoration: decoration,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColor.text2,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        field,
      ],
    );
  }
}

class _V7PrimaryButton extends StatelessWidget {
  const _V7PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1.0 : 0.42,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Material(
          color: AppColor.gold,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColor.onGold,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 17, color: AppColor.onGold),
                          const SizedBox(width: AppSpace.sm),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColor.onGold,
                          ),
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
