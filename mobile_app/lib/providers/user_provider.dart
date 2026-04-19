import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

// ─── User State ───────────────────────────────────────────────────────────────

class UserState {
  final String? id;
  final String? email;
  final String? username;
  final String? dayfiUsername;
  final String? stellarPublicKey;
  final bool isVerified;
  final bool isLoading;
  final String? error;

  const UserState({
    this.id,
    this.email,
    this.username,
    this.dayfiUsername,
    this.stellarPublicKey,
    this.isVerified = false,
    this.isLoading = false,
    this.error,
  });

  String get displayUsername => dayfiUsername ?? username ?? '';
  String get initials => (username ?? 'U')[0].toUpperCase();

  UserState copyWith({
    String? id,
    String? email,
    String? username,
    String? dayfiUsername,
    String? stellarPublicKey,
    bool? isVerified,
    bool? isLoading,
    String? error,
  }) {
    return UserState(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      dayfiUsername: dayfiUsername ?? this.dayfiUsername,
      stellarPublicKey: stellarPublicKey ?? this.stellarPublicKey,
      isVerified: isVerified ?? this.isVerified,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  factory UserState.fromMap(Map<String, dynamic> map) {
    return UserState(
      id: map['id'] as String?,
      email: map['email'] as String?,
      username: map['username'] as String?,
      dayfiUsername: map['dayfiUsername'] as String?,
      stellarPublicKey: map['stellarPublicKey'] as String?,
      isVerified: map['isVerified'] as bool? ?? false,
    );
  }
}

// ─── User Notifier ────────────────────────────────────────────────────────────

class UserNotifier extends StateNotifier<UserState> {
  UserNotifier() : super(const UserState(isLoading: true)) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final token = await apiService.getToken();
      if (token == null) {
        state = const UserState();
        return;
      }

      final data = await apiService.getMe();
      state = UserState.fromMap(data).copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    try {
      final data = await apiService.getMe();
      state = UserState.fromMap(data);
    } catch (_) {}
  }

  void clear() {
    state = const UserState();
  }

  Future<void> registerDeviceToken(String token, String platform) async {
    try {
      await apiService.registerDeviceToken(token, platform);
    } catch (_) {}
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final userNotifierProvider = StateNotifierProvider<UserNotifier, UserState>((ref) {
  return UserNotifier();
});

final usernameProvider = Provider<String?>((ref) {
  return ref.watch(userNotifierProvider).username;
});

final emailProvider = Provider<String?>((ref) {
  return ref.watch(userNotifierProvider).email;
});