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
  
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _isForgotPassword = false;
    });
  }

  void _toggleForgotPassword() {
    setState(() {
      _isForgotPassword = !_isForgotPassword;
      _isSignUp = false;
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_isForgotPassword) {
        final success = await ApiService.resetPassword(
          email: _emailController.text.trim(),
        );
        
        if (success) {
          _showMessage('Password reset email sent! Check your inbox.');
          setState(() => _isForgotPassword = false);
        } else {
          _showMessage('Failed to send password reset email. Please try again.');
        }
      } else if (_isSignUp) {
        final success = await ApiService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        
        if (success) {
          _showMessage('Account created successfully!');
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
          widget.onSuccess?.call();
        } else {
          _showMessage('Failed to create account. Please try again.');
        }
      } else {
        final success = await ApiService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        
        if (success) {
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
          widget.onSuccess?.call();
        } else {
          _showMessage('Invalid email or password.');
        }
      }
    } catch (e) {
      _showMessage('An error occurred. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String get _title {
    if (_isForgotPassword) return 'Reset Password';
    return _isSignUp ? 'Create Account' : 'Sign In';
  }

  String get _buttonText {
    if (_isForgotPassword) return 'Send Reset Email';
    return _isSignUp ? 'Sign Up' : 'Sign In';
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
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    
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
                        ),
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                            .hasMatch(value)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    
                    if (!_isForgotPassword) ...[
                      const SizedBox(height: 16),
                      
                      // Password field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
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