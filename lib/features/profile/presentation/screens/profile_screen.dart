import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/widgets/avatar_cropper_dialog.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onUpdate;

  const ProfileScreen({super.key, this.onBack, this.onUpdate});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dobController = TextEditingController();

  String _canonicalPhone = '';

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;

  String? _role;
  String _userId = '';

  // Initial data for change comparison
  String _ogFirstName = '';
  String _ogLastName = '';
  String _ogPhone = '';
  String _ogDob = '';
  String? _ogAvatarUrl;

  // New unsaved avatar bytes
  Uint8List? _newAvatarBytes;

  @override
  void initState() {
    super.initState();
    _loadProfile();

    _firstNameController.addListener(_checkForChanges);
    _lastNameController.addListener(_checkForChanges);
    _dobController.addListener(_checkForChanges);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    if (_isLoading) return;

    final fnChanges = _firstNameController.text.trim() != _ogFirstName;
    final lnChanges = _lastNameController.text.trim() != _ogLastName;
    final pChanges = _canonicalPhone.trim() != _ogPhone;
    final dChanges = _dobController.text.trim() != _ogDob;
    final avatarChanges = _newAvatarBytes != null;

    final hasChanges =
        fnChanges || lnChanges || pChanges || dChanges || avatarChanges;

    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final data = await ref.read(magicAuthServiceProvider).currentProfile();

      _userId = data.userId;
      _ogFirstName = data.firstName ?? '';
      _ogLastName = data.lastName ?? '';
      _ogPhone = data.phone ?? '';
      _ogDob = data.dob ?? '';
      _ogAvatarUrl = data.avatarFileId;
      _role = data.role;

      _firstNameController.text = _ogFirstName;
      _lastNameController.text = _ogLastName;
      _canonicalPhone = _ogPhone;
      _dobController.text = _ogDob;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final bytes = await AvatarCropperDialog.pickAndCropAvatar(context);
    if (bytes != null) {
      setState(() {
        _newAvatarBytes = bytes;
      });
      _checkForChanges();
    }
  }

  String _roleLabel(String? role) {
    return switch (role) {
      'system_admin' => 'Администратор системы',
      'admin' => 'Администратор',
      'manager' => 'Управляющий',
      'teacher' => 'Преподаватель',
      'client' => 'Клиент',
      _ => 'Клиент',
    };
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges) return;

    // Validation
    if (_firstNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Имя обязательно')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      String? updatedAvatarUrl = _ogAvatarUrl;

      // 1. Upload new avatar if picked
      if (_newAvatarBytes != null) {
        final attachments = ref.read(chatAttachmentServiceProvider);
        updatedAvatarUrl = await attachments.uploadAvatar(
          bytes: _newAvatarBytes!,
          fileName:
              'profile_${_userId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        // Clean up old avatar
        if (_ogAvatarUrl != null) {
          await attachments.deleteAvatar(_ogAvatarUrl);
        }
      }

      // 2. Update DB
      await ref
          .read(magicAuthServiceProvider)
          .updateCurrentProfile(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            phone: _canonicalPhone.trim(),
            dob: _dobController.text.trim().isEmpty
                ? null
                : _dobController.text.trim(),
            avatarFileId: updatedAvatarUrl,
          );

      // 3. Update local OG vars
      _ogFirstName = _firstNameController.text.trim();
      _ogLastName = _lastNameController.text.trim();
      _ogPhone = _canonicalPhone.trim();
      _ogDob = _dobController.text.trim();
      _ogAvatarUrl = updatedAvatarUrl;
      _newAvatarBytes = null;

      _checkForChanges();

      // 4. Invalidate global caches
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Изменения сохранены',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (widget.onUpdate != null) {
        widget.onUpdate!();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final str =
          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      _dobController.text = str;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _ProfileSkeleton();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;

    final backgroundColor = isDark
        ? TelegramColors.darkBg
        : TelegramColors.lightBg;
    final surfaceColor = isDark
        ? TelegramColors.darkSurface
        : TelegramColors.lightSurface;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark
        ? TelegramColors.darkTextSecondary
        : TelegramColors.lightTextSecondary;

    final checkmarkIcon = _isSaving
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          )
        : const Icon(Icons.check);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('Изменить профиль', style: TextStyle(fontSize: 18)),
        backgroundColor: surfaceColor,
        elevation: 0,
        actions: [
          if (!isDesktop && _hasChanges) ...[
            IconButton(
              icon: checkmarkIcon,
              onPressed: _isSaving ? null : _saveChanges,
              tooltip: 'Сохранить',
            ),
          ],
        ],
      ),
      floatingActionButton: (isDesktop && _hasChanges)
          ? FloatingActionButton(
              backgroundColor: AppTheme.primaryGold,
              onPressed: _isSaving ? null : _saveChanges,
              child: checkmarkIcon,
            )
          : null,
      body: SafeArea(
        child: ResponsiveConstraint(
          child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          children: [
            // Avatar Section
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      if (_newAvatarBytes != null)
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: MemoryImage(_newAvatarBytes!),
                        )
                      else
                        TelegramAvatar(
                          name: _ogFirstName.isNotEmpty
                              ? '$_ogFirstName $_ogLastName'
                              : 'Имя',
                          avatarUrl: _ogAvatarUrl,
                          uniqueId: _userId,
                          radius: 60,
                        ),
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withAlpha(100),
                        ),
                        child: const Icon(
                          Icons.add_a_photo_outlined,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: _pickAvatar,
                icon: const Icon(Icons.photo_camera, size: 18),
                label: const Text('Сменить фото'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryGold,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Info Section
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  _buildTelegramTextField(
                    controller: _firstNameController,
                    label: 'Имя (обязательно)',
                    textColor: textColor,
                    hintColor: secondaryTextColor,
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : Colors.black12,
                    indent: 16,
                  ),
                  _buildTelegramTextField(
                    controller: _lastNameController,
                    label: 'Фамилия (необязательно)',
                    textColor: textColor,
                    hintColor: secondaryTextColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Bio or Additional Settings
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: RuPhoneField(
                      initialCanonical: _canonicalPhone,
                      labelText: 'Номер телефона',
                      decoration: InputDecoration(
                        labelText: 'Номер телефона',
                        labelStyle: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onCanonicalChanged: (c) {
                        _canonicalPhone = c;
                        _checkForChanges();
                      },
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : Colors.black12,
                    indent: 16,
                  ),
                  _buildTelegramTextField(
                    controller: TextEditingController(text: _roleLabel(_role)),
                    label: 'Роль',
                    textColor: secondaryTextColor,
                    hintColor: secondaryTextColor,
                    readOnly: true,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: 16,
                top: 8,
                bottom: 24,
                right: 16,
              ),
              child: Text(
                'Ваш номер телефона и роль внутри платформы CRM.',
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
            ),

            // Birthday
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: const Text('День рождения'),
                subtitle: Text(
                  _dobController.text.isEmpty
                      ? 'Не указано'
                      : _dobController.text,
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _selectDate,
              ),
            ),
            const SizedBox(height: 48),

            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.login_outlined),
                    title: const Text('Способы входа'),
                    subtitle: const Text('Пароль и код из письма'),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () => context.push('/auth-methods'),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : Colors.black12,
                    indent: 16,
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Юридические документы'),
                    subtitle: const Text(
                      'Политика, соглашение и удаление данных',
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () => context.push('/legal-documents'),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : Colors.black12,
                    indent: 16,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever_outlined,
                      color: AppTheme.danger,
                    ),
                    title: const Text(
                      'Удалить аккаунт',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                    subtitle: const Text('Отправить запрос на удаление'),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () => context.push('/delete-account'),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelegramTextField({
    required TextEditingController controller,
    required String label,
    required Color textColor,
    required Color hintColor,
    bool readOnly = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        style: TextStyle(color: textColor, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: hintColor, fontSize: 14),
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? TelegramColors.darkBg
        : TelegramColors.lightBg;
    final surfaceColor = isDark
        ? TelegramColors.darkSurface
        : TelegramColors.lightSurface;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Изменить профиль', style: TextStyle(fontSize: 18)),
        backgroundColor: surfaceColor,
        elevation: 0,
      ),
      body: ResponsiveConstraint(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          children: [
            const Center(
              child: Skeleton(width: 120, height: 120, borderRadius: 60),
            ),
            const SizedBox(height: 20),
            const Center(child: Skeleton(width: 140, height: 18)),
            const SizedBox(height: 32),
            _SkeletonSection(surfaceColor: surfaceColor, rows: 2),
            const SizedBox(height: 24),
            _SkeletonSection(surfaceColor: surfaceColor, rows: 2),
            const SizedBox(height: 24),
            _SkeletonSection(surfaceColor: surfaceColor, rows: 1),
            const SizedBox(height: 48),
            _SkeletonSection(surfaceColor: surfaceColor, rows: 3),
          ],
        ),
      ),
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  final Color surfaceColor;
  final int rows;

  const _SkeletonSection({required this.surfaceColor, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: List.generate(
          rows,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: index == rows - 1 ? 0 : 16),
            child: const Row(
              children: [
                Skeleton(width: 28, height: 28, borderRadius: 14),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 130, height: 12),
                      SizedBox(height: 8),
                      Skeleton(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
