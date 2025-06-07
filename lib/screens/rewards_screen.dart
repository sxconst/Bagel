import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/rewards_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/raffle_card.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<RewardsProvider>(context, listen: false).loadRaffles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rewards'),
        actions: [
          Consumer<UserProvider>(
            builder: (context, userProvider, child) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    '${userProvider.tokens} tokens',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<RewardsProvider>(
        builder: (context, rewardsProvider, child) {
          if (rewardsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rewardsProvider.raffles.length,
            itemBuilder: (context, index) {
              final raffle = rewardsProvider.raffles[index];
              return RaffleCard(raffle: raffle);
            },
          );
        },
      ),
    );
  }
}