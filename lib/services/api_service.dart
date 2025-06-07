import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  // Get the Supabase client instance
  static final SupabaseClient _supabase = Supabase.instance.client;
  
  static const String courtsTable = 'courts';
  static const String profilesTable = 'profiles';

  /// Retrieves all tennis courts from Supabase
  static Future<List<Map<String, dynamic>>> getCourts() async {
    try {
      final response = await _supabase
          .from(courtsTable)
          .select('*'); // Select all columns, or specify: 'id, name, lat, lon, total_courts, courts_in_use, last_updated, access, surface, lights'
      
      // Convert the response to the expected format
      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      debugPrint('Error fetching courts: $error');
      // Return empty list on error, or handle as needed
      return [];
    }
  }

  /// Retrieves courts within viewport bounds with zoom-based limiting
  static Future<List<Map<String, dynamic>>> getCourtsInBounds({
    required double northLat,
    required double southLat,
    required double eastLng,
    required double westLng,
    required double zoomLevel,
  }) async {
    try {
      // Calculate limit based on zoom level (higher zoom = more courts)
      int limit = _calculateLimitByZoom(zoomLevel);
      
      final response = await _supabase
          .from(courtsTable)
          .select('*')
          .gte('lat', southLat)
          .lte('lat', northLat)
          .gte('lon', westLng)
          .lte('lon', eastLng)
          .limit(limit);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      debugPrint('Error fetching courts in bounds: $error');
      return [];
    }
  }

  /// Calculate how many courts to show based on zoom level
  static int _calculateLimitByZoom(double zoomLevel) {
    if (zoomLevel < 10) return 20;      // City level - very few courts
    if (zoomLevel < 12) return 50;      // District level
    if (zoomLevel < 14) return 100;     // Neighborhood level
    if (zoomLevel < 16) return 200;     // Street level
    return 500;                         // Very close zoom - show more
  }

  /// Get courts with clustering for low zoom levels
  static Future<List<Map<String, dynamic>>> getCourtsWithClustering({
    required double northLat,
    required double southLat,
    required double eastLng, 
    required double westLng,
    required double zoomLevel,
  }) async {
    try {
      if (zoomLevel < 12) {
        // For low zoom, return clustered/aggregated data
        return await _getClusteredCourts(northLat, southLat, eastLng, westLng);
      } else {
        // For high zoom, return individual courts
        return await getCourtsInBounds(
          northLat: northLat,
          southLat: southLat,
          eastLng: eastLng,
          westLng: westLng,
          zoomLevel: zoomLevel,
        );
      }
    } catch (error) {
      debugPrint('Error fetching courts with clustering: $error');
      return [];
    }
  }

  /// Get clustered court data for low zoom levels
  static Future<List<Map<String, dynamic>>> _getClusteredCourts(
    double northLat, double southLat, double eastLng, double westLng) async {
    
    // This creates virtual "cluster" points representing groups of courts
    // You can adjust the grid size based on your needs
    double latStep = (northLat - southLat) / 10; // Create 10x10 grid
    double lngStep = (eastLng - westLng) / 10;
    
    List<Map<String, dynamic>> clusters = [];
    
    for (int i = 0; i < 10; i++) {
      for (int j = 0; j < 10; j++) {
        double clusterLat = southLat + (i * latStep) + (latStep / 2);
        double clusterLng = westLng + (j * lngStep) + (lngStep / 2);
        
        // Count courts in this grid cell
        final response = await _supabase
            .from(courtsTable)
            .select('cluster_id')
            .gte('lat', southLat + (i * latStep))
            .lt('lat', southLat + ((i + 1) * latStep))
            .gte('lon', westLng + (j * lngStep))
            .lt('lon', westLng + ((j + 1) * lngStep));

        int courtCount = response.length;
        
        if (courtCount > 0) {
          clusters.add({
            'id': 'cluster_${i}_$j',
            'name': '$courtCount Courts',
            'lat': clusterLat,
            'lon': clusterLng,
            'isCluster': true,
            'courtCount': courtCount,
          });
        }
      }
    }
    
    return clusters;
  }

  /// Search courts by name or location
  static Future<List<Map<String, dynamic>>> searchCourts(String query) async {
    try {
      final response = await _supabase
          .from(courtsTable)
          .select('*')
          .ilike('name', '%$query%'); // Case-insensitive search on name field
      
      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      debugPrint('Error searching courts: $error');
      return [];
    }
  }

  /// Updates court usage information
  static Future<void> updateCourtUsage(String courtId, int courtsInUse) async {
    try {
      await _supabase
          .from(courtsTable)
          .update({
            'courts_in_use': courtsInUse,
            'last_updated': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('cluster_id', courtId);
    } catch (error) {
      debugPrint('Error updating court usage: $error');
      throw Exception('Failed to update court usage');
    }
  }

  /// Get a specific court by ID
  static Future<Map<String, dynamic>?> getCourtById(String courtId) async {
    try {
      final response = await _supabase
          .from(courtsTable)
          .select('*')
          .eq('cluster_id', courtId)
          .single();
      
      return response;
    } catch (error) {
      debugPrint('Error fetching court by ID: $error');
      return null;
    }
  }

  // Keep your existing methods for partner stores and raffles
  static Future<List<Map<String, dynamic>>> getPartnerStores() async {
    // You can also move this to Supabase if needed
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      {
        'id': '1',
        'lat': 40.7614,
        'lon': -73.9776,
        'name': 'Tennis Pro Shop',
      },
    ];
  }

  static Future<void> enterRaffle(String raffleId, int tokens) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Implement raffle entry logic with Supabase
  }

  static Future<List<Map<String, dynamic>>> getRaffles() async {
    // You can also move this to Supabase if needed
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      {
        'id': '1',
        'title': 'Wilson Pro Staff RF97',
        'description': 'Professional tennis racket',
        'sponsorStore': 'Tennis Pro Shop',
        'tokensRequired': 500,
        'endDate': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
        'prize': 'Wilson Pro Staff RF97 Racket',
        'userEntries': 0,
      },
    ];
  }

  static Future<Map<String, dynamic>> getUserData() async {
    // This could also be moved to Supabase with user authentication
    await Future.delayed(const Duration(milliseconds: 300));
    return {
      'tokens': 1250,
      'email': 'user@example.com',
    };
  }

  static Future<bool> signUp({
  required String email,
  required String password,
  }) async {
    try {
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      final user = authResponse.user;
      if (user == null) {
        debugPrint('Sign-up failed: user is null');
        return false;
      }
      return true;
    } catch (error) {
      debugPrint('Error signing up: $error');
      return false;
    }
  }

  static Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = authResponse.user;
      return user != null;
    } catch (error) {
      debugPrint('Error signing in: $error');
      return false;
    }
  }

  static Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (error) {
      debugPrint('Error signing out: $error');
    }
  }

  static Future<bool> resetPassword({required String email}) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      return true;
    } catch (error) {
      debugPrint('Error sending password reset email: $error');
      return false;
    }
  }

  static User? get currentUser => _supabase.auth.currentUser;

  static Future<void> upsertUserProfile({
    required String userId,
    String? email,
    double? lastLat,
    double? lastLng,
  }) async {
    try {
      // We use upsert to only change the fields provided.
      final updates = <String, dynamic>{'id': userId};
      if (email != null) updates['email'] = email;
      if (lastLat != null) updates['last_lat'] = lastLat;
      if (lastLng != null) updates['last_lng'] = lastLng;
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

      await _supabase.from(profilesTable).upsert(updates);
    } catch (error) {
      debugPrint('Error upserting profile: $error');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> fetchUserProfile(String userId) async {
    try {
      final result = await _supabase
          .from(profilesTable)
          .select('id, email, last_lat, last_lng')
          .eq('id', userId)
          .single();
      return result as Map<String, dynamic>?;
    } catch (error) {
      debugPrint('Error fetching profile for $userId: $error');
      return null;
    }
  }

}