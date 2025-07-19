import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../auth/auth_guard.dart';
import '../auth/auth_modal.dart';
import '../providers/auth_provider.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadProfile();
  }

  Future<void> _checkAuthAndLoadProfile() async {
    // Check if user is signed in using AuthGuard
    if (AuthGuard.isSignedIn) {
      await _loadUserProfile();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserProfile() async {
    if (AuthGuard.currentUserId != null) {
      final profile = await ApiService.fetchUserProfile(AuthGuard.currentUserId!);
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _showAuthModal({bool isSignUp = false}) {
    AuthModal.show(
      context,
      onSuccess: () {
        // Refresh the profile after successful authentication
        setState(() {
          _isLoading = true;
        });
        _loadUserProfile();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: AuthGuard.isSignedIn ? [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              onPressed: () => _showLogoutDialog(),
            ),
          ),
        ] : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AuthGuard.isSignedIn
              ? _buildAuthenticatedContent()
              : _buildUnauthenticatedContent(),
    );
  }

  Widget _buildAuthenticatedContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildProfileCard(),
          const SizedBox(height: 20),
          _buildStatsSection(),
          const SizedBox(height: 20),
          _buildContactSection(),
          const SizedBox(height: 100), // Bottom padding
        ],
      ),
    );
  }

  Widget _buildUnauthenticatedContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF007AFF),
                  const Color(0xFF007AFF).withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(60),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: Colors.white,
              size: 60,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Welcome to Your Account',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Create an account to start reporting and become a guardian of your local tennis community!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => _showAuthModal(isSignUp: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Get Started',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF007AFF),
                  const Color(0xFF007AFF).withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Center(
              child: Text(
                _getInitials(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _userProfile?['username'] ?? 'User',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _userProfile?['email'] ?? AuthGuard.currentUserEmail ?? '',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Stats',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.campaign_rounded,
                title: 'Usage Reports',
                value: '${_userProfile?['reports'] ?? 0}',
                color: const Color(0xFF34C759),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.report_rounded,
                title: 'Court Detail Updates',
                value: '${_userProfile?['court_details_updated'] ?? 0}',
                color: const Color(0xFF007AFF),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Send Us Feedback!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildContactItem(
                icon: Icons.photo_camera_rounded,
                label: 'Instagram',
                value: '@bagelapp',
              ),
              const SizedBox(height: 12),
              _buildContactItem(
                icon: Icons.email_rounded,
                label: 'Email',
                value: 'bagel.app.help@gmail.com',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: const Color(0xFF007AFF),
          size: 20,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getInitials() {
    final username = _userProfile?['username'] ?? 'U';
    if (username.length >= 2) {
      return username.substring(0, 2).toUpperCase();
    }
    return username.substring(0, 1).toUpperCase();
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Sign Out',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Provider.of<AuthProvider>(context, listen: false).signOut();
                Navigator.of(context).pop();
              },
              child: const Text(
                'Sign Out',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}