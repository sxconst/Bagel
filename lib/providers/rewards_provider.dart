import 'package:flutter/material.dart';
import '../models/raffle.dart';
import '../services/api_service.dart';

class RewardsProvider with ChangeNotifier {
  List<Raffle> _raffles = [];
  bool _isLoading = false;

  List<Raffle> get raffles => _raffles;
  bool get isLoading => _isLoading;

  Future<void> loadRaffles() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await ApiService.getRaffles();
      _raffles = data.map((json) => Raffle.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading raffles: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> enterRaffle(String raffleId, int tokens) async {
    try {
      await ApiService.enterRaffle(raffleId, tokens);
      await loadRaffles(); // Refresh data
      return true;
    } catch (e) {
      debugPrint('Error entering raffle: $e');
      return false;
    }
  }
}