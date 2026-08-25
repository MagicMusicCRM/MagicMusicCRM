import 'package:magic_music_crm/core/services/magic_crm_service.dart';

typedef TeacherAccessDialogRunner =
    Future<bool?> Function({
      required String initialEmail,
      String? currentPassword,
      required Future<void> Function(String? email, String? password) onSubmit,
    });

class TeacherDetailAccessFlow {
  const TeacherDetailAccessFlow._();

  static Future<Map<String, dynamic>?> run({
    required MagicCrmService service,
    required String teacherId,
    required String currentEmail,
    required bool accessExists,
    required TeacherAccessDialogRunner showDialog,
    required void Function(Object error) onLoadError,
  }) async {
    Map<String, dynamic>? credentials;
    if (accessExists) {
      try {
        credentials = await service.getTeacherAccess(teacherId);
      } catch (error) {
        onLoadError(error);
        return null;
      }
    }
    Map<String, dynamic>? updated;
    final saved = await showDialog(
      initialEmail: credentials?['email']?.toString() ?? currentEmail,
      currentPassword: credentials?['password']?.toString(),
      onSubmit: (email, password) async {
        updated = await service.provisionTeacherAccess(
          teacherId: teacherId,
          email: email,
          password: password,
        );
      },
    );
    return saved == true ? updated : null;
  }
}
