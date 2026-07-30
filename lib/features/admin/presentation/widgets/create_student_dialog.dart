import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms.dart';

/// Compatibility entry point used by the existing Clients screen.
///
/// The v4 form owns loading, field-level validation and the strict
/// Lead/Student configuration contracts.
class CreateStudentDialog extends StatelessWidget {
  const CreateStudentDialog({super.key});

  @override
  Widget build(BuildContext context) => const StudentCreateDialogV4();
}
