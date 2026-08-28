import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';
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
    text: 'Воронка, выручка, должники и действия команды на одном экране.',
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
  String _canonicalPhone = '';
  String? _phoneError;
  bool _isSaving = false;

  /// Presentation-only carousel cursor. `0..._obSlides.length-1` show a slide;
  /// `_obSlides.length` shows the profile form that owns `_submit()`.
  int _step = 0;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  /// Phone is valid when a canonical RU number is present.
  bool get _phoneIsValid => isCanonicalRu(_canonicalPhone);

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    final phoneValid = _phoneIsValid;
    setState(() => _phoneError = phoneValid ? null : 'Укажите номер телефона');
    if (!formValid || !phoneValid) return;

    setState(() => _isSaving = true);
    try {
      final service = ref.read(releaseGateServiceProvider);
      await service.completeOnboarding(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _canonicalPhone.trim(),
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
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить данные.'),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Matches the phone input decoration to the surrounding name fields.
  InputDecoration _phoneInputDecoration() {
    return InputDecoration(
      hintStyle: const TextStyle(color: AppColor.text2),
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
            colors: [AppColor.selectionBg, AppColor.bg],
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
              color: AppColor.surfaceActive,
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
        AuthPrimaryButton(
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
              const AppLogo(size: 92),
              const SizedBox(height: AppSpace.xs),
              const Text(
                'Заполните профиль',
                style: TextStyle(color: AppColor.text2, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          const Text(
            'Эти данные нужны школе для связи и работы системы.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColor.text2,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          AuthField(
            controller: _firstNameController,
            label: 'Имя',
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Укажите имя' : null,
          ),
          const SizedBox(height: AppSpace.lg),
          AuthField(
            controller: _lastNameController,
            label: 'Фамилия',
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.familyName],
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Укажите фамилию'
                : null,
          ),
          const SizedBox(height: AppSpace.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Номер телефона',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColor.text2,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              RuPhoneField(
                decoration: _phoneInputDecoration(),
                onCanonicalChanged: (c) {
                  _canonicalPhone = c;
                  if (_phoneError != null && _phoneIsValid) {
                    setState(() => _phoneError = null);
                  }
                },
              ),
              if (_phoneError != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  _phoneError!,
                  style: const TextStyle(color: AppColor.danger, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpace.xxl),
          AuthPrimaryButton(
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
