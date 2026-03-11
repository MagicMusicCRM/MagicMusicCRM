import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class CustomFieldConfigWidget extends StatelessWidget {
  const CustomFieldConfigWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Настройки полей', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Управление дополнительными полями сущностей',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryPurple.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.schema_rounded, color: AppTheme.primaryPurple),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Динамические поля', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Система использует гибкую схему JSONB для всех сущностей: ученики, филиалы, преподаватели.\n\n'
                    'При создании или редактировании записи можно задать произвольные поля в формате ключ-значение:\n'
                    '• «Имя родителя»: «Иван Иванов»\n'
                    '• «Уровень»: «Начинающий»\n'
                    '• «Любимый жанр»: «Классика»\n\n'
                    'Эти атрибуты автоматически сохраняются в поле custom_data.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryGold.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.upcoming_rounded, color: AppTheme.secondaryGold),
                      ),
                      const SizedBox(width: 12),
                      const Text('Глобальные схемы', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Возможность настройки глобальных схем полей для шаблонной работы с custom_data будет добавлена в следующей версии.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Глобальные схемы — в разработке')),
                      );
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Настроить шаблоны'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
