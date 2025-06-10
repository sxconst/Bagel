import 'package:flutter/material.dart';
import '../services/api_service.dart';

class UserProvider with ChangeNotifier {
  int _tokens = 0;
  String _email = '';
  int _reports = 0;

  int get tokens => _tokens;
  String get email => _email;
  int get reports => _reports;

  Future<void> loadUserData(String userID) async {
    try {
      final userData = await ApiService.fetchUserProfile(userID);
      _tokens = userData?['tokens'];
      _email = userData?['email'];
      _reports = userData?['reports'];
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> addTokens(String? userID, int amount) async {
    if (userID != null && userID.isNotEmpty) {
      _tokens += amount; // Increment local token count
      await ApiService.upsertUserProfile(
        userId: userID,
        lastLat: null,
        lastLon: null,
        username: null,
        tokens: _tokens,
      );
      notifyListeners();
    }
  }

  Future<void> spendTokens(String? userID, int amount) async {
    if (userID != null && userID.isNotEmpty) {
      _tokens -= amount; // Update local token count
      await ApiService.upsertUserProfile(
        userId: userID,
        lastLat: null,
        lastLon: null,
        username: null,
        tokens: _tokens,
      );
      notifyListeners();
    }
  }

  Future<void> updateNumReports(String? userID) async {
    if (userID != null && userID.isNotEmpty) {
      _reports += 1; // Increment local report count
      await ApiService.upsertUserProfile(
        userId: userID,
        lastLat: null,
        lastLon: null,
        username: null,
        tokens: null,
        reports: _reports,
      );
      notifyListeners();
    }
  }
}