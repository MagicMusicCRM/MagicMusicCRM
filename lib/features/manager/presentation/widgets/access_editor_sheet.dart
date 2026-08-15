import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/access_management.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class AccessEditorSheet extends ConsumerStatefulWidget {
  const AccessEditorSheet({
    super.key,
    required this.actorRole,
    required this.userId,
    required this.userLabel,
    this.dataSource,
    this.onChanged,
    this.embedded = false,
  });

  final String actorRole;
  final String userId;
  final String userLabel;
  final AccessManagementDataSource? dataSource;
  final VoidCallback? onChanged;
  final bool embedded;

  static Future<void> show(
    BuildContext context, {
    required String actorRole,
    required String userId,
    required String userLabel,
    VoidCallback? onChanged,
  }) async {
    final link = EntityLink.typed(
      entityType: EntityLinkType.user,
      entityId: userId,
      optionalFocus: EntityLinkFocus(focus: 'permissions'),
      presentation: EntityPresentationReference(primary: userLabel),
    );
    final container = ProviderScope.containerOf(context, listen: false);
    final snapshot = await container.read(capabilitySnapshotProvider.future);
    if (!context.mounted) return;
    await navigateEntityLink(context, snapshot, link);
  }

  @override
  ConsumerState<AccessEditorSheet> createState() => _AccessEditorSheetState();
}

class _AccessEditorSheetState extends ConsumerState<AccessEditorSheet> {
  final _reasonController = TextEditingController(text: 'access.review');
  ManagedUserAccess? _access;
  Object? _loadError;
  String? _message;
  String? _selectedRole;
  bool _resetConfirmed = false;
  bool _pending = false;
  MagicMutationIdentity? _roleIdentity;
  final Map<String, MagicMutationIdentity> _overrideIdentities = {};

  AccessManagementDataSource get _source =>
      widget.dataSource ?? ref.read(accessManagementServiceProvider);

  bool get _isRoot => widget.actorRole == 'system_admin';

  static const _roleLabels = {
    'client': 'Клиент',
    'teacher': 'Преподаватель',
    'admin': 'Администратор',
    'manager': 'Управляющий',
    'director': 'Директор',
    'system_admin': 'Администратор системы',
  };

  static const _capabilityLabels = {
    'access.user.role.assign': 'Назначение ролей',
    'access.user.override.manage': 'Персональные права',
    'crm.client.read.basic': 'Просмотр клиентов',
    'crm.client.read.contacts': 'Контакты клиентов',
    'crm.client.write': 'Изменение клиентов',
    'crm.comment.read.shared': 'Общие комментарии',
    'schedule.lesson.read.assigned': 'Просмотр расписания',
    'schedule.lesson.write': 'Изменение расписания',
    'schedule.attendance.write': 'Изменение посещаемости',
    'schedule.lesson.complete': 'Завершение занятий',
    'commerce.client_finance.read': 'Финансы карточки клиента',
    'commerce.school_finance.read': 'Финансы всей школы',
    'commerce.package.read': 'Просмотр каталога',
    'commerce.package.manage': 'Управление каталогом',
    'commerce.subscription.issue': 'Выдача абонементов',
    'workflow.task.read': 'Просмотр задач',
    'workflow.task.write': 'Изменение задач',
    'report.status.read': 'Управленческие отчёты',
    'report.export.xlsx': 'Экспорт отчётов',
    'config.crm.read': 'Просмотр настроек системы',
    'config.crm.edit': 'Редактирование настроек системы',
    'config.crm.publish': 'Публикация настроек системы',
    'system.settings.manage': 'Системные настройки',
  };

  @override
  void initState() {
    super.initState();
    if (widget.actorRole == 'director' || widget.actorRole == 'system_admin') {
      _load();
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load({bool clearMessage = true}) async {
    setState(() {
      _loadError = null;
      if (clearMessage) _message = null;
    });
    try {
      final access = await _source.getUserAccess(widget.userId);
      if (!mounted) return;
      setState(() {
        _access = access;
        _selectedRole = access.role;
        _resetConfirmed = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  List<String> _assignableRoles(ManagedUserAccess access) {
    if (_isRoot) {
      return const [
        'client',
        'teacher',
        'admin',
        'manager',
        'director',
        'system_admin',
      ];
    }
    return const ['client', 'teacher', 'admin', 'manager'];
  }

  String? _validatedReason() {
    final value = _reasonController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,120}$').hasMatch(value)) {
      setState(() => _message = 'Выберите причину изменения.');
      return null;
    }
    return value;
  }

  Future<void> _saveRole() async {
    final access = _access;
    final role = _selectedRole;
    if (access == null || role == null || role == access.role || _pending) {
      return;
    }
    final reason = _validatedReason();
    if (reason == null) return;
    if (!_resetConfirmed) {
      setState(
        () => _message = 'Подтвердите сброс персональных настроек доступа.',
      );
      return;
    }
    final identity = _roleIdentity ??= MagicMutationIdentity.create(
      'access-role',
    );
    await _mutate(() {
      return _source.assignRole(
        userId: access.userId,
        role: role,
        expectedVersion: access.accessVersion,
        resetOverridesConfirmed: true,
        emergencySurface: _isRoot,
        reasonCode: reason,
        identity: identity,
      );
    }, staleIdentity: () => _roleIdentity = null);
  }

  Future<void> _setCapability(
    ManagedCapability capability,
    bool allowed,
  ) async {
    final access = _access;
    if (access == null || _pending) return;
    if (allowed && !capability.canAllow) return;
    if (!allowed && !capability.canDeny) return;
    final reason = _validatedReason();
    if (reason == null) return;
    final identity = _overrideIdentities.putIfAbsent(
      capability.key,
      () => MagicMutationIdentity.create('access-override'),
    );
    await _mutate(() {
      return _source.setOverride(
        userId: access.userId,
        capabilityKey: capability.key,
        effect: allowed ? 'allow' : 'deny',
        expectedVersion: access.accessVersion,
        emergencySurface: _isRoot,
        reasonCode: reason,
        identity: identity,
      );
    }, staleIdentity: () => _overrideIdentities.remove(capability.key));
  }

  Future<void> _mutate(
    Future<void> Function() action, {
    required VoidCallback staleIdentity,
  }) async {
    setState(() {
      _pending = true;
      _message = null;
    });
    try {
      await action();
      staleIdentity();
      widget.onChanged?.call();
      await _load(clearMessage: false);
      if (mounted) setState(() => _message = 'Изменения сохранены.');
    } catch (error) {
      if (!mounted) return;
      if (error is MagicApiException && error.statusCode == 409) {
        staleIdentity();
        await _load(clearMessage: false);
        if (mounted) {
          setState(
            () => _message =
                'Доступ уже изменён в другой сессии. Данные обновлены.',
          );
        }
      } else {
        setState(
          () => _message = userErrorMessage(
            error,
            fallback: 'Не удалось сохранить изменения.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actorRole != 'director' && widget.actorRole != 'system_admin') {
      return const Material(
        child: Center(
          child: Text(
            'Недостаточно прав для управления доступом',
            key: Key('access-editor-forbidden'),
          ),
        ),
      );
    }
    final access = _access;
    return Material(
      key: const Key('access-editor-surface'),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Доступ: ${widget.userLabel}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (_isRoot)
                          const Text(
                            'Аварийный режим администратора системы',
                            key: Key('access-emergency-surface'),
                            style: TextStyle(color: AppColor.danger),
                          ),
                      ],
                    ),
                  ),
                  if (!widget.embedded)
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loadError != null
                  ? Center(
                      child: FilledButton(
                        onPressed: _load,
                        child: const Text('Повторить загрузку'),
                      ),
                    )
                  : access == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      key: const Key('access-editor-scroll'),
                      padding: const EdgeInsets.all(AppSpace.lg),
                      children: [
                        DropdownButtonFormField<String>(
                          menuMaxHeight: 256,
                          key: const Key('access-role-selector'),
                          initialValue: _selectedRole,
                          decoration: const InputDecoration(labelText: 'Роль'),
                          items: [
                            for (final role in _assignableRoles(access))
                              DropdownMenuItem(
                                value: role,
                                child: Text(_roleLabels[role] ?? 'Другая роль'),
                              ),
                          ],
                          onChanged: _pending
                              ? null
                              : (value) =>
                                    setState(() => _selectedRole = value),
                        ),
                        if (_selectedRole != access.role) ...[
                          const SizedBox(height: AppSpace.md),
                          const Text(
                            'При смене роли персональные настройки доступа '
                            'будут сброшены.',
                            key: Key('access-role-reset-warning'),
                          ),
                          CheckboxListTile(
                            key: const Key('access-reset-confirmation'),
                            contentPadding: EdgeInsets.zero,
                            value: _resetConfirmed,
                            onChanged: _pending
                                ? null
                                : (value) => setState(
                                    () => _resetConfirmed = value == true,
                                  ),
                            title: const Text('Подтверждаю сброс'),
                          ),
                        ],
                        const SizedBox(height: AppSpace.md),
                        DropdownButtonFormField<String>(
                          menuMaxHeight: 256,
                          key: const Key('access-reason'),
                          initialValue: _reasonController.text,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Причина изменения',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'access.review',
                              child: Text('Плановая проверка'),
                            ),
                            DropdownMenuItem(
                              value: 'access.role_change',
                              child: Text('Изменение обязанностей'),
                            ),
                            DropdownMenuItem(
                              value: 'access.correction',
                              child: Text('Исправление ошибки'),
                            ),
                          ],
                          onChanged: _pending
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _reasonController.text = value;
                                  }
                                },
                        ),
                        const SizedBox(height: AppSpace.md),
                        FilledButton(
                          key: const Key('access-save-role'),
                          onPressed: _pending || _selectedRole == access.role
                              ? null
                              : _saveRole,
                          child: const Text('Сохранить роль'),
                        ),
                        const SizedBox(height: AppSpace.xl),
                        Text(
                          'Версия набора прав: ${access.packageVersion}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpace.sm),
                        for (final capability in access.capabilities)
                          SwitchListTile(
                            key: Key('access-capability-${capability.key}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _capabilityLabels[capability.key] ??
                                  'Неизвестное право',
                            ),
                            subtitle: Text(
                              'По роли: ${capability.packageEffect == 'allow' ? 'включено' : 'выключено'}'
                              '${capability.overrideEffect == null ? '' : '. Лично: ${capability.overrideEffect == 'allow' ? 'включено' : 'выключено'}'}',
                            ),
                            value: capability.effectiveAllowed,
                            onChanged:
                                _pending ||
                                    (capability.effectiveAllowed
                                        ? !capability.canDeny
                                        : !capability.canAllow)
                                ? null
                                : (value) => _setCapability(capability, value),
                          ),
                      ],
                    ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Text(_message!, key: const Key('access-editor-message')),
              ),
            if (_pending) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
