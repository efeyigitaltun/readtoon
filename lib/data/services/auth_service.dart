import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Firebase Authentication ve kullanıcı profil dokümanlarını yönetir.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  }) : _authOverride = auth,
       _firestoreOverride = firestore,
       _googleSignInOverride = googleSignIn;

  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _firestoreOverride;
  final GoogleSignIn? _googleSignInOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  late final GoogleSignIn _googleSignIn =
      _googleSignInOverride ?? GoogleSignIn(scopes: const ['email']);

  Stream<User?> get authStateChanges => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    final normalizedUsername = username.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Hesap oluşturuldu ancak kullanıcı bilgisi alınamadı.',
      );
    }

    try {
      await user.updateDisplayName(normalizedUsername);
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'username': normalizedUsername,
        'usernameLower': normalizedUsername.toLowerCase(),
        'email': normalizedEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Başarısız profil yazımı kullanıcıyı Auth'ta yarım hesap olarak bırakmasın.
      try {
        await user.delete();
      } catch (_) {
        // Silme başarısız olsa da asıl profil yazma hatasını göster.
      }
      rethrow;
    }
    return credential;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user != null) {
      await _ensureUserProfile(user, preferredUsername: googleUser.displayName);
    }
    return userCredential;
  }

  Future<void> _ensureUserProfile(
    User user, {
    String? preferredUsername,
  }) async {
    final profile = _firestore.collection('users').doc(user.uid);
    final snapshot = await profile.get();
    final existingUsername = snapshot.data()?['username'] as String?;
    final email = user.email?.trim().toLowerCase() ?? '';
    final candidateUsername = existingUsername?.trim().isNotEmpty == true
        ? existingUsername!.trim()
        : preferredUsername?.trim().isNotEmpty == true
        ? preferredUsername!.trim()
        : user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : email.contains('@')
        ? email.split('@').first
        : 'ReadToon';
    final truncatedUsername = candidateUsername.length > 24
        ? candidateUsername.substring(0, 24)
        : candidateUsername;
    final username = truncatedUsername.length >= 3
        ? truncatedUsername
        : 'reader_${user.uid.substring(0, 6)}';

    await user.updateDisplayName(username);
    await profile.set({
      'uid': user.uid,
      'username': username,
      'usernameLower': username.toLowerCase(),
      'email': email,
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> resetPassword(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  /// Reauthenticates, removes account-owned cloud data, then deletes the Auth user.
  /// Password users must provide their current password; Google users are asked
  /// to choose and reauthenticate with their Google account.
  Future<void> deleteAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Silinecek etkin bir hesap bulunamadı.',
      );
    }

    final providers = user.providerData.map((info) => info.providerId).toSet();
    if (providers.contains(EmailAuthProvider.PROVIDER_ID)) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw FirebaseAuthException(
          code: 'requires-recent-login',
          message: 'Hesabı silmek için mevcut şifreniz gerekli.',
        );
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } else if (providers.contains(GoogleAuthProvider.PROVIDER_ID)) {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'user-cancelled',
          message: 'Google doğrulaması iptal edildi.',
        );
      }
      final googleAuth = await googleUser.authentication;
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        ),
      );
    } else {
      throw FirebaseAuthException(
        code: 'unsupported-provider',
        message: 'Bu giriş yöntemiyle hesap silme desteklenmiyor.',
      );
    }

    await _deleteCloudData(user.uid);
    await user.delete();
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Firebase hesabı ve bulut verileri silinmiştir.
    }
  }

  Future<void> _deleteCloudData(String uid) async {
    final userDocument = _firestore.collection('users').doc(uid);
    final library = await userDocument.collection('library').get();
    final reviewIndex = await userDocument.collection('review_index').get();
    final authoredReviews = await _firestore
        .collectionGroup('reviews')
        .where('userId', isEqualTo: uid)
        .get();
    final reports = await _firestore
        .collection('review_reports')
        .where('reporterId', isEqualTo: uid)
        .get();

    final references = <DocumentReference<Map<String, dynamic>>>[
      ...library.docs.map((document) => document.reference),
      ...reviewIndex.docs.map((document) => document.reference),
      ...authoredReviews.docs.map((document) => document.reference),
      ...reports.docs.map((document) => document.reference),
      userDocument,
    ];

    for (var start = 0; start < references.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, references.length);
      for (final reference in references.sublist(start, end)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Firebase oturumu kapandı; Google hesap seçicisi sonraki girişte açılabilir.
    }
  }
}
