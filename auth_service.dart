import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'fcm_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FcmService _fcmService = FcmService();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _fcmService.registerTokenForCurrentUser();
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    await _fcmService.registerTokenForCurrentUser();
  }

  Future<void> signOut() async {
    await _fcmService.unregisterTokenForCurrentUser();
    await _auth.signOut();
  }

  /// Переводит код ошибки FirebaseAuth в понятное локализованное сообщение.
  static String messageForError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'auth.errorInvalidEmail'.tr();
      case 'user-disabled':
        return 'auth.errorUserDisabled'.tr();
      case 'user-not-found':
        return 'auth.errorUserNotFound'.tr();
      case 'wrong-password':
      case 'invalid-credential':
        return 'auth.errorWrongPassword'.tr();
      case 'email-already-in-use':
        return 'auth.errorEmailInUse'.tr();
      case 'weak-password':
        return 'auth.errorWeakPassword'.tr();
      default:
        return 'auth.errorGeneric'.tr(args: [e.message ?? e.code]);
    }
  }
}
