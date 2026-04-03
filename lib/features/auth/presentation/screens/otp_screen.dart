import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 6) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: '+${widget.phone}',
        token: otp,
        type: OtpType.sms,
      );
      if (mounted) context.go('/'); 
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppTheme.danger, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.primaryGold),
                      child: const Icon(Icons.sms_outlined, size: 50, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text('Подтверждение', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 16),
                  Text('Введите код из SMS, отправленный на\n+${widget.phone}', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white.withAlpha(160))),
                  const SizedBox(height: 48),

                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                    decoration: InputDecoration(
                      labelText: 'Код подтверждения',
                      counterText: '',
                      filled: true,
                      fillColor: AppTheme.cardDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.primaryGold, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 32),

                  Container(
                    height: 56,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: AppTheme.primaryGold),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isLoading ? null : _verifyOtp,
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Подтвердить', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
