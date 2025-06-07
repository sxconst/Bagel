import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  Future<bool> signIn({required String email, required String password}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final success = await ApiService.signIn(email: email, password: password);
      _isAuthenticated = success;
      
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await ApiService.signOut();
    _isAuthenticated = false;
    notifyListeners();
  }
}