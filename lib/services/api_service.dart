import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  // Get the Supabase client instance
  static final SupabaseClient _supabase = Supabase.instance.client;
  
  static const String courtsTable = 'courts';
  static const String profilesTable = 'profiles';
  static const String rafflesTable = 'raffles';
  static const String raffleEntriesTable = 'raffle_entries';

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
    if (zoomLevel == -1) return 100000; // Used for caching
    if (zoomLevel < 6) return 200;       // Country level
    if (zoomLevel < 8) return 400;       // State level
    if (zoomLevel < 10) return 800;     // Regional level
    if (zoomLevel < 12) return 1200;     // City level
    if (zoomLevel < 15) return 1600;     // Neighborhood level
    if (zoomLevel < 20) return 2000;    // Street level - show all
    return 3000;                        // Very far out zoom - show more
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
      // First get the username of the user who reported
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      final userProfile = await _supabase
          .from(profilesTable)
          .select('username')
          .eq('id', user.id)
          .single();
      final username = userProfile['username'] as String;
      debugPrint(username);

      // Get the current num_reports value
      final currentData = await _supabase
          .from(courtsTable)
          .select('num_reports')
          .eq('cluster_id', courtId)
          .single();
      debugPrint(currentData.toString());
      
      final currentReports = currentData['num_reports'];
      final newReports = currentReports + 1;
      
      // Update with incremented value
      await _supabase
          .from(courtsTable)
          .update({
            'courts_in_use': courtsInUse,
            'last_updated': DateTime.now().toUtc().toIso8601String(),
            'num_reports': newReports,
            'last_updated_by': username,
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

 
  static Future<void> enterRaffle({
    required String raffleID, 
    required String userID, 
    required int entries
    }) async {
    try {
      // First try to get current entries
      final existing = await _supabase
          .from(raffleEntriesTable)
          .select('entries')
          .eq('user_id', userID)
          .eq('raffle_id', raffleID)
          .maybeSingle();
      
      if (existing != null) {
        // Row exists, update the entries
        final currentEntries = existing['entries'] as int? ?? 0;
        final newEntries = currentEntries + entries;
        
        await _supabase
            .from(raffleEntriesTable)
            .update({'entries': newEntries})
            .eq('user_id', userID)
            .eq('raffle_id', raffleID);
      } else {
        // Row doesn't exist, create new one
        await _supabase.from(raffleEntriesTable).insert({
          'user_id': userID,
          'raffle_id': raffleID,
          'entries': entries,
        }); 
      }
    } catch (error) {
      debugPrint('Error entering raffle: $error');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getRaffles() async {
    try {
      final result = await _supabase
          .from(rafflesTable)
          .select('*')
          .order('end', ascending: false)
          .limit(2); // 1 currently active raffle and the last expired raffle
      
      return List<Map<String, dynamic>>.from(result);
    } catch (error) {
      debugPrint('Error fetching raffles: $error');
      return [];
    }
  }

  static Future<(bool, User?)> signUp({
  required String email,
  required String password,
  required String username,
  }) async {
    try {
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
        },
      );
      final user = authResponse.user;
      if (user == null) {
        debugPrint('Sign-up failed: user is null');
        return (false, null);
      }
      return (true, user);
    } catch (error) {
      debugPrint('Error signing up: $error');
      return (false, null);
    }
  }

  static Future<(bool, String?)> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = authResponse.user;
      return (user != null, null);
    } catch (error) {
      debugPrint('Error signing in: $error');
      return (false, error.toString());
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

  static Future<bool> resendVerification(String email) async {
    try {
      await _supabase.auth.resend(email: email, type: OtpType.signup);
      return true;
    } catch (error) {
      debugPrint('Error resending verification email: $error');
      return false;
    }
  }

  static User? get currentUser => _supabase.auth.currentUser;

  static Future<void> upsertUserProfile({
    required String userId,
    String? email,
    double? lastLat,
    double? lastLon,
    String? username,
    int? tokens,
    int? tokens24h,
    int? reports,
    int? courtDetailsUpdated,
  }) async {
    try {
      // We use upsert to only change the fields provided.
      final updates = <String, dynamic>{'id': userId};
      if (email != null) updates['email'] = email;
      if (lastLat != null) updates['last_lat'] = lastLat;
      if (lastLon != null) updates['last_lon'] = lastLon;
      if (username != null) updates['username'] = username;
      if (tokens != null) updates['tokens'] = tokens;
      if (tokens24h != null) updates['tokens_earned_24h'] = tokens24h;
      if (reports != null) updates['reports'] = reports;
      if (courtDetailsUpdated != null) {
        updates['court_details_updated'] = courtDetailsUpdated;
      }
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
          .select('id, email, last_lat, last_lon, reports, tokens, username')
          .eq('id', userId)
          .single();
      return result as Map<String, dynamic>?;
    } catch (error) {
      debugPrint('Error fetching profile for $userId: $error');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchUsername(String userId) async {
    try {
      final result = await _supabase
          .from(profilesTable)
          .select('username')
          .eq('id', userId)
          .single();
      return result as Map<String, dynamic>?;
    } catch (error) {
      debugPrint('Error fetching username for $userId: $error');
      return null;
    }
  }
  
  /// Updates court usage information
  static Future<void> updateCourtDetails({
    required String courtId,
    required String userId,
    String? name,
    String? access,
    String? surface,
    String? lights,
  }) async {
    try {
      // Update the court details with the provided values
      await _supabase
          .from(courtsTable)
          .update({
            'name': name,
            'access': access,
            'surface': surface,
            'lights': lights == 'Available' ? true : false,
          })
          .eq('cluster_id', courtId);

      // Get the users current court_details_updated count and increment it
      final currentData = await _supabase
          .from(profilesTable)
          .select('court_details_updated')
          .eq('id', userId)
          .single();

      final currentDetails = currentData['court_details_updated'];
      final newDetails = currentDetails + 1;

      await upsertUserProfile(
        userId: userId,
        courtDetailsUpdated: newDetails,
      );

    } catch (error) {
      debugPrint('Error updating court usage: $error');
      throw Exception('Failed to update court usage');
    }
  }
}