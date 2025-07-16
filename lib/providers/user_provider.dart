import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProvider with ChangeNotifier {
  int _tokens = 0;
  String _email = '';
  int _reports = 0;
  int _tokens24h = 0;

  int get tokens => _tokens;
  String get email => _email;
  int get reports => _reports;
  int get tokens24h => _tokens24h;

  Future<void> loadUserData() async {
    try {
      final String userID = Supabase.instance.client.auth.currentUser?.id ?? '';
      if (userID.isNotEmpty) {
        final userData = await ApiService.fetchUserProfile(userID);
        _tokens = userData?['tokens'];
        _email = userData?['email'];
        _reports = userData?['reports'];
        _tokens24h = userData?['tokens_earned_24h'];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> addTokens(int amount) async {
    final String userID = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userID.isNotEmpty) {
      _tokens += amount; // Increment local token count
      _tokens24h += amount; // Increment 24h token count
      await ApiService.upsertUserProfile(
        userId: userID,
        lastLat: null,
        lastLon: null,
        username: null,
        tokens: _tokens,
        tokens24h: _tokens24h,
      );
      notifyListeners();
    }
  }

  Future<void> spendTokens(int amount) async {
    final String userID = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userID.isNotEmpty) {
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

  Future<void> updateNumReports() async {
    final String userID = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userID.isNotEmpty) {
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