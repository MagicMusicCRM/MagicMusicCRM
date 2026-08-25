import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_model.dart';

void main() {
  group('TeacherDetailInitialData', () {
    test('normalizes profile fallback and legacy employment values', () {
      final initial = TeacherDetailInitialData.fromTeacher({
        'id': 'teacher-a',
        'profiles': {
          'first_name': 'Анна',
          'last_name': 'Петрова',
          'phone': '+79990000000',
        },
        'current_rate': '750',
        'salary': 15000,
        'custom_data': {
          'level': 'Начальный; Средний, Продвинутый',
          'category': 'Дети, Взрослые',
          'birthday': '03.02.1990',
          'workStartDate': '2026-08-01',
          'isPartTime': true,
        },
      });

      expect(initial.name, 'Анна Петрова');
      expect(initial.phone, '+79990000000');
      expect(initial.employment.levels, {
        'Начальный',
        'Средний',
        'Продвинутый',
      });
      expect(initial.employment.categories, {'Дети', 'Взрослые'});
      expect(initial.employment.birthday, DateTime(1990, 2, 3));
      expect(initial.employment.workStartDate, DateTime(2026, 8, 1));
      expect(initial.employment.isPartTime, isTrue);
      expect(initial.employment.salary, 15000);
      expect(initial.employment.rate, 750);
    });

    test('plural arrays override singular legacy strings', () {
      final initial = TeacherDetailInitialData.fromTeacher({
        'id': 'teacher-a',
        'first_name': 'Ирина',
        'custom_data': {
          'levels': [' Профессиональный ', '', null],
          'level': 'Начальный',
          'categories': ['Взрослые'],
          'category': 'Дети',
        },
      });

      expect(initial.name, 'Ирина');
      expect(initial.employment.levels, {'Профессиональный'});
      expect(initial.employment.categories, {'Взрослые'});
    });
  });

  test('display helpers preserve role and branch compatibility', () {
    expect(teacherDetailRoleLabel('system_admin'), 'Администратор системы');
    expect(
      teacherDetailBranchesText([
        {'branch_name': 'Центр'},
        {'name': 'Север'},
      ]),
      'Центр, Север',
    );
  });
}
