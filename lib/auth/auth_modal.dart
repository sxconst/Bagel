import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AuthModal {
  static void show(BuildContext context, {VoidCallback? onSuccess}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => AuthBottomSheet(onSuccess: onSuccess),
    );
  }
}

class AuthBottomSheet extends StatefulWidget {
  final VoidCallback? onSuccess;
  
  const AuthBottomSheet({super.key, this.onSuccess});

  @override
  State<AuthBottomSheet> createState() => _AuthBottomSheetState();
}

class _AuthBottomSheetState extends State<AuthBottomSheet> {
  bool _isSignUp = false;
  bool _isForgotPassword = false;
  bool _isLoading = false;
  bool _showVerificationMessage = false;
  bool _showUnverifiedEmailWarning = false;
  String _verificationEmail = '';
  String _unverifiedEmail = '';
  
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _isForgotPassword = false;
      _showVerificationMessage = false;
      _showUnverifiedEmailWarning = false;
      // Clear confirm password and username when switching modes
      _confirmPasswordController.clear();
      _usernameController.clear();
    });
  }

  void _toggleForgotPassword() {
    setState(() {
      _isForgotPassword = !_isForgotPassword;
      _isSignUp = false;
      _showVerificationMessage = false;
      _showUnverifiedEmailWarning = false;
      // Clear confirm password and username when switching modes
      _confirmPasswordController.clear();
      _usernameController.clear();
    });
  }

  void _continueToSignIn() {
    setState(() {
      _showVerificationMessage = false;
      _isSignUp = false;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _usernameController.clear();
    });
  }

  void _resendVerificationEmail() async {
    setState(() => _isLoading = true);
    
    try {
      // Assuming you have a method in ApiService to resend verification
      final success = await ApiService.resendVerification(_unverifiedEmail);
      
      if (success) {
        _showSuccessMessage('Verification email sent! Please check your inbox.');
        setState(() {
          _showUnverifiedEmailWarning = false;
          _showVerificationMessage = true;
          _verificationEmail = _unverifiedEmail;
        });
      } else {
        _showErrorMessage('Failed to send verification email. Please try again.');
      }
    } catch (e) {
      _showErrorMessage('An error occurred while sending verification email.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _showUnverifiedEmailWarning = false;
    });

    try {
      if (_isForgotPassword) {
        final success = await ApiService.resetPassword(
          email: _emailController.text.trim(),
        );
        
        if (success) {
          _showSuccessMessage('Password reset email sent! Check your inbox and follow the instructions to reset your password.');
          setState(() => _isForgotPassword = false);
        } else {
          _showErrorMessage('Failed to send password reset email. Please check your email address and try again.');
        }
      } else if (_isSignUp) {
        final result = await ApiService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          username: _usernameController.text.trim(),
        );
        
        if (result.$1 == true) {
          _showSuccessMessage('Account created successfully! Please check your email for a confirmation link.');
          
          // Show verification message instead of immediately switching to sign in
          setState(() {
            _showVerificationMessage = true;
            _verificationEmail = _emailController.text.trim();
          });
        } else {
          _showErrorMessage('Failed to create account. This email might already be registered. Please try a different email or sign in instead.');
        }
      } else {
        final result = await ApiService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        
        // Assuming ApiService.signIn now returns a result object with success status and error type
        if (result.$1 == true) {
          _showSuccessMessage('Successfully signed in! Welcome back.');
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
          widget.onSuccess?.call();
        } else if (result.$2 == 'AuthApiException(message: Email not confirmed, statusCode: 400, code: email_not_confirmed)') {
          // Show unverified email warning
          setState(() {
            _showUnverifiedEmailWarning = true;
            _unverifiedEmail = _emailController.text.trim();
          });
        } else {
          _showErrorMessage('Invalid email or password. Please check your credentials and try again.');
        }
      }
    } catch (e) {
      _showErrorMessage('An unexpected error occurred. Please check your internet connection and try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String get _title {
    if (_showVerificationMessage) return 'Verify Your Email';
    if (_isForgotPassword) return 'Reset Password';
    return _isSignUp ? 'Create Account' : 'Sign In';
  }

  String get _buttonText {
    if (_isForgotPassword) return 'Send Reset Email';
    return _isSignUp ? 'Sign Up' : 'Sign In';
  }

  Widget _buildUnverifiedEmailWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange[700],
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Email Not Verified',
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your email address hasn\'t been verified yet. Please check your inbox for a verification email.',
            style: TextStyle(
              color: Colors.orange[600],
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _isLoading ? null : _resendVerificationEmail,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    foregroundColor: Colors.orange[700],
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.orange[700]!,
                            ),
                          ),
                        )
                      : const Text(
                          'Resend Verification Email',
                          style: TextStyle(fontSize: 12),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _showUnverifiedEmailWarning = false;
                  });
                },
                child: Text(
                  'Dismiss',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationMessage() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 64,
            color: Colors.blue,
          ),
        ),
        
        const SizedBox(height: 24),
        
        const Text(
          'Check Your Email',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        const SizedBox(height: 16),
        
        Text(
          'We\'ve sent a verification link to:',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 8),
        
        Text(
          _verificationEmail,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.blue,
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 24),
        
        Text(
          'Please check your email and click the verification link to activate your account. Once verified, you can sign in below.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 32),
        
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _continueToSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue to Sign In',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        TextButton(
          onPressed: () {
            setState(() {
              _showVerificationMessage = false;
              _isSignUp = true;
            });
          },
          child: const Text(
            'Didn\'t receive the email? Sign up again',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              _title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _showVerificationMessage 
                  ? _buildVerificationMessage()
                  : Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          
                          // Unverified email warning (appears above email field)
                          if (_showUnverifiedEmailWarning && !_isSignUp && !_isForgotPassword)
                            _buildUnverifiedEmailWarning(),
                          
                          // Email field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: _isForgotPassword 
                                ? TextInputAction.done 
                                : TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: _showUnverifiedEmailWarning 
                                    ? BorderSide(color: Colors.orange.withValues(alpha: 0.5))
                                    : const BorderSide(),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: _showUnverifiedEmailWarning 
                                    ? const BorderSide(color: Colors.orange)
                                    : const BorderSide(color: Colors.blue),
                              ),
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                  .hasMatch(value)) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          
                          // Username field (only for sign up)
                          if (_isSignUp && !_isForgotPassword) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _usernameController,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Username',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: const Icon(Icons.person_outlined),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a username';
                                }
                                if (value.length < 5) {
                                  return 'Username must be at least 5 characters';
                                }
                                if (value.length > 16) {
                                  return 'Username must be less than 16 characters';
                                }
                                if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                                  return 'Username can only contain letters, numbers, and underscores';
                                }
                                return null;
                              },
                            ),
                          ],
                          
                          if (!_isForgotPassword) ...[
                            const SizedBox(height: 16),
                            
                            // Password field
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              textInputAction: _isSignUp ? TextInputAction.next : TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: const Icon(Icons.lock_outlined),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                if (_isSignUp && value.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            
                            // Confirm Password field (only for sign up)
                            if (_isSignUp) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: 'Confirm Password',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please confirm your password';
                                  }
                                  if (value != _passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ],
                          
                          const SizedBox(height: 24),
                          
                          // Submit button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleSubmit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      _buttonText,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Toggle buttons
                          if (!_isForgotPassword) ...[
                            TextButton(
                              onPressed: _toggleMode,
                              child: Text(
                                _isSignUp
                                    ? 'Already have an account? Sign In'
                                    : 'Don\'t have an account? Sign Up',
                                style: const TextStyle(color: Colors.blue),
                              ),
                            ),
                            
                            if (!_isSignUp) ...[
                              TextButton(
                                onPressed: _toggleForgotPassword,
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ],
                          ] else ...[
                            TextButton(
                              onPressed: _toggleForgotPassword,
                              child: const Text(
                                'Back to Sign In',
                                style: TextStyle(color: Colors.blue),
                              ),
                            ),
                          ],
                          
                          const Spacer(),
                          
                          // Terms and conditions (for sign up)
                          if (_isSignUp && !_isForgotPassword)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'By signing up, you agree to our Terms of Service and Privacy Policy',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}