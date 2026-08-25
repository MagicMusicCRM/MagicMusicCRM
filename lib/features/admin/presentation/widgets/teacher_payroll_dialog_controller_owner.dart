import 'package:flutter/material.dart';

class TeacherPayrollDialogControllerOwner extends StatefulWidget {
  const TeacherPayrollDialogControllerOwner({
    super.key,
    required this.controllers,
    required this.builder,
  });

  final List<TextEditingController> controllers;
  final WidgetBuilder builder;

  @override
  State<TeacherPayrollDialogControllerOwner> createState() =>
      _TeacherPayrollDialogControllerOwnerState();
}

class _TeacherPayrollDialogControllerOwnerState
    extends State<TeacherPayrollDialogControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
