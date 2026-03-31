import 'package:flutter_riverpod/flutter_riverpod.dart';

class RegistrationCredentials {
  final String email;
  final String password;

  RegistrationCredentials({required this.email, required this.password});
}

class RegistrationNotifier extends Notifier<RegistrationCredentials?> {
  @override
  RegistrationCredentials? build() {
    return null;
  }

  void setCredentials(String email, String password) {
    state = RegistrationCredentials(email: email, password: password);
  }

  void clear() {
    state = null;
  }
}

/// Temporarily holds registration credentials in memory to support auto-login after email confirmation.
final registrationProvider = NotifierProvider<RegistrationNotifier, RegistrationCredentials?>(() {
  return RegistrationNotifier();
});
