import 'dart:ui' as ui;
import 'package:bagel/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/courts_provider.dart';
import '../widgets/court_info_bottom_sheet.dart';
import '../models/tennis_court.dart';
import '../services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:app_settings/app_settings.dart';

class MapsScreen extends StatefulWidget {
  const MapsScreen({super.key});

  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen> {
  GoogleMapController? _mapController;
  LatLng? _userLocation;
  bool _isLocationLoaded = false;
  final Map<String, BitmapDescriptor> _markerCache = {};
  
  double _currentZoom = 12.0;
  // ignore: prefer_final_fields
  Set<Marker> _currentMarkers = {}; // Current markers displayed on map
  
  // Simple caching system
  final Map<String, TennisCourt> _allCourts = {}; // court ID -> court data
  CachedRegion? _cachedRegion; // Single cached region
  
  // Debouncing mechanism
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  bool _isSatelliteView = false;
  
  @override
  void initState() {
    super.initState();
    _initializeUser();
    _initializeLocation();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeUser() async {
    try {
      final profile = await ApiService.fetchUserProfile(
        Supabase.instance.client.auth.currentUser?.id ?? ''
      );
      
      if (profile == null) {
        debugPrint('No user profile found, using default location');
      } else {
        _userLocation = LatLng(
          profile["last_lat"] ?? 37.7749,
          profile["last_lon"] ?? -122.4194,
        );
        debugPrint('Loaded user location from profile: ${_userLocation?.latitude}, ${_userLocation?.longitude}');
        // ignore: use_build_context_synchronously
        final UserProvider userDataLoader = Provider.of<UserProvider>(context, listen: false);
        userDataLoader.loadUserData();
      }
      
      setState(() {
        _isLocationLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      _userLocation = LatLng(37.7749, -122.4194);
      setState(() {
        _isLocationLoaded = true;
      });
    }
  }

  Future<void> _initializeLocation() async {
    await _requestLocationPermission();
    await _getCurrentLocation();
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      debugPrint('Location permission granted');
    } else {
      debugPrint('Location permission denied');
    }
  }

  Future<void> _getCurrentLocation() async {
    LatLng fallbackLocation = LatLng(37.7749, -122.4194); // San Francisco

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          debugPrint('Location services are disabled.');
          setState(() {
            _userLocation = fallbackLocation;
          });
          return;
        }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        
        // Check if the permission was granted
        if (permission == LocationPermission.denied) {
            debugPrint('Location permissions are denied.');
            _userLocation = fallbackLocation;
            return;
        }
      }
      
      void _showPermissionDeniedDialog() {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Location Permission Denied'),
                content: Text(
                    'Location permissions are permanently denied. Please go to your device settings and enable location access for this app.'),
                actions: <Widget>[
                  TextButton(
                    child: Text('Open Settings'),
                    onPressed: () {
                      // Open app settings
                      openAppSettings();
                    },
                  ),
                  TextButton(
                    child: Text('Cancel'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
      }

      if (permission == LocationPermission.deniedForever) {
          // Location permissions are permanently denied
          debugPrint('Location permissions are permanently denied.');
          _showPermissionDeniedDialog(); // Optional: Show a dialog to instruct users to go to settings
          return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
      );

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await ApiService.upsertUserProfile(
          userId: user.id,
          lastLat: position.latitude,
          lastLon: position.longitude,
          username: null,
          tokens: null,
        );
      }

      if (_mapController != null && _userLocation != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_userLocation!, 15),
        );
      }

      debugPrint('User location updated: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  /// Calculate how many courts to show based on zoom level (matches ApiService logic)
  int _calculateLimitByZoom(double zoomLevel) {
    if (zoomLevel == -1) return 100000; // Used for caching
    if (zoomLevel < 6) return 25;       // Country level
    if (zoomLevel < 8) return 50;       // State level
    if (zoomLevel < 10) return 100;     // Regional level
    if (zoomLevel < 12) return 200;     // City level
    if (zoomLevel < 15) return 500;     // Neighborhood level
    if (zoomLevel < 20) return 1000;    // Street level - show all
    return 3000;                        // Very far out zoom - show more
  }

  /// Calculate distance between two points in kilometers
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth's radius in kilometers
    
    double dLat = (lat2 - lat1) * (math.pi / 180);
    double dLon = (lon2 - lon1) * (math.pi / 180);
    
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    double c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }

  // Check if current viewport needs new data
  bool _shouldFetchNewData(LatLngBounds currentViewport) {
    if (_cachedRegion == null) {
      debugPrint('No cached region - fetching new data');
      return true;
    }
    
    // Check if current viewport is contained within cached region
    bool isContained = _cachedRegion!.bounds.contains(currentViewport.southwest) &&
                      _cachedRegion!.bounds.contains(currentViewport.northeast);
    
    if (!isContained) {
      debugPrint('Viewport not contained in cached region - fetching new data');
      debugPrint('Viewport: ${currentViewport.southwest} to ${currentViewport.northeast}');
      debugPrint('Cached: ${_cachedRegion!.bounds.southwest} to ${_cachedRegion!.bounds.northeast}');
      return true;
    }
    
    // Check if cache is too old (5 minutes)
    if (DateTime.now().difference(_cachedRegion!.timestamp).inMinutes > 5) {
      debugPrint('Cache is too old - fetching new data');
      return true;
    }
    
    debugPrint('Using cached data');
    return false;
  }

  // Create expanded bounds for better caching
  LatLngBounds _createExpandedBounds(LatLngBounds viewport) {
    double latRange = viewport.northeast.latitude - viewport.southwest.latitude;
    double lngRange = viewport.northeast.longitude - viewport.southwest.longitude;
    
    // Add 50% buffer on each side
    double latBuffer = latRange * 0.5;
    double lngBuffer = lngRange * 0.5;
    
    return LatLngBounds(
      southwest: LatLng(
        viewport.southwest.latitude - latBuffer,
        viewport.southwest.longitude - lngBuffer,
      ),
      northeast: LatLng(
        viewport.northeast.latitude + latBuffer,
        viewport.northeast.longitude + lngBuffer,
      ),
    );
  }

  // Debounced version of _loadCourtsInViewport
  void _debouncedLoadCourtsInViewport() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        _loadCourtsInViewport();
      }
    });
  }

  Future<void> _loadCourtsInViewport() async {
    if (_mapController == null || !mounted) return;

    try {
      final viewport = await _mapController!.getVisibleRegion();
      debugPrint('Loading courts for viewport: ${viewport.southwest} to ${viewport.northeast}');
      debugPrint('Current zoom: $_currentZoom');

      // Get courts that should be visible in viewport
      List<TennisCourt> courtsInViewport = _getCourtsInViewport(viewport);
      debugPrint('Found ${courtsInViewport.length} courts in current viewport from cache');
      
      // Update markers incrementally
      await _updateMarkersIncrementally(courtsInViewport);

      // Check if we need to fetch new data
      if (!_shouldFetchNewData(viewport)) {
        debugPrint('Cache is sufficient, no API call needed');
        return;
      }
      
      // Fetch new data with expanded bounds
      final expandedBounds = _createExpandedBounds(viewport);
      debugPrint('Fetching courts from API with expanded bounds: ${expandedBounds.southwest} to ${expandedBounds.northeast}');
      
      final courtsData = await ApiService.getCourtsInBounds(
        northLat: expandedBounds.northeast.latitude,
        southLat: expandedBounds.southwest.latitude,
        eastLng: expandedBounds.northeast.longitude,
        westLng: expandedBounds.southwest.longitude,
        zoomLevel: _currentZoom,
      );

      debugPrint('Loaded ${courtsData.length} courts from API');
      
      // Store new courts (don't clear existing ones, merge them)
      int newCourtsAdded = 0;
      for (final courtData in courtsData) {
        final court = TennisCourt.fromJson(courtData);
        if (!_allCourts.containsKey(court.clusterId)) {
          newCourtsAdded++;
        }
        _allCourts[court.clusterId] = court;
      }
      
      debugPrint('Added $newCourtsAdded new courts to cache, total cached: ${_allCourts.length}');
      
      // Update cached region
      _cachedRegion = CachedRegion(
        bounds: expandedBounds,
        zoomLevel: _currentZoom,
        timestamp: DateTime.now(),
      );
      
      // Update markers with new data
      List<TennisCourt> updatedCourtsInViewport = _getCourtsInViewport(viewport);
      debugPrint('Found ${updatedCourtsInViewport.length} courts in viewport after API update');
      await _updateMarkersIncrementally(updatedCourtsInViewport);

    } catch (error) {
      debugPrint('Error loading courts in viewport: $error');
    }
  }

  // Incremental marker update - only add/remove/update markers that have changed
  Future<void> _updateMarkersIncrementally(List<TennisCourt> courtsToShow) async {
    if (!mounted) return;

    // Create a set of court IDs that should be visible
    final Set<String> targetCourtIds = courtsToShow.map((court) => court.clusterId).toSet();
    
    // Get current marker IDs
    final Set<String> currentMarkerIds = _currentMarkers
        .map((marker) => marker.markerId.value.replaceFirst('court_', ''))
        .toSet();

    // Find markers to remove (currently displayed but not in target)
    final Set<String> markersToRemove = currentMarkerIds.difference(targetCourtIds);
    
    // Find markers to add (in target but not currently displayed)
    final Set<String> markersToAdd = targetCourtIds.difference(currentMarkerIds);

    // Find markers that might need updating (in both sets)
    final Set<String> markersToCheck = currentMarkerIds.intersection(targetCourtIds);

    debugPrint('Marker update: Remove ${markersToRemove.length}, Add ${markersToAdd.length}, Check ${markersToCheck.length}');

    // Remove markers that are no longer needed
    if (markersToRemove.isNotEmpty) {
      _currentMarkers.removeWhere((marker) {
        final courtId = marker.markerId.value.replaceFirst('court_', '');
        return markersToRemove.contains(courtId);
      });
    }

    // Create new markers for courts to add
    for (final courtId in markersToAdd) {
      final court = courtsToShow.firstWhere((c) => c.clusterId == courtId);
      final marker = await _createSingleMarker(court);
      if (marker != null) {
        _currentMarkers.add(marker);
      }
    }

    // Check if existing markers need updates (status changes)
    for (final courtId in markersToCheck) {
      final court = courtsToShow.firstWhere((c) => c.clusterId == courtId);
      final existingMarker = _currentMarkers.firstWhere(
        (marker) => marker.markerId.value == 'court_$courtId',
      );

      // Check if marker needs updating by comparing cache key
      final newCacheKey = '${court.courtsInUse}_${court.totalCourts}_${court.status.name}';
      final currentCacheKey = _getMarkerCacheKey(existingMarker);

      if (currentCacheKey != newCacheKey) {
        _currentMarkers.remove(existingMarker);
        final newMarker = await _createSingleMarker(court);
        if (newMarker != null) {
          _currentMarkers.add(newMarker);
        }
      }
    }

    // Update the UI with new markers
    if (mounted) {
      setState(() {
        // _currentMarkers is already updated above
      });
    }
  }

  // Helper to get cache key from existing marker (we'll store this as a custom property)
  String _getMarkerCacheKey(Marker marker) {
    // Since we can't easily extract the cache key from the marker,
    // we'll use a simple approach: assume it needs updating if it's been a while
    // In a more sophisticated implementation, you could store marker metadata
    return '';
  }

  // Create a single marker for a court
  Future<Marker?> _createSingleMarker(TennisCourt court) async {
    try {
      final markerIcon = await _createModernMarker(
        courtsInUse: court.courtsInUse,
        totalCourts: court.totalCourts,
        status: court.status,
      );

      return Marker(
        markerId: MarkerId('court_${court.clusterId}'),
        position: LatLng(court.lat, court.lon),
        icon: markerIcon,
        anchor: const Offset(0.5, 0.5),
        onTap: () => _handleMarkerTap(court),
      );
    } catch (e) {
      debugPrint('Error creating marker for court ${court.name}: $e');
      return null;
    }
  }

  // Get courts that are visible in the current viewport with zoom-based limiting
  List<TennisCourt> _getCourtsInViewport(LatLngBounds viewport) {
    // First filter by viewport bounds
    List<TennisCourt> courtsInBounds = _allCourts.values.where((court) {
      return court.lat >= viewport.southwest.latitude &&
             court.lat <= viewport.northeast.latitude &&
             court.lon >= viewport.southwest.longitude &&
             court.lon <= viewport.northeast.longitude;
    }).toList();

    // Apply zoom-based limiting
    int limit = _calculateLimitByZoom(_currentZoom);
    debugPrint('Zoom level $_currentZoom allows up to $limit courts, found ${courtsInBounds.length} in bounds');
    
    if (courtsInBounds.length <= limit) {
      debugPrint('All ${courtsInBounds.length} courts within limit, showing all');
      return courtsInBounds;
    }

    // Calculate viewport center for distance-based sorting
    LatLng viewportCenter = LatLng(
      (viewport.northeast.latitude + viewport.southwest.latitude) / 2,
      (viewport.northeast.longitude + viewport.southwest.longitude) / 2,
    );

    // Sort by distance from viewport center and take the closest ones
    courtsInBounds.sort((a, b) {
      double distanceA = _calculateDistance(
        viewportCenter.latitude, viewportCenter.longitude,
        a.lat, a.lon,
      );
      double distanceB = _calculateDistance(
        viewportCenter.latitude, viewportCenter.longitude,
        b.lat, b.lon,
      );
      return distanceA.compareTo(distanceB);
    });

    List<TennisCourt> limitedCourts = courtsInBounds.take(limit).toList();
    debugPrint('Limited to ${limitedCourts.length} closest courts for zoom level $_currentZoom');
    
    return limitedCourts;
  }

  void _loadCourts() {
    final courtsProvider = Provider.of<CourtsProvider>(context, listen: false);
    courtsProvider.loadCourts();

    _cachedRegion = null;
    
    _loadCourtsInViewport();
  }

  void _refreshCourts() {
    final courtsProvider = Provider.of<CourtsProvider>(context, listen: false);
    courtsProvider.loadCourts();
    
    // Clear all cached data to force refresh
    _allCourts.clear();
    _cachedRegion = null;
    _currentMarkers.clear();
    
    _loadCourtsInViewport();
  }

  Future<BitmapDescriptor> _createModernMarker({
    required int courtsInUse,
    required int totalCourts,
    required CourtStatus status,
  }) async {
    // Create cache key
    final cacheKey = '${courtsInUse}_${totalCourts}_${status.name}';
    if (_markerCache.containsKey(cacheKey)) {
      return _markerCache[cacheKey]!;
    }

    const double size = 120; // Higher res for crisp rendering
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // 2025 vibrant colors with high contrast
    Color primaryColor;
    Color glowColor;
    switch (status) {
      case CourtStatus.empty:
        primaryColor = const Color(0xFF22C55E); // Tennis green
        glowColor = const Color(0xFF22C55E).withValues(alpha: 0.3);
        break;
      case CourtStatus.partiallyFull:
        primaryColor = const Color(0xFFEAB308); // Alertful yellow
        glowColor = const Color(0xFFEAB308).withValues(alpha: 0.3);
        break;
      case CourtStatus.full:
        primaryColor = const Color(0xFFDC2626); // STOP! red
        glowColor = const Color(0xFFDC2626).withValues(alpha: 0.3);
        break;
      case CourtStatus.noRecentReport:
        primaryColor = const Color(0xFF8B8D98); // Subtle gray
        glowColor = const Color(0xFF8B8D98).withValues(alpha: 0.3);
        break;
    }

    // Draw glow effect
    final glowPaint = Paint()
      ..color = glowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    
    canvas.drawCircle(
      Offset(size * 0.5, size * 0.5),
      size * 0.22,
      glowPaint,
    );

    // Draw main circle with modern gradient effect
    final mainPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor,
          primaryColor.withValues(alpha: 0.9),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size * 0.5, size * 0.5),
        radius: size * 0.18,
      ))
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(size * 0.5, size * 0.5),
      size * 0.18,
      mainPaint,
    );

    // Draw crisp white border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(
      Offset(size * 0.5, size * 0.5),
      size * 0.18,
      borderPaint,
    );

    // Draw ultra-crisp text
    final fractionText = '$courtsInUse/$totalCourts';
    final textPainter = TextPainter(
      text: TextSpan(
        text: fractionText,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.16,
          fontWeight: FontWeight.w700,
          fontFamily: 'SF Pro Display',
          letterSpacing: -0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    
    // Center the text with pixel-perfect alignment
    final textOffset = Offset(
      (size - textPainter.width) * 0.5,
      (size - textPainter.height) * 0.5 - 1, // Slight optical adjustment
    );
    
    textPainter.paint(canvas, textOffset);

    // Convert to high-res image then scale down for crisp display
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    
    final bitmapDescriptor = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
    
    // Cache the marker
    _markerCache[cacheKey] = bitmapDescriptor;
    
    return bitmapDescriptor;
  }

  Future<void> _handleMarkerTap(TennisCourt court) async {
    debugPrint('Marker tapped for court: ${court.name}');
    
    // Zoom to the marker first
    await _zoomToMarker(court);
    
    // Then show the court info
    _showCourtInfo(court);
  }

  Future<void> _zoomToMarker(TennisCourt court) async {
    if (_mapController == null) return;
    
    const double focusZoomLevel = 16.0; // Adjust as needed
    
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(court.lat, court.lon),
          zoom: focusZoomLevel,
        ),
      ),
    );
    
    _currentZoom = focusZoomLevel;
  }

  void _showCourtInfo(TennisCourt court) {
    showModalBottomSheet(
      context: context,
      builder: (context) => CourtInfoBottomSheet(
        court: court,
        onCourtUpdated: () {
          _loadCourts();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: !_isLocationLoaded || _userLocation == null
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.blue.withValues(alpha: 0.05),
                    Colors.white,
                  ],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Loading your location...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  onMapCreated: (controller) {
                    setState(() => _mapController = controller);
                    debugPrint('Map controller created with location: ${_userLocation!.latitude}, ${_userLocation!.longitude}');
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) _loadCourtsInViewport();
                    });
                  },
                  initialCameraPosition: CameraPosition(
                    target: _userLocation!,
                    zoom: _currentZoom,
                  ),
                  markers: _currentMarkers,
                  onCameraIdle: () {
                    debugPrint('Camera stopped moving at zoom $_currentZoom');
                    _debouncedLoadCourtsInViewport();
                  },
                  onCameraMove: (position) {
                    _currentZoom = position.zoom;
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: false,
                  mapType: _isSatelliteView ? MapType.hybrid : MapType.normal,
                  style: '''
                    [
                      {
                        "featureType": "poi",
                        "elementType": "labels.icon",
                        "stylers": [
                          {
                            "visibility": "off"
                          }
                        ]
                      },
                      {
                        "featureType": "poi.business",
                        "stylers": [
                          {
                            "visibility": "off"
                          }
                        ]
                      }
                    ]
                  ''',
                ),
                // Floating buttons in top-right, vertically aligned
                Positioned(
                  top: 6,
                  left: 10,
                  child: SafeArea(
                    child: Column(
                      children: [
                        // Refresh button
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _refreshCourts();
                            },
                            borderRadius: BorderRadius.circular(14),
                            splashColor: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                            highlightColor: const Color(0xFF3B82F6).withValues(alpha: 0.05),
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF3B82F6),
                                size: 29,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Custom location button
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _goToUserLocation();
                            },
                            borderRadius: BorderRadius.circular(14),
                            splashColor: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                            highlightColor: const Color(0xFF3B82F6).withValues(alpha: 0.05),
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.my_location_rounded,
                                color: Color(0xFF3B82F6),
                                size: 29,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Satellite toggle button
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _isSatelliteView = !_isSatelliteView;
                              });
                            },
                            borderRadius: BorderRadius.circular(14),
                            splashColor: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                            highlightColor: const Color(0xFF3B82F6).withValues(alpha: 0.05),
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: _isSatelliteView 
                                    ? const Color(0xFF3B82F6).withValues(alpha: 0.9)
                                    : Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.layers_rounded, // Changed from satellite_alt_rounded to layers_rounded
                                color: _isSatelliteView ? Colors.white : const Color(0xFF3B82F6),
                                size: 29,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _goToUserLocation() {
    if (_mapController != null && _userLocation != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _userLocation!,
            zoom: 15,
          ),
        ),
      );
    }
  }
}

// Simple cached region data structure
class CachedRegion {
  final LatLngBounds bounds;
  final double zoomLevel;
  final DateTime timestamp;
  
  CachedRegion({
    required this.bounds,
    required this.zoomLevel,
    required this.timestamp,
  });
}

// Extension to check if bounds contain another bounds
extension LatLngBoundsExtensions on LatLngBounds {
  bool contains(LatLng point) {
    return point.latitude >= southwest.latitude &&
          point.latitude <= northeast.latitude &&
          point.longitude >= southwest.longitude &&
          point.longitude <= northeast.longitude;
  }
}
