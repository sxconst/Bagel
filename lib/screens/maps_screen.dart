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
  Set<Marker> _viewportMarkers = {};
  
  // Simple caching system
  final Map<String, TennisCourt> _allCourts = {}; // court ID -> court data
  CachedRegion? _cachedRegion; // Single cached region
  
  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _initializeUser();
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
        userDataLoader.loadUserData(profile["id"]);
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
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are denied.');
        setState(() {
          _userLocation = fallbackLocation;
        });
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
    
    // Check if zoom level has changed significantly (more restrictive)
    double zoomDifference = (_currentZoom - _cachedRegion!.zoomLevel).abs();
    if (zoomDifference > 1.5) {
      debugPrint('Zoom level changed significantly - fetching new data (${_cachedRegion!.zoomLevel} -> $_currentZoom)');
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

  Future<void> _loadCourtsInViewport() async {
    if (_mapController == null || !mounted) return;

    try {
      final viewport = await _mapController!.getVisibleRegion();
      debugPrint('Loading courts for viewport: ${viewport.southwest} to ${viewport.northeast}');
      debugPrint('Current zoom: $_currentZoom');

      // Always update markers from cached data first for responsiveness
      List<TennisCourt> courtsInViewport = _getCourtsInViewport(viewport);
      debugPrint('Found ${courtsInViewport.length} courts in current viewport from cache');
      
      // Update markers immediately with cached data
      Set<Marker> newMarkers = await _createCourtMarkers(courtsInViewport);
      
      if (mounted) {
        setState(() {
          _viewportMarkers = newMarkers;
        });
      }

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
      Set<Marker> updatedMarkers = await _createCourtMarkers(updatedCourtsInViewport);
      
      if (!mounted) return;
      
      setState(() {
        _viewportMarkers = updatedMarkers;
      });

    } catch (error) {
      debugPrint('Error loading courts in viewport: $error');
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
    
    // Clear all cached data to force refresh
    _allCourts.clear();
    _cachedRegion = null;
    
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

  Future<Set<Marker>> _createCourtMarkers(List<TennisCourt> courts) async {
    final Set<Marker> markers = <Marker>{};
    debugPrint('Creating markers for ${courts.length} courts');

    for (final court in courts) {
      try {
        final markerIcon = await _createModernMarker(
          courtsInUse: court.courtsInUse,
          totalCourts: court.totalCourts,
          status: court.status,
        );

        final marker = Marker(
          markerId: MarkerId('court_${court.clusterId}'),
          position: LatLng(court.lat, court.lon),
          icon: markerIcon,
          anchor: const Offset(0.5, 0.5),
          onTap: () => _handleMarkerTap(court),
        );
        
        markers.add(marker);
      } catch (e) {
        debugPrint('Error creating marker for court ${court.name}: $e');
      }
    }

    debugPrint('Successfully created ${markers.length} markers');
    return markers;
  }

  // Simplified marker tap handling
  Future<void> _handleMarkerTap(TennisCourt court) async {
    debugPrint('Marker tapped for court: ${court.name}');
    _showCourtInfo(court);
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
                    Colors.green.withValues(alpha: 0.05),
                    Colors.white,
                  ],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
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
                    // Use a small delay to ensure map is fully initialized
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) _loadCourtsInViewport();
                    });
                  },
                  initialCameraPosition: CameraPosition(
                    target: _userLocation!,
                    zoom: _currentZoom,
                  ),
                  markers: Set<Marker>.from(_viewportMarkers), // Create new set to avoid ParentDataWidget issues
                  onCameraIdle: () {
                    debugPrint('Camera stopped moving at zoom $_currentZoom');
                    _loadCourtsInViewport();
                  },
                  onCameraMove: (position) {
                    _currentZoom = position.zoom;
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
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
                // Floating refresh button in top-left
                Positioned(
                  top: 6,
                  left: 10,
                  child: SafeArea(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _loadCourts();
                        },
                        borderRadius: BorderRadius.circular(12),
                        splashColor: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                        highlightColor: const Color(0xFF3B82F6).withValues(alpha: 0.05),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(12),
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
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
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