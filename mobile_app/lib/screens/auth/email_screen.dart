// lib/screens/auth/email_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
// import '../../theme/app_theme.dart';

class EmailScreen extends StatefulWidget {
  final bool isNewUser;
  const EmailScreen({super.key, this.isNewUser = true});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _agreed = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms of Service')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await apiService.sendOtp(_emailController.text.trim());
      if (mounted) {
        context.push(
          '/auth/otp',
          extra: {
            'email': _emailController.text.trim(),
            'isNewUser': result['isNewUser'] ?? false,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiService.parseError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // Back button (only if can pop)
                if (context.canPop())
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios, size: 20),
                  ),

                const Spacer(flex: 2),

                // Title
                Text(
                  widget.isNewUser ? 'Enter your Email' : 'Login with Email',
                  style: Theme.of(context).textTheme.displaySmall,
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0),

                const SizedBox(height: 12),

                Text(
                  widget.isNewUser
                      ? 'If this email is new, we\'ll continue creating your wallet. If it already has a wallet, we\'ll help you sign in.'
                      : 'If this email already has an account, we\'ll proceed with login. If it\'s new, we\'ll start creating your wallet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

                const SizedBox(height: 32),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _continue(),
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(hintText: 'you@email.com'),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Email required';
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(val)) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                const Spacer(flex: 3),

                // Terms checkbox
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _agreed,
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'I agree to the ',
                          style: Theme.of(context).textTheme.bodySmall,
                          children: [
                            TextSpan(
                              text: 'Terms of Service',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                            const TextSpan(text: ' & '),
                            TextSpan(
                              text: 'Privacy Statement',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Continue button
                ElevatedButton(
                  onPressed: _loading ? null : _continue,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('Continue'),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
