import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/auth_service.dart';

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.uid,
    required this.email,
    required this.username,
    this.providerIds = const {},
  });

  final String uid;
  final String email;
  final String username;
  final Set<String> providerIds;

  factory AuthenticatedUser.fromFirebase(User user, {String? username}) {
    final email = user.email ?? '';
    final fallbackName = email.contains('@')
        ? email.split('@').first
        : 'ReadToon';
    final profileName = username?.trim();
    final displayName = user.displayName?.trim();
    return AuthenticatedUser(
      uid: user.uid,
      email: email,
      username: profileName?.isNotEmpty == true
          ? profileName!
          : displayName?.isNotEmpty == true
          ? displayName!
          : fallbackName,
      providerIds: user.providerData.map((info) => info.providerId).toSet(),
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Konuk oturumu yalnızca uygulamanın mevcut çalıştırması boyunca sürer.
final guestModeProvider = StateProvider<bool>((ref) => false);

/// Giriş/kayıt/çıkış değişikliklerini Firebase'den canlı takip eder.
/// Firebase henüz yapılandırılmamış test ortamlarında oturumsuz state döner.
final authStateProvider = StreamProvider<AuthenticatedUser?>((ref) {
  try {
    return ref
        .watch(authServiceProvider)
        .authStateChanges
        .map(
          (user) => user == null ? null : AuthenticatedUser.fromFirebase(user),
        );
  } catch (_) {
    return Stream.value(null);
  }
});
