import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/rewards_provider.dart';
import '../providers/user_provider.dart';
import '../auth/auth_guard.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  int selectedEntries = 1;
  final int entryFee = 500;
  Duration? countdownDuration;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Load raffles when the screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
    _loadRaffleData();
    });
  }

  Future<void> _loadRaffleData() async {
    final rewardsProvider = Provider.of<RewardsProvider>(context, listen: false);
    
    // If raffles are not cached, load them
    if (rewardsProvider.raffles.isEmpty) {
      await rewardsProvider.loadRaffles();
    }
    
    // Always refresh the countdown
    final duration = await rewardsProvider.refreshCountdown();
    if (duration != null && mounted) {
      setState(() {
        countdownDuration = duration;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showHowToEarnTokens() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'How to Earn Tokens',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1976D2),
            ),
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EarnMethodItem(
                  icon: Icons.person,
                  title: 'Sign Up',
                  description: 'Sign up for an account to begin earning',
                ),
                _EarnMethodItem(
                  icon: Icons.sports_tennis,
                  title: 'Report court usage',
                  description: 'Earn 100 tokens every time you make a report!',
                ),
                _EarnMethodItem(
                  icon: Icons.hourglass_disabled,
                  title: 'Earning limits',
                  description: 'Token earning is limited to 100/minute and 500/day',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Got it!',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleIncrementEntries() async {
    if (!AuthGuard.isSignedIn) {
      final authenticated = await AuthGuard.requireAuth(context);
      if (!authenticated) return;
    }
    
    setState(() {
      selectedEntries++;
    });
  }

  Future<void> _handleDecrementEntries() async {
    if (!AuthGuard.isSignedIn) {
      final authenticated = await AuthGuard.requireAuth(context);
      if (!authenticated) return;
    }
    
    if (selectedEntries > 1) {
      setState(() {
        selectedEntries--;
      });
    }
  }

  // ignore: strict_top_level_inference
  Future<void> _handleSubmitEntries(raffle, int totalCost, UserProvider userProvider, RewardsProvider rewardsProvider) async {
    if (!AuthGuard.isSignedIn) {
      final authenticated = await AuthGuard.requireAuth(context);
      if (!authenticated) return;
    }

    // Check if user has enough tokens (existing validation logic)
    if (totalCost > userProvider.tokens) {
      return; // The insufficient tokens message will still be shown in the UI
    }

    // Show loading indicator
    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    // Enter the raffle
    final success = await rewardsProvider.enterRaffle(
      raffle.id, 
      totalCost,
    );
    
    // Hide loading indicator
    // ignore: use_build_context_synchronously
    Navigator.of(context).pop();
    
    if (success) {
      // Update user tokens
      userProvider.spendTokens(totalCost);
      
      // Reset selected entries
      setState(() {
        selectedEntries = 1;
      });
      
      // Show success message
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedEntries == 1 
                ? 'Successfully entered raffle!' 
                : 'Successfully entered raffle with $selectedEntries entries!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      // Show error message
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to enter raffle. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // Tab Bar
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFFE9ECEF),
                    width: 1,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF1976D2),
                indicatorWeight: 3,
                labelColor: const Color(0xFF1976D2),
                unselectedLabelColor: const Color(0xFF6C757D),
                labelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(text: 'Raffle'),
                  Tab(text: 'Leaderboard'),
                ],
              ),
            ),
            
            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRaffleTab(),
                  _buildLeaderboardTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRaffleTab() {
    return Consumer<RewardsProvider>(
      builder: (context, rewardsProvider, child) {
        if (rewardsProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1976D2)),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Title
              const Text(
                'New Raffle Every Week!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF212529),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // Current Raffle Card
              if (rewardsProvider.raffles.isNotEmpty) 
                _buildCurrentRaffleCard(rewardsProvider.raffles.first),
              
              // No raffles message
              if (rewardsProvider.raffles.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.card_giftcard,
                        size: 64,
                        color: const Color(0xFF1976D2).withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Active Raffles',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6C757D),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Check back soon for new prizes!',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF6C757D),
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 24),
              
              // How to Earn Tokens Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _showHowToEarnTokens,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1976D2), width: 2),
                    foregroundColor: const Color(0xFF1976D2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'HOW TO EARN TOKENS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Timer Section (only show if there are active raffles)
              if (rewardsProvider.raffles.isNotEmpty) _buildTimerSection(),
              
              const SizedBox(height: 32),
              
              // Winner Section
              _buildWinnerSection(),
              
              // Extra spacing at bottom for ads
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }

  // ignore: strict_top_level_inference
  Widget _buildCurrentRaffleCard(raffle) {
    return Consumer2<UserProvider, RewardsProvider>(
      builder: (context, userProvider, rewardsProvider, child) {
        final totalCost = selectedEntries * entryFee;
        
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Prize Title
                Text(
                  raffle.prize ?? 'Get This Item For Free!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212529),
                  ),
                  textAlign: TextAlign.center,
                ),
                                
                // Entry Counter
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: selectedEntries > 1 ? _handleDecrementEntries : null,
                      style: IconButton.styleFrom(
                        backgroundColor: selectedEntries > 1 
                            ? const Color(0xFFE3F2FD) 
                            : const Color(0xFFF5F5F5),
                        foregroundColor: selectedEntries > 1 
                            ? const Color(0xFF1976D2) 
                            : const Color(0xFF9E9E9E),
                      ),
                      icon: const Icon(Icons.remove),
                    ),
                    
                    const SizedBox(width: 24),
                    
                    Text(
                      '$selectedEntries',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1976D2),
                      ),
                    ),
                    
                    const SizedBox(width: 24),
                    
                    IconButton(
                      onPressed: _handleIncrementEntries,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFE3F2FD),
                        foregroundColor: const Color(0xFF1976D2),
                      ),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),

                Text(
                  '(${totalCost.toStringAsFixed(0)} TOKENS)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6C757D),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Submit Button - Always enabled for visual appeal
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _handleSubmitEntries(raffle, totalCost, userProvider, rewardsProvider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      selectedEntries == 1 
                          ? 'SUBMIT 1 ENTRY' 
                          : 'SUBMIT $selectedEntries ENTRIES',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                
                // Insufficient tokens message - only show for authenticated users
                if (AuthGuard.isSignedIn && totalCost > userProvider.tokens)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Insufficient tokens. You need ${totalCost - userProvider.tokens} more tokens.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                
                // Encouraging sign-up message for unauthenticated users
                
              if (!AuthGuard.isSignedIn)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'You must be signed in to enter!',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimerSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'NEXT PRIZE DRAWING',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6C757D),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          
          if (countdownDuration != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _buildTimerUnit(countdownDuration!.inDays.toString().padLeft(2, '0'), 'DAYS'),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                ),
                _buildTimerUnit((countdownDuration!.inHours % 24).toString().padLeft(2, '0'), 'HRS'),
              ],
            )
          else
            // Fallback to hardcoded values if countdown is not available
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _buildTimerUnit('--', 'DAYS'),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                ),
                _buildTimerUnit('--', 'HRS'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTimerUnit(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1976D2),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6C757D),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildWinnerSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Color(0xFF1976D2),
            child: Icon(
              Icons.person,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'LAST WEEK\'S WINNER',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1976D2),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'mrjuicy11 / NewJersey',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212529),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              // Handle view more winners
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF1976D2),
            ),
            child: const Text(
              'VIEW MORE WINNERS',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    return const Center(
      child: Text(
        'Leaderboard Coming Soon!',
        style: TextStyle(
          fontSize: 18,
          color: Color(0xFF6C757D),
        ),
      ),
    );
  }
}

class _EarnMethodItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _EarnMethodItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1976D2).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF1976D2),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF212529),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6C757D),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}