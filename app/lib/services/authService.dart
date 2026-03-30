import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- EMAIL REGISTRATION ---
  Future<String?> registerWithEmail({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await result.user!.updateDisplayName("$firstName $lastName");

      // --- Save user data in Firestore ---
      await FirebaseFirestore.instance
          .collection('users')
          .doc(result.user!.uid)
          .set({
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            'photoBase64': '',
            'photoUrl': '',
            'createdAt': FieldValue.serverTimestamp(),
            'role': 'user', // Default role
          });

      await sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      // Return user-friendly error messages
      if (e.code == 'email-already-in-use') {
        return "This email is already registered. Please login or use another email.";
      }
      if (e.code == 'invalid-email') {
        return "Please enter a valid email address.";
      }
      if (e.code == 'weak-password') {
        return "Password is too weak. Try a stronger one.";
      }
      return e.message;
    } catch (e) {
      return 'An unknown error occurred';
    }
  }

  // --- EMAIL LOGIN ---
  Future<String?> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      if (!_auth.currentUser!.emailVerified) {
        await sendEmailVerification();
        await _auth.signOut();
        return "Please verify your email (check inbox/spam).";
      }
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return "No user found with this email.";
      }
      if (e.code == 'wrong-password') {
        return "Incorrect password. Please try again.";
      }
      return e.message;
    } catch (e) {
      return 'An unknown error occurred';
    }
  }

  // --- EMAIL VERIFICATION ---
  Future<void> sendEmailVerification() async {
    if (_auth.currentUser != null && !_auth.currentUser!.emailVerified) {
      await _auth.currentUser!.sendEmailVerification();
    }
  }

  // --- GOOGLE SIGN-IN ---
  Future<String?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return 'Google sign in cancelled.';

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      // --- Save user data to Firestore if not exists ---
      final user = userCredential.user;
      if (user != null) {
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        final doc = await docRef.get();

        // Proper name splitting (handles one-word names too)
        String displayName = user.displayName ?? '';
        String firstName = '';
        String lastName = '';
        if (displayName.isNotEmpty) {
          final nameParts = displayName.split(' ');
          firstName = nameParts.first;
          lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
        }

        if (!doc.exists) {
          await docRef.set({
            'firstName': firstName,
            'lastName': lastName,
            'email': user.email ?? '',
            'photoBase64': '',
            'photoUrl': user.photoURL ?? '',
            'createdAt': FieldValue.serverTimestamp(),
            'role': 'user',
          });
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        return "This email is already registered with another method.";
      }
      return e.message;
    } catch (e) {
      return 'Google sign in failed.';
    }
  }

  // --- OPTIONAL: Check if email exists before registration (for instant UI feedback) ---
  // Note: fetchSignInMethodsForEmail has been removed in firebase_auth 6.x
  // This method is no longer reliable for checking email existence
  Future<bool> checkIfEmailExists(String email) async {
    // This functionality is deprecated and unreliable in newer Firebase versions
    // Return false to disable the check
    return false;
  }

  // --- SIGN OUT ---
  Future<void> signOut() async {
    await _auth.signOut();
    await GoogleSignIn().signOut();
  }

  // --- SET USER AS ADMIN (Call this to make someone admin) ---
  Future<void> setUserAsAdmin(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'role': 'admin',
      });
    } catch (e) {
      print('Error setting user as admin: $e');
    }
  }

  // --- CHECK IF CURRENT USER IS ADMIN ---
  Future<bool> isCurrentUserAdmin() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        return userData?['role'] == 'admin';
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // --- GET USER ROLE ---
  Future<String> getUserRole() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'guest';

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        return userData?['role'] ?? 'user';
      }
      return 'user';
    } catch (e) {
      return 'user';
    }
  }
}
