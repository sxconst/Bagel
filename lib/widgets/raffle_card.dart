import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/raffle.dart';
import '../providers/rewards_provider.dart';
import '../providers/user_provider.dart';

class RaffleCard extends StatefulWidget {
  final Raffle raffle;

  const RaffleCard({super.key, required this.raffle});

  @override
  State<RaffleCard> createState() => _RaffleCardState();
}

class _RaffleCardState extends State<RaffleCard> {
  Future<void> _enterRaffle() async {
    // 1) Grab providers synchronously, before any async gap.
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final rewardsProvider = Provider.of<RewardsProvider>(context, listen: false);

    // 2) Check tokens immediately (no await here).
    if (userProvider.tokens < widget.raffle.tokensRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough tokens!')),
      );
      return;
    }

    // 3) Perform the async call. After this, `mounted` might be false.
    final bool success = await rewardsProvider.enterRaffle(
      widget.raffle.id,
      widget.raffle.tokensRequired,
    );

    // 4) If this widget was disposed while awaiting, bail out.
    if (!mounted) return;

    // 5) If the raffle entry succeeded, spend tokens and show the SnackBar.
    if (success) {
      userProvider.spendTokens(Supabase.instance.client.auth.currentUser?.id, widget.raffle.tokensRequired);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully entered raffle!')),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final raffle = widget.raffle;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              raffle.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Sponsored by: ${raffle.sponsorStore}'),
            Text('Prize: ${raffle.prize}'),
            Text('Required: ${raffle.tokensRequired} tokens'),
            if (raffle.userEntries > 0)
              Text('Your entries: ${raffle.userEntries}'),
            Text(
              'Ends: ${_formatDate(raffle.endDate)}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enterRaffle,
                child: Text('Enter Raffle (${raffle.tokensRequired} tokens)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
