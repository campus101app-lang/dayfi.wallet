// lib/screens/auth/otp_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'dart:async';

class OtpScreen extends StatefulWidget {
  final String email;
  final bool isNewUser;

  const OtpScreen({super.key, required this.email, required this.isNewUser});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  bool _resending = false;
  int _resendCountdown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _resendCountdown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCountdown <= 0) {
        t.cancel();
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 6) return;
    setState(() => _loading = true);

    try {
      final result = await apiService.verifyOtp(widget.email, _otp);
      if (!mounted) return;

      final step = result['step'];

      if (step == 'setup_username') {
        context.push('/auth/username', extra: {'setupToken': result['setupToken']});
      } else if (step == 'complete') {
        await apiService.saveToken(result['token']);
        context.go('/home');
      } else {
        context.push('/auth/biometric');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiService.parseError(e)),
            backgroundColor: DayFiColors.red,
          ),
        );
        // Clear OTP
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0) return;
    setState(() => _resending = true);
    try {
      await apiService.sendOtp(widget.email);
      _startCountdown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New code sent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiService.parseError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _onChanged(int index, String value) {
    if (value.length == 6) {
      // Handle paste
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = value[i];
      }
      _focusNodes[5].requestFocus();
      _verify();
      return;
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    if (_otp.length == 6) _verify();
  }

  void _onKeyPressed(int index, RawKeyEvent event) {
    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final masked = widget.email.replaceRange(
      3,
      widget.email.indexOf('@'),
      '***',
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => context.pop(),
                child: const Icon(Icons.arrow_back_ios, size: 20),
              ),
              const Spacer(flex: 2),

              Text(
                'Enter the\n6-digit code',
                style: Theme.of(context).textTheme.displaySmall,
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0),

              const SizedBox(height: 12),

              Text(
                'Enter the code we\'ve sent to $masked',
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 40),

              // OTP boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  return SizedBox(
                    width: 48,
                    height: 60,
                    child: RawKeyboardListener(
                      focusNode: FocusNode(),
                      onKey: (e) => _onKeyPressed(i, e),
                      child: TextFormField(
                        controller: _controllers[i],
                        focusNode: _focusNodes[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: i == 0 ? 6 : 1,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: Theme.of(context).textTheme.headlineMedium,
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (v) => _onChanged(i, v),
                      ),
                    ),
                  );
                }),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 32),

              // Resend
              Center(
                child: _resending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : GestureDetector(
                        onTap: _resendCountdown == 0 ? _resend : null,
                        child: Text.rich(
                          TextSpan(
                            text: 'Didn\'t get the code? Request a new one in ',
                            style: Theme.of(context).textTheme.bodySmall,
                            children: [
                              TextSpan(
                                text: _resendCountdown > 0
                                    ? '00:${_resendCountdown.toString().padLeft(2, '0')}'
                                    : 'Resend',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: _resendCountdown == 0
                                          ? Theme.of(context).colorScheme.primary
                                          : null,
                                    ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),

              const Spacer(flex: 3),

              ElevatedButton(
                onPressed: _loading || _otp.length < 6 ? null : _verify,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Continue'),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}