import 'dart:ui' as ui;
import 'dart:math' as math;
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
  
  // Court data storage - persists individual courts once loaded
  final Map<String, TennisCourt> _loadedCourts = {}; // court ID -> court data
  
  // Grid-based region tracking
  final Map<String, LatLngBounds> _loadedGridCells = {}; // grid cell -> bounds
  static const double _gridSizeKm = 2.0; // 2km grid cells
  static const double _overlapThreshold = 0.7; // 70% overlap to avoid reload
  
  @override
  void initState() {
    super.initState();
    _initializeUser();
    _initializeLocation();
  }

  Future<void> _initializeUser() async {
    try {
      final profile = await ApiService.fetchUserProfile(
        Supabase.instance.client.auth.currentUser?.id ?? ''
      );
      
      if (profile == null) {
        debugPrint('No user profile found, using default location');
        _userLocation = LatLng(37.7749, -122.4194); // Default to San Francisco
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
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are denied');
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high)
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

  // Convert latitude/longitude to grid coordinates
  _GridCoordinate _latLngToGridCoordinate(double lat, double lng) {
    // Each degree of latitude is approximately 111 km
    // Each degree of longitude varies by latitude but we'll use an approximation
    const double kmPerDegreeLat = 111.0;
    final double kmPerDegreeLng = 111.0 * math.cos(lat * math.pi / 180);
    
    final int gridX = (lng * kmPerDegreeLng / _gridSizeKm).floor();
    final int gridY = (lat * kmPerDegreeLat / _gridSizeKm).floor();
    
    return _GridCoordinate(gridX, gridY);
  }

  // Convert grid coordinate back to lat/lng bounds
  LatLngBounds _gridCoordinateToLatLngBounds(_GridCoordinate coord) {
    const double kmPerDegreeLat = 111.0;
    final double avgLat = 40.0; // Use average latitude for longitude calculation
    final double kmPerDegreeLng = 111.0 * math.cos(avgLat * math.pi / 180);
    
    final double minLat = coord.y * _gridSizeKm / kmPerDegreeLat;
    final double maxLat = (coord.y + 1) * _gridSizeKm / kmPerDegreeLat;
    final double minLng = coord.x * _gridSizeKm / kmPerDegreeLng;
    final double maxLng = (coord.x + 1) * _gridSizeKm / kmPerDegreeLng;
    
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // Get all grid cells that overlap with the current viewport
  Set<_GridCoordinate> _getGridCellsForBounds(LatLngBounds bounds) {
    final Set<_GridCoordinate> gridCells = {};
    
    final swGrid = _latLngToGridCoordinate(bounds.southwest.latitude, bounds.southwest.longitude);
    final neGrid = _latLngToGridCoordinate(bounds.northeast.latitude, bounds.northeast.longitude);
    
    // Add all grid cells that intersect with the viewport
    for (int x = swGrid.x; x <= neGrid.x; x++) {
      for (int y = swGrid.y; y <= neGrid.y; y++) {
        gridCells.add(_GridCoordinate(x, y));
      }
    }
    
    return gridCells;
  }

  // Calculate how much area overlap exists between two bounds
  double _calculateBoundsOverlap(LatLngBounds bounds1, LatLngBounds bounds2) {
    final double overlapNorth = math.min(bounds1.northeast.latitude, bounds2.northeast.latitude);
    final double overlapSouth = math.max(bounds1.southwest.latitude, bounds2.southwest.latitude);
    final double overlapEast = math.min(bounds1.northeast.longitude, bounds2.northeast.longitude);
    final double overlapWest = math.max(bounds1.southwest.longitude, bounds2.southwest.longitude);
    
    if (overlapNorth <= overlapSouth || overlapEast <= overlapWest) {
      return 0.0; // No overlap
    }
    
    final double overlapArea = (overlapNorth - overlapSouth) * (overlapEast - overlapWest);
    final double bounds1Area = (bounds1.northeast.latitude - bounds1.southwest.latitude) * 
                              (bounds1.northeast.longitude - bounds1.southwest.longitude);
    
    return overlapArea / bounds1Area;
  }

  // Check if we need to load new data for the current viewport
  bool _shouldLoadNewData(LatLngBounds currentBounds) {
    if (_loadedGridCells.isEmpty) return true;
    
    // Check if current viewport has sufficient overlap with any loaded region
    for (final loadedBounds in _loadedGridCells.values) {
      final overlap = _calculateBoundsOverlap(currentBounds, loadedBounds);
      if (overlap >= _overlapThreshold) {
        debugPrint('Found sufficient overlap (${overlap.toStringAsFixed(2)}) with loaded region');
        return false;
      }
    }
    
    return true;
  }

  // Create expanded bounds with buffer for better caching
  LatLngBounds _createExpandedBounds(LatLngBounds bounds) {
    const double bufferFactor = 0.3; // 30% buffer on each side
    
    final double latBuffer = (bounds.northeast.latitude - bounds.southwest.latitude) * bufferFactor;
    final double lngBuffer = (bounds.northeast.longitude - bounds.southwest.longitude) * bufferFactor;
    
    return LatLngBounds(
      southwest: LatLng(
        bounds.southwest.latitude - latBuffer,
        bounds.southwest.longitude - lngBuffer,
      ),
      northeast: LatLng(
        bounds.northeast.latitude + latBuffer,
        bounds.northeast.longitude + lngBuffer,
      ),
    );
  }

  Future<void> _loadCourtsInViewport() async {
    if (_mapController == null) return;
    if (!mounted) return;

    try {
      final bounds = await _mapController!.getVisibleRegion();
      debugPrint('Loading courts for bounds: ${bounds.southwest} to ${bounds.northeast}');

      // Check if we need to load new data
      if (!_shouldLoadNewData(bounds)) {
        debugPrint('Using cached data - sufficient overlap found');
        List<TennisCourt> courtsInViewport = _getCourtsInBounds(bounds);
        Set<Marker> newMarkers = await _createCourtMarkers(courtsInViewport);
        
        if (!mounted) return;
        setState(() {
          _viewportMarkers = newMarkers;
        });
        return;
      }
      
      // Create expanded bounds for better caching
      final expandedBounds = _createExpandedBounds(bounds);
      
      debugPrint('Fetching new courts data from API');
      
      final courtsData = await ApiService.getCourtsInBounds(
        northLat: expandedBounds.northeast.latitude,
        southLat: expandedBounds.southwest.latitude,
        eastLng: expandedBounds.northeast.longitude,
        westLng: expandedBounds.southwest.longitude,
        zoomLevel: _currentZoom,
      );

      debugPrint('Loaded ${courtsData.length} courts from API');
      
      // Store each court individually
      for (final courtData in courtsData) {
        final court = TennisCourt.fromJson(courtData);
        _loadedCourts[court.clusterId] = court;
      }
      
      // Mark the grid cells as loaded
      final gridCells = _getGridCellsForBounds(expandedBounds);
      for (final cell in gridCells) {
        final cellBounds = _gridCoordinateToLatLngBounds(cell);
        _loadedGridCells['${cell.x}_${cell.y}'] = cellBounds;
      }
      
      // Get courts in current viewport and create markers
      List<TennisCourt> courtsInViewport = _getCourtsInBounds(bounds);
      Set<Marker> newMarkers = await _createCourtMarkers(courtsInViewport);
      
      if (!mounted) return;
      
      setState(() {
        _viewportMarkers = newMarkers;
      });

    } catch (error) {
      debugPrint('Error loading courts in viewport: $error');
    }
  }

  // Get all loaded courts that fall within the given bounds
  List<TennisCourt> _getCourtsInBounds(LatLngBounds bounds) {
    return _loadedCourts.values.where((court) {
      return court.lat >= bounds.southwest.latitude &&
             court.lat <= bounds.northeast.latitude &&
             court.lon >= bounds.southwest.longitude &&
             court.lon <= bounds.northeast.longitude;
    }).toList();
  }

  void _loadCourts() {
    final courtsProvider = Provider.of<CourtsProvider>(context, listen: false);
    courtsProvider.loadCourts();
    
    // Clear loaded data when manually refreshing to get fresh data
    _loadedCourts.clear();
    _loadedGridCells.clear();
    
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
    final markers = <Marker>{};
    debugPrint('Creating markers for ${courts.length} courts');

    for (final court in courts) {
      try {
        final markerIcon = await _createModernMarker(
          courtsInUse: court.courtsInUse,
          totalCourts: court.totalCourts,
          status: court.status,
        );

        // Add onTap handler that finds the nearest court to the marker position
        markers.add(
          Marker(
            markerId: MarkerId('court_${court.clusterId}'),
            position: LatLng(court.lat, court.lon),
            icon: markerIcon,
            anchor: const Offset(0.5, 0.5),
            onTap: () => _handleMarkerTap(LatLng(court.lat, court.lon)),
          ),
        );
      } catch (e) {
        debugPrint('Error creating marker for court ${court.name}: $e');
      }
    }

    debugPrint('Created total ${markers.length} markers');
    return markers;
  }

  // Handle marker taps by finding the closest court to the marker position
  Future<void> _handleMarkerTap(LatLng markerPosition) async {
    debugPrint('=== MARKER TAP DETECTED ===');
    debugPrint('Marker position: ${markerPosition.latitude}, ${markerPosition.longitude}');
    
    if (_mapController == null) {
      debugPrint('Map controller is null');
      return;
    }

    const double maxDistanceMeters = 10.0; // Very small distance for exact matches
    
    try {
      // Get current viewport bounds to only check visible courts
      final bounds = await _mapController!.getVisibleRegion();
      final visibleCourts = _getCourtsInBounds(bounds);
      debugPrint('Checking ${visibleCourts.length} visible courts');
      
      TennisCourt? exactMatch;
      double nearestDistance = double.infinity;
      
      // Find the court that exactly matches this marker position
      for (final court in visibleCourts) {
        final distance = Geolocator.distanceBetween(
          markerPosition.latitude,
          markerPosition.longitude,
          court.lat,
          court.lon,
        );
        
        if (distance <= maxDistanceMeters && distance < nearestDistance) {
          nearestDistance = distance;
          exactMatch = court;
        }
      }
      
      if (exactMatch != null) {
        _showCourtInfo(exactMatch);
      } else {
        // Fallback: just use the first court in the list as this shouldn't happen
        if (visibleCourts.isNotEmpty) {
          _showCourtInfo(visibleCourts.first);
        }
      }
      
    } catch (e) {
      debugPrint('Error in marker tap handling: $e');
    }
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
                    _loadCourtsInViewport();
                  },
                  initialCameraPosition: CameraPosition(
                    target: _userLocation!,
                    zoom: _currentZoom,
                  ),
                  markers: _viewportMarkers,
                  onCameraIdle: () {
                    debugPrint('Camera stopped moving, loading new markers');
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
                SafeArea(
                  child: Positioned(
                    top: 16,
                    left: 16,
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

// Helper class for grid coordinates
class _GridCoordinate {
  final int x;
  final int y;
  
  _GridCoordinate(this.x, this.y);
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _GridCoordinate &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
  
  @override
  String toString() => 'GridCoordinate($x, $y)';
}