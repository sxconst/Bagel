import 'package:flutter/material.dart';
import '../models/raffle.dart';
import '../services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RewardsProvider with ChangeNotifier {
  List<Raffle> _raffles = [];
  bool _isLoading = false;
  String _prevWinner = 'No Winner';
  int _entries = 0;

  List<Raffle> get raffles => _raffles;
  bool get isLoading => _isLoading;
  String get prevWinner => _prevWinner;
  int get entries => _entries;

  Future<void> loadRaffles() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await ApiService.getRaffles();
      _raffles = data.map((json) => Raffle.fromJson(json)).toList();
      fetchUserEntries(_raffles.first.id);
    } catch (e) {
      debugPrint('Error loading raffles: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> enterRaffle(String raffleID, int entries) async {
    try {
      final String userID = Supabase.instance.client.auth.currentUser?.id ?? '';
      await ApiService.enterRaffle(raffleID: raffleID, userID: userID, entries: entries);
      await loadRaffles(); // Refresh data
      return true;
    } catch (e) {
      debugPrint('Error entering raffle: $e');
      return false;
    }
  }

  Future<Duration?> refreshCountdown() async {
    try {
      final raffle = await ApiService.getRaffles();
      final raffleDetails = raffle.map((json) => Raffle.fromJson(json)).toList();
      final firstRaffle = raffleDetails.first;
      final difference = firstRaffle.end.difference(DateTime.now().toUtc());
      return difference;
    } catch (e) {
      debugPrint('Could not fetch raffle details: $e');
      return Duration.zero;
    }
  }

  Future<void> fetchUserEntries(String raffleId) async {
    final String userID = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userID.isNotEmpty) {
      final entriesData = await ApiService.fetchUserEntries(userID, raffleId);
      _entries = entriesData?['entries'] ?? 0;
    }
  }

  Future<void> setPreviousWinner() async {
    try {
      for (final raffle in raffles) {
        if (raffle.status == false) {
          final userData = await ApiService.fetchUsername(raffle.winner);
          _prevWinner = userData?['username'];
        }
      }
    } catch(e) {
      debugPrint('Could not get previous winner: $e');
    }
  }
}