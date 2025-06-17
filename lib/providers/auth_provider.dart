import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:bagel/providers/user_provider.dart';
import 'package:provider/provider.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  Future<bool> signIn({required BuildContext context, required String email, required String password}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final success = await ApiService.signIn(email: email, password: password);
      _isAuthenticated = success.$1;
      
      _isLoading = false;
      notifyListeners();
      // ignore: use_build_context_synchronously
      final UserProvider userDataLoader = Provider.of<UserProvider>(context, listen: false);
      userDataLoader.loadUserData();
      return _isAuthenticated;
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