part of 'client_card.dart';

extension _ClientCardModeration on _ClientCardState {
  /// Переключатель чёрного списка.
  ///
  /// ✔ Решение владельца 17.07: это бан — клиенту закрываются чаты школы и
  /// администрации. Поэтому не обычный тумблер:
  ///  - при постановке спрашиваем причину: через месяц «почему он в чёрном
  ///    списке» больше спросить будет не у кого;
  ///  - применяется сразу своим запросом, а не копится до «Сохранить» вместе с
  ///    остальными полями. Бан — не правка карточки, и уехать заодно с ней он
  ///    не должен.
  Widget _buildBlacklistToggle(ColorScheme cs) {
    final banned = _isBlacklisted;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: SwitchListTile(
        value: banned,
        activeThumbColor: AppTheme.danger,
        contentPadding: EdgeInsets.zero,
        title: const Text('Чёрный список'),
        subtitle: Text(
          banned
              ? (_blacklistReason ?? 'Причина не указана')
              : 'Клиент не сможет писать в чаты школы и администрации',
          style: TextStyle(
            fontSize: 12,
            color: banned ? AppTheme.danger : cs.onSurfaceVariant,
          ),
        ),
        onChanged: _blacklistBusy ? null : (value) => _toggleBlacklist(value),
      ),
    );
  }

  Future<void> _toggleBlacklist(bool value) async {
    String? reason;
    if (value) {
      reason = await _askBlacklistReason();
      // Отмена диалога — это отмена бана, а не бан без причины.
      if (reason == null) return;
    }

    _emitState(() => _blacklistBusy = true);
    try {
      // Банится та половина карточки, которая есть: аккаунт клиента цепляется
      // к любой из них, и бан только на ученике оставил бы лиду открытый чат.
      final service = ref.read(magicCrmServiceProvider);
      if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
        await service.setClientBlacklist(
          entity: 'students',
          id: _studentId,
          blacklisted: value,
          reason: reason,
        );
      }
      if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
        await service.setClientBlacklist(
          entity: 'leads',
          id: _leadId,
          blacklisted: value,
          reason: reason,
        );
      }
      // Перечитываем ту половину, которая открыта: флаг едет в её DTO.
      if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
        await _fetchStudentData();
      } else {
        await _fetchCard();
      }
      unawaited(_reloadOperationalHistory());
      if (mounted) {
        MagicToast.show(
          context,
          value ? 'Клиент в чёрном списке' : 'Клиент убран из чёрного списка',
          type: value ? MagicToastType.danger : MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось изменить чёрный список',
          detail: userErrorMessage(e),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _blacklistBusy = false);
    }
  }

  Future<String?> _askBlacklistReason() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('В чёрный список'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Клиент не сможет писать в чаты школы и администрации. '
              'Отменить это может любой администратор или управляющий.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Причина',
                hintText: 'Например: оскорблял администратора в чате',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('В чёрный список'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    // Причину не требуем: заставлять сочинять текст ради галочки — верный
    // способ получить «...» в каждой второй карточке. Пустая строка честнее.
    return controller.text.trim();
  }
}
