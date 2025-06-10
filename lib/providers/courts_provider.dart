import 'package:flutter/material.dart';
import '../models/tennis_court.dart';
import '../services/api_service.dart';

class CourtsProvider with ChangeNotifier {
  List<TennisCourt> _courts = [];
  List<PartnerStore> _partnerStores = [];
  bool _isLoading = false;

  List<TennisCourt> get courts => _courts;
  List<PartnerStore> get partnerStores => _partnerStores;
  bool get isLoading => _isLoading;

  Future<void> loadCourts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final courtData = await ApiService.getCourts();
      final storeData = await ApiService.getPartnerStores();
      
      _courts = courtData.map((json) => TennisCourt.fromJson(json)).toList();
      _partnerStores = storeData.map((json) => PartnerStore.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading courts: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateCourtUsage(String courtId, int courtsInUse) async {
    try {
      await ApiService.updateCourtUsage(courtId, courtsInUse);
      
      // Update local data
      final courtIndex = _courts.indexWhere((court) => court.clusterId == courtId);
      if (courtIndex != -1) {
        await loadCourts();
      }    

    } catch (e) {
      debugPrint('Error updating court usage: $e');
    }
  }
}