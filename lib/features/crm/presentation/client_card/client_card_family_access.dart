part of 'client_card.dart';

extension _ClientCardFamilyAccess on _ClientCardState {
  // Reads the family id out of either the existing `_family` payload or the
  // raw `createFamily` response (which nests the record under `family`).
  String? _familyIdFrom(Map<String, dynamic>? source) {
    if (source == null) return null;
    final direct = source['id']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = source['family'];
    if (nested is Map) {
      final id = nested['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> _openAddFamilyMemberSheet() async {
    final selfId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    final input = await showAddFamilyMemberSheet(
      context,
      isStudent: _isStudent,
      // Default the linked record to this card's own entity (lead or student).
      defaultEntityType: widget.entityType,
      defaultEntityId: selfId,
      defaultEntityLabel: _clientPresentationLabel,
    );
    if (input == null) return;
    final role = input.role;
    final entityType = input.entityType;
    final entityId = input.entityId;
    final isPrimaryContact = input.isPrimaryContact;
    if (entityId.isEmpty) {
      if (mounted) {
        MagicToast.show(
          context,
          'Выберите запись',
          type: MagicToastType.danger,
        );
      }
      return;
    }

    _emitState(() => _familyBusy = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      var familyId = _familyIdFrom(_family?['family'] as Map<String, dynamic>?);
      if (familyId == null) {
        final branchId = _leadData['branch_id']?.toString();
        final created = await crm.createFamily({
          if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
        });
        familyId = _familyIdFrom(created);
        if (familyId == null) {
          throw StateError('Не удалось получить идентификатор семьи');
        }
      }
      await crm.addFamilyMember(
        familyId,
        entityType: entityType,
        entityId: entityId,
        role: role,
        isPrimaryContact: isPrimaryContact ? true : null,
      );
      await _fetchFamily();
      if (mounted) {
        MagicToast.show(
          context,
          'Участник добавлен',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка добавления',
          detail: userErrorMessage(e),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _familyBusy = false);
    }
  }

  Future<void> _removeFamilyMember(FamilyMember member) async {
    final memberId = member.id;
    if (memberId.isEmpty) return;
    final name = member.name.trim().isNotEmpty ? member.name : 'участника';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('Связь "$name" с семьёй будет удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    _emitState(() => _familyBusy = true);
    try {
      await ref.read(magicCrmServiceProvider).removeFamilyMember(memberId);
      await _fetchFamily();
      if (mounted) {
        MagicToast.show(
          context,
          'Участник удалён',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка удаления',
          detail: userErrorMessage(e),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _familyBusy = false);
    }
  }

  Future<void> _setFamilyPrimaryPayer(FamilyMember member) async {
    final familyRecord = _family?['family'];
    final familyId = familyRecord is Map
        ? familyRecord['id']?.toString()
        : null;
    if (familyId == null || familyId.isEmpty || member.id.isEmpty) return;
    _emitState(() => _familyBusy = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .setFamilyPrimaryPayer(familyId, member.id);
      await _fetchFamily();
      if (mounted) {
        MagicToast.show(
          context,
          'Основной плательщик назначен',
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось назначить плательщика',
          detail: userErrorMessage(error),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _familyBusy = false);
    }
  }

  void _openFamilyMember(BuildContext sourceContext, FamilyMember member) {
    final entityType = member.entityType;
    final entityId = member.entityId;
    if (entityId == null || entityId.isEmpty) return;
    if (entityType != 'lead' && entityType != 'student') return;
    _openLinkedRecord(
      sourceContext,
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: entityId,
        variant: entityType,
        presentation: EntityPresentationReference(primary: member.name),
      ),
      EntityOpenTarget.current,
    );
  }

  Future<void> _linkClientUser(Map<String, dynamic> candidate) async {
    final userId =
        candidate['userId']?.toString() ?? candidate['user_id']?.toString();
    if (userId == null || userId.isEmpty) return;
    _emitState(() => _clientAccessBusy = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .linkUserToClient(widget.entityType, _entityId, userId);
      await _fetchClientAccess();
      if (mounted) {
        MagicToast.show(
          context,
          'Аккаунт связан с карточкой',
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось связать аккаунт',
          detail: userErrorMessage(error),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _clientAccessBusy = false);
    }
  }

  Future<void> _inviteClientToApp() async {
    final studentId = _studentId;
    if (studentId.isEmpty) return;
    _emitState(() => _clientAccessBusy = true);
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .inviteStudent(studentId);
      if (mounted) {
        MagicToast.show(
          context,
          'Приглашение отправлено',
          detail: result['email']?.toString(),
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось отправить приглашение',
          detail: userErrorMessage(error),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _clientAccessBusy = false);
    }
  }

  bool _isCurrentLeadDuplicateCandidate(Map<String, dynamic> candidate) {
    final leadId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    if (leadId == null || leadId.isEmpty) return false;
    return (candidate['entity_type_a'] == 'lead' &&
            candidate['entity_id_a'] == leadId &&
            candidate['entity_type_b'] == 'student') ||
        (candidate['entity_type_b'] == 'lead' &&
            candidate['entity_id_b'] == leadId &&
            candidate['entity_type_a'] == 'student');
  }
}
