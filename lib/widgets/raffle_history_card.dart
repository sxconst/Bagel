import 'package:flutter/material.dart';

class RaffleHistoryCard extends StatelessWidget {
  const RaffleHistoryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: const Text('Wilson Pro Staff'),
              subtitle: const Text('Entered 3 times • Ended 2 days ago'),
              trailing: Chip(
                label: const Text('Lost'),
                backgroundColor: Colors.red[100],
              ),
            ),
            ListTile(
              title: const Text('Tennis Strings Set'),
              subtitle: const Text('Entered 1 time • Active'),
              trailing: Chip(
                label: const Text('Active'),
                backgroundColor: Colors.blue[100],
              ),
            ),
          ],
        ),
      ),
    );
  }
}