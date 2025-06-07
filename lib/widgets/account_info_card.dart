import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

class AccountInfoCard extends StatelessWidget {
  const AccountInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.email),
                  title: const Text('Email'),
                  subtitle: Text(userProvider.email),
                  trailing: TextButton(
                    onPressed: () => _showChangeEmailDialog(context),
                    child: const Text('Change'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text('Password'),
                  subtitle: const Text('••••••••'),
                  trailing: TextButton(
                    onPressed: () => _showChangePasswordDialog(context),
                    child: const Text('Change'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showChangeEmailDialog(BuildContext context) {
    // Implement email change dialog
  }

  void _showChangePasswordDialog(BuildContext context) {
    // Implement password change dialog
  }
}