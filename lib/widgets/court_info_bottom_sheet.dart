import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tennis_court.dart';
import '../providers/courts_provider.dart';
import '../providers/user_provider.dart';
import '../auth/auth_guard.dart';

class CourtInfoBottomSheet extends StatefulWidget {
  final TennisCourt court;

  const CourtInfoBottomSheet({super.key, required this.court});

  @override
  State<CourtInfoBottomSheet> createState() => _CourtInfoBottomSheetState();
}

class _CourtInfoBottomSheetState extends State<CourtInfoBottomSheet> {
  int _selectedCourtsInUse = 0;

  @override
  void initState() {
    super.initState();
    _selectedCourtsInUse = widget.court.courtsInUse;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.court.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text('Total Courts: ${widget.court.totalCourts}'),
          Text('Currently in Use: ${widget.court.courtsInUse}'),
          const SizedBox(height: 5),

          Text(
            widget.court.status == CourtStatus.noRecentReport
              ? 'No report in the last 90 minutes'
              : 'Last Updated: ${widget.court.timeSinceLastUpdate} minutes ago',
            style: TextStyle(color: Colors.grey[600]),
          ),

          // then the larger bottom gap
          const SizedBox(height: 20),
          
          // Reward callout
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.stars, color: Colors.green[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Earn 150 tokens for helping keep court info updated!',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          const Text('Update court usage:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: List.generate(widget.court.totalCourts + 1, (index) {
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCourtsInUse = index),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _selectedCourtsInUse == index 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$index',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedCourtsInUse == index 
                            ? Colors.white 
                            : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleUpdateCourtUsage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.update, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Update & Earn 150 Tokens',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          
          // Optional: Show sign-in hint if not authenticated
          if (!AuthGuard.isSignedIn) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Sign in to earn tokens and track your contributions',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _handleUpdateCourtUsage() async {
    // Use AuthGuard to protect this action
    await AuthGuard.protectAsync(
      context,
      () => _performCourtUpdate(),
      message: 'Sign in to update courts and earn 150 tokens!',
    );
  }

  Future<void> _performCourtUpdate() async {
    final courtsProvider = Provider.of<CourtsProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    try {
      // Show loading state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Updating court...'),
            ],
          ),
          duration: Duration(seconds: 1),
        ),
      );

      // Perform the update
      await courtsProvider.updateCourtUsage(widget.court.clusterId, _selectedCourtsInUse);
      userProvider.addTokens(150);

      if (mounted) {
        Navigator.pop(context);
        
        // Show success message with token reward
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Court updated successfully!'),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stars, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        '+150',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Handle error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                const Text('Failed to update court. Please try again.'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
