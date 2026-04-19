// lib/screens/auth/username_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'dart:async';

class UsernameScreen extends StatefulWidget {
  final String setupToken;

  const UsernameScreen({super.key, required this.setupToken});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _checking = false;
  bool? _available;
  String? _errorMsg;
  Timer? _debounce;
  
  // Wallet creation steps
  int _currentStep = 0;
  final List<String> _steps = [
    'Authenticating...',
    'Creating Stellar wallet...',
    'Funding your account...',
    'Adding USDC trustline...',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _available = null;
      _errorMsg = null;
    });

    if (value.length < 3) return;

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      setState(() => _errorMsg = 'Only letters, numbers, underscores');
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 600), () => _checkUsername(value));
  }

  Future<void> _checkUsername(String username) async {
    setState(() => _checking = true);
    try {
      final result = await apiService.checkUsername(username);
      if (mounted) {
        setState(() {
          _available = result['available'] == true;
          _errorMsg = _available == false ? (result['reason'] ?? 'Username taken') : null;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _continue() async {
    if (_available != true || _loading) return;
    setState(() => _loading = true);

    try {
      // Step 1: Authenticating
      setState(() => _currentStep = 0);
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Creating wallet
      setState(() => _currentStep = 1);
      
      // Main API call (does wallet creation + funding + trustlines)
      final result = await apiService.setupUsername(
        _controller.text.trim().toLowerCase(),
        widget.setupToken,
      );
      
      if (!mounted) return;

      // Step 3: Funding account
      setState(() => _currentStep = 2);
      await Future.delayed(const Duration(milliseconds: 600));

      // Step 4: Adding trustline
      setState(() => _currentStep = 3);
      await Future.delayed(const Duration(milliseconds: 800));

      // Complete
      await apiService.saveToken(result['token']);
      if (mounted) context.go('/auth/biometric');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiService.parseError(e)),
            backgroundColor: DayFiColors.red,
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = _controller.text.trim();

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
                'Claim your\ndayfi.me username',
                style: Theme.of(context).textTheme.displaySmall,
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0),

              const SizedBox(height: 12),

              Text(
                'This will be your payment username.\nIt\'s not an email address.',
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 32),

              // Username input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onChanged: _onUsernameChanged,
                      onSubmitted: (_) => _continue(),
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'yourname',
                        errorText: _errorMsg,
                        suffixIcon: _checking
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _available == true
                                ? const Icon(Icons.check_circle, color: DayFiColors.green, size: 20)
                                : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '@dayfi.me',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ).animate().fadeIn(delay: 200.ms),

              if (_available == true && username.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '✓ This username is available',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DayFiColors.green,
                      ),
                ).animate().fadeIn(),
              ],

              const Spacer(flex: 3),

              ElevatedButton(
                onPressed: _available == true && !_loading ? _continue : null,
                child: _loading
                    ? Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _steps[_currentStep],
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
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