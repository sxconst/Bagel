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

class MapsScreen extends StatefulWidget {
  const MapsScreen({super.key});

  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen> {
  GoogleMapController? _mapController;
  LatLng? _userLocation;
  bool _isLocationLoaded = false; // Add this flag
  final Map<String, BitmapDescriptor> _markerCache = {};
  
  double _currentZoom = 12.0;
  Set<Marker> _viewportMarkers = {};
  
  // Court data storage - persists individual courts once loaded
  final Map<String, TennisCourt> _loadedCourts = {}; // court ID -> court data
  final Set<String> _loadedRegions = {}; // track which regions we've already loaded
  
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
        _isLocationLoaded = true; // Set flag when location is ready
      });
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      // Fall back to default location on error
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

  Future<void> _loadCourtsInViewport() async {
    if (_mapController == null) return;
    if (!mounted) return;

    try {
      final bounds = await _mapController!.getVisibleRegion();
      debugPrint('Loading courts for bounds: ${bounds.southwest} to ${bounds.northeast}');

      // Create region key to track if we've loaded this area before
      final regionKey = _createRegionKey(bounds);
      
      // Get courts that are already in our viewport from loaded data
      List<TennisCourt> courtsInViewport = _getCourtsInBounds(bounds);
      
      // Only make API call if we haven't loaded this region before
      if (!_loadedRegions.contains(regionKey)) {
        
        debugPrint('Fetching new courts data from API for region: $regionKey');
        
        final courtsData = await ApiService.getCourtsInBounds(
          northLat: bounds.northeast.latitude,
          southLat: bounds.southwest.latitude,
          eastLng: bounds.northeast.longitude,
          westLng: bounds.southwest.longitude,
          zoomLevel: _currentZoom,
        );

        debugPrint('Loaded ${courtsData.length} new courts from API');
        
        // Store each court individually
        for (final courtData in courtsData) {
          final court = TennisCourt.fromJson(courtData);
          _loadedCourts[court.clusterId] = court;
        }
        
        // Mark this region as loaded
        _loadedRegions.add(regionKey);
        
        // Get updated list of courts in viewport
        courtsInViewport = _getCourtsInBounds(bounds);
        
      } else {
        debugPrint('Using cached court data - ${courtsInViewport.length} courts in viewport');
      }

      // Create markers for courts in current viewport
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

  // Create a region key for tracking loaded areas (larger regions to avoid too many API calls)
  String _createRegionKey(LatLngBounds bounds) {
    // Round to 2 decimal places to create larger regions (~1km precision)
    final north = (bounds.northeast.latitude * 100).round() / 100;
    final south = (bounds.southwest.latitude * 100).round() / 100;
    final east = (bounds.northeast.longitude * 100).round() / 100;
    final west = (bounds.southwest.longitude * 100).round() / 100;
    
    return '${north}_${south}_${east}_$west';
  }

  void _loadCourts() {
    final courtsProvider = Provider.of<CourtsProvider>(context, listen: false);
    courtsProvider.loadCourts();
    
    // Clear loaded data when manually refreshing to get fresh data
    _loadedCourts.clear();
    _loadedRegions.clear();
    
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

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 56, // Standard height for better proportion
        title: null,
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFF3B82F6),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
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
              ],
            ),
    );
  }
}