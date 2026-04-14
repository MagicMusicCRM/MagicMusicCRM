import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/widgets/avatar_cropper_dialog.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onUpdate;

  const ProfileScreen({super.key, this.onBack, this.onUpdate});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;
  
  String? _role;

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
    _phoneController.addListener(_checkForChanges);
    _dobController.addListener(_checkForChanges);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    if (_isLoading) return;
    
    final fnChanges = _firstNameController.text.trim() != _ogFirstName;
    final lnChanges = _lastNameController.text.trim() != _ogLastName;
    final pChanges = _phoneController.text.trim() != _ogPhone;
    final dChanges = _dobController.text.trim() != _ogDob;
    final avatarChanges = _newAvatarBytes != null;

    final hasChanges = fnChanges || lnChanges || pChanges || dChanges || avatarChanges;
    
    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase.from('profiles').select().eq('id', user.id).single();

      _ogFirstName = data['first_name'] ?? '';
      _ogLastName = data['last_name'] ?? '';
      _ogPhone = data['phone'] ?? '';
      _ogDob = data['dob'] ?? '';
      _ogAvatarUrl = data['avatar_url']?.toString();
      _role = data['role']?.toString();

      _firstNameController.text = _ogFirstName;
      _lastNameController.text = _ogLastName;
      _phoneController.text = _ogPhone;
      _dobController.text = _ogDob;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
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

  Future<void> _saveChanges() async {
    if (!_hasChanges) return;
    
    // Validation
    if (_firstNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя обязательно')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      String? updatedAvatarUrl = _ogAvatarUrl;

      // 1. Upload new avatar if picked
      if (_newAvatarBytes != null) {
        updatedAvatarUrl = await ChatAttachmentService.uploadAvatar(
          bytes: _newAvatarBytes!,
          fileName: 'profile_${user.id}_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        // Clean up old avatar
        if (_ogAvatarUrl != null) {
          await ChatAttachmentService.deleteAvatar(_ogAvatarUrl);
        }
      }

      // 2. Update DB
      await _supabase.from('profiles').update({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'dob': _dobController.text.trim().isEmpty ? null : _dobController.text.trim(),
        if (_newAvatarBytes != null) 'avatar_url': updatedAvatarUrl,
      }).eq('id', user.id);

      // 3. Update local OG vars
      _ogFirstName = _firstNameController.text.trim();
      _ogLastName = _lastNameController.text.trim();
      _ogPhone = _phoneController.text.trim();
      _ogDob = _dobController.text.trim();
      _ogAvatarUrl = updatedAvatarUrl;
      _newAvatarBytes = null;
      
      _checkForChanges();

      // 4. Invalidate global caches
      ref.invalidate(currentProfileProvider);
      ref.invalidate(allProfilesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Изменения сохранены', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green,
        ));
      }

      if (widget.onUpdate != null) {
        widget.onUpdate!();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: AppTheme.danger));
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
      final str = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      _dobController.text = str;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;

    final backgroundColor = isDark ? TelegramColors.darkBg : TelegramColors.lightBg;
    final surfaceColor = isDark ? TelegramColors.darkSurface : TelegramColors.lightSurface;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary;

    final checkmarkIcon = _isSaving 
        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : const Icon(Icons.check);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        leading: widget.onBack != null 
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
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
          ]
        ],
      ),
      floatingActionButton: (isDesktop && _hasChanges) 
        ? FloatingActionButton(
            backgroundColor: AppTheme.primaryGold,
            onPressed: _isSaving ? null : _saveChanges,
            child: checkmarkIcon,
          )
        : null,
      body: ResponsiveConstraint(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          children: [
            // Avatar Section
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_newAvatarBytes != null)
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: MemoryImage(_newAvatarBytes!),
                      )
                    else
                      TelegramAvatar(
                        name: _ogFirstName.isNotEmpty ? '$_ogFirstName $_ogLastName' : 'Имя',
                        avatarUrl: _ogAvatarUrl,
                        uniqueId: _supabase.auth.currentUser?.id ?? '',
                        radius: 60,
                      ),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withAlpha(100),
                      ),
                      child: const Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 36),
                    ),
                  ],
                ),
              ),
            ),
              const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: _pickAvatar,
                icon: const Icon(Icons.photo_camera, size: 18),
                label: const Text('Сменить фото'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryGold),
              ),
            ),
              const SizedBox(height: 32),

              // Info Section
              Container(
                decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    _buildTelegramTextField(
                      controller: _firstNameController,
                      label: 'Имя (обязательно)',
                      textColor: textColor,
                      hintColor: secondaryTextColor,
                    ),
                    Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 16),
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
                decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    _buildTelegramTextField(
                      controller: _phoneController,
                      label: 'Номер телефона',
                      textColor: textColor,
                      hintColor: secondaryTextColor,
                      keyboardType: TextInputType.phone,
                    ),
                    Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 16),
                    _buildTelegramTextField(
                      controller: TextEditingController(text: _role == 'client' ? 'Ученик' : _role),
                      label: 'Роль',
                      textColor: secondaryTextColor,
                      hintColor: secondaryTextColor,
                      readOnly: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8, bottom: 24, right: 16),
                child: Text(
                  'Ваш номер телефона и роль внутри платформы CRM.',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
              ),

              // Birthday
              Container(
                decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const Icon(Icons.card_giftcard),
                  title: const Text('День рождения'),
                  subtitle: Text(_dobController.text.isEmpty ? 'Не указано' : _dobController.text),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _selectDate,
                ),
              ),
            const SizedBox(height: 48),
          ],
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
