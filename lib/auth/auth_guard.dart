import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'auth_modal.dart';

class AuthGuard {
  /// Checks if user is authenticated, shows auth modal if not
  /// Returns true if user is authenticated or becomes authenticated
  /// Returns false if user dismisses the modal without authenticating
  static Future<bool> requireAuth(
    BuildContext context, {
    String? message,
  }) async {
    // Check if user is already signed in
    if (ApiService.currentUser != null) {
      return true;
    }

    // Show optional message about why authentication is needed
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      
      // Small delay to let user read the message
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Show auth modal and wait for result
    bool authSuccessful = false;
    
    await showModalBottomSheet(
      // ignore: use_build_context_synchronously
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => AuthBottomSheet(
        onSuccess: () {
          authSuccessful = true;
        },
      ),
    );

    return authSuccessful;
  }

  /// Wrapper for actions that require authentication
  /// Usage: AuthGuard.protect(context, () => doSomething(), message: "Sign in to continue")
  static Future<void> protect(
    BuildContext context,
    VoidCallback action, {
    String? message,
  }) async {
    final isAuthenticated = await requireAuth(context, message: message);
    if (isAuthenticated) {
      action();
    }
  }

  /// Async wrapper for actions that require authentication
  /// Usage: AuthGuard.protectAsync(context, () async => await doSomething(), message: "Sign in to continue")
  static Future<void> protectAsync(
    BuildContext context,
    Future<void> Function() action, {
    String? message,
  }) async {
    final isAuthenticated = await requireAuth(context, message: message);
    if (isAuthenticated) {
      await action();
    }
  }

  /// Check if user is currently signed in
  static bool get isSignedIn => ApiService.currentUser != null;

  /// Get current user email if signed in
  static String? get currentUserEmail => ApiService.currentUser?.email;

  /// Get current user ID if signed in
  static String? get currentUserId => ApiService.currentUser?.id;
}