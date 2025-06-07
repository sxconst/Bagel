import 'package:flutter/material.dart';
import '../services/api_service.dart';

class UserProvider with ChangeNotifier {
  int _tokens = 0;
  String _email = '';

  int get tokens => _tokens;
  String get email => _email;

  Future<void> loadUserData() async {
    try {
      final userData = await ApiService.getUserData();
      _tokens = userData['tokens'] ?? 0;
      _email = userData['email'] ?? '';
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  void addTokens(int amount) {
    _tokens += amount;
    notifyListeners();
  }

  void spendTokens(int amount) {
    _tokens -= amount;
    notifyListeners();
  }
}