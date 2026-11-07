import 'package:bagel/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;
import 'dart:async';

import '../providers/courts_provider.dart';
import '../widgets/court_info_bottom_sheet.dart';
import '../models/tennis_court.dart';
import '../services/api_service.dart';

class MapsScreen extends StatefulWidget {
  const MapsScreen({super.key});

  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen> {
  final MapController _mapController = MapController();
  bool _mapReady = false;

  static const LatLng _fallbackLocation = LatLng(37.7749, -122.4194);

  LatLng? _userLocation;
  bool _isLocationLoaded = false;

  double _currentZoom = 12.0;

  // Courts currently shown on the map
  List<TennisCourt> _visibleCourts = [];

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
    _initializeLocation();
    _initializeUser();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initializeUser() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      // Not signed in: skip the query (an empty id is an invalid uuid)
      if (userId == null || userId.isEmpty) {
        debugPrint('Not signed in, using default location');
      } else {
        final profile = await ApiService.fetchUserProfile(userId);
        if (profile == null) {
          debugPrint('No user profile found, using default location');
        } else {
          // Don't overwrite a fresher device location
          _userLocation ??= LatLng(
            profile["last_lat"] ?? _fallbackLocation.latitude,
            profile["last_lon"] ?? _fallbackLocation.longitude,
          );
          if (!mounted) return;
          Provider.of<UserProvider>(context, listen: false).loadUserData();
        }
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }

    if (!mounted) return;
    setState(() {
      _userLocation ??= _fallbackLocation;
      _isLocationLoaded = true;
    });
  }

  Future<void> _initializeLocation() async {
    await _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        if (mounted) setState(() => _userLocation ??= _fallbackLocation);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are denied.');
        if (mounted) setState(() => _userLocation ??= _fallbackLocation);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;

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

      if (_mapReady && _userLocation != null) {
        _mapController.move(_userLocation!, 15);
        _currentZoom = 15;
      }

      debugPrint('User location updated: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) setState(() => _userLocation ??= _fallbackLocation);
    }
  }

  /// Calculate how many courts to show based on zoom level (matches ApiService logic)
  int _calculateLimitByZoom(double zoomLevel) {
    if (zoomLevel == -1) return 100000; // Used for caching
    if (zoomLevel < 6) return 25; // Country level
    if (zoomLevel < 8) return 50; // State level
    if (zoomLevel < 10) return 100; // Regional level
    if (zoomLevel < 12) return 200; // City level
    if (zoomLevel < 15) return 500; // Neighborhood level
    if (zoomLevel < 20) return 1000; // Street level - show all
    return 3000; // Very far out zoom - show more
  }

  /// Calculate distance between two points in kilometers
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;

    double dLat = (lat2 - lat1) * (math.pi / 180);
    double dLon = (lon2 - lon1) * (math.pi / 180);

    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) *
            math.cos(lat2 * (math.pi / 180)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    double c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }

  // Check if current viewport needs new data
  bool _shouldFetchNewData(LatLngBounds currentViewport) {
    if (_cachedRegion == null) {
      debugPrint('No cached region - fetching new data');
      return true;
    }

    final cached = _cachedRegion!.bounds;
    final isContained = cached.contains(currentViewport.southWest) &&
        cached.contains(currentViewport.northEast);

    if (!isContained) {
      debugPrint('Viewport not contained in cached region - fetching new data');
      return true;
    }

    if (DateTime.now().difference(_cachedRegion!.timestamp).inMinutes > 5) {
      debugPrint('Cache is too old - fetching new data');
      return true;
    }

    return false;
  }

  // Create expanded bounds for better caching (50% buffer on each side)
  LatLngBounds _createExpandedBounds(LatLngBounds viewport) {
    final latBuffer = (viewport.north - viewport.south) * 0.5;
    final lngBuffer = (viewport.east - viewport.west) * 0.5;

    return LatLngBounds(
      LatLng(viewport.south - latBuffer, viewport.west - lngBuffer),
      LatLng(viewport.north + latBuffer, viewport.east + lngBuffer),
    );
  }

  void _debouncedLoadCourtsInViewport() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) _loadCourtsInViewport();
    });
  }

  Future<void> _loadCourtsInViewport() async {
    if (!_mapReady || !mounted) return;

    try {
      final viewport = _mapController.camera.visibleBounds;
      _currentZoom = _mapController.camera.zoom;

      // Show whatever we already have cached
      _updateVisibleCourts(_getCourtsInViewport(viewport));

      if (!_shouldFetchNewData(viewport)) return;

      final expandedBounds = _createExpandedBounds(viewport);
      final courtsData = await ApiService.getCourtsInBounds(
        northLat: expandedBounds.north,
        southLat: expandedBounds.south,
        eastLng: expandedBounds.east,
        westLng: expandedBounds.west,
        zoomLevel: _currentZoom,
      );

      debugPrint('Loaded ${courtsData.length} courts from API');

      // Merge new courts into the cache
      for (final courtData in courtsData) {
        final court = TennisCourt.fromJson(courtData);
        _allCourts[court.clusterId] = court;
      }

      _cachedRegion = CachedRegion(
        bounds: expandedBounds,
        zoomLevel: _currentZoom,
        timestamp: DateTime.now(),
      );

      _updateVisibleCourts(_getCourtsInViewport(viewport));
    } catch (error) {
      debugPrint('Error loading courts in viewport: $error');
    }
  }

  void _updateVisibleCourts(List<TennisCourt> courts) {
    if (!mounted) return;
    setState(() => _visibleCourts = courts);
  }

  // Get courts that are visible in the current viewport with zoom-based limiting
  List<TennisCourt> _getCourtsInViewport(LatLngBounds viewport) {
    final courtsInBounds = _allCourts.values.where((court) {
      return court.lat >= viewport.south &&
          court.lat <= viewport.north &&
          court.lon >= viewport.west &&
          court.lon <= viewport.east;
    }).toList();

    final limit = _calculateLimitByZoom(_currentZoom);
    if (courtsInBounds.length <= limit) return courtsInBounds;

    final centerLat = (viewport.north + viewport.south) / 2;
    final centerLon = (viewport.east + viewport.west) / 2;

    courtsInBounds.sort((a, b) {
      final distanceA = _calculateDistance(centerLat, centerLon, a.lat, a.lon);
      final distanceB = _calculateDistance(centerLat, centerLon, b.lat, b.lon);
      return distanceA.compareTo(distanceB);
    });

    return courtsInBounds.take(limit).toList();
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
    setState(() => _visibleCourts = []);

    _loadCourtsInViewport();
  }

  Color _statusColor(CourtStatus status) {
    switch (status) {
      case CourtStatus.empty:
        return const Color(0xFF22C55E); // Tennis green
      case CourtStatus.partiallyFull:
        return const Color(0xFFEAB308); // Yellow
      case CourtStatus.full:
        return const Color(0xFFDC2626); // Red
      case CourtStatus.noRecentReport:
        return const Color(0xFF8B8D98); // Gray
    }
  }

  Marker _buildCourtMarker(TennisCourt court) {
    final color = _statusColor(court.status);
    return Marker(
      key: ValueKey('court_${court.clusterId}'),
      point: LatLng(court.lat, court.lon),
      width: 46,
      height: 46,
      child: GestureDetector(
        onTap: () => _handleMarkerTap(court),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '${court.courtsInUse}/${court.totalCourts}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildUserMarker(LatLng point) {
    return Marker(
      point: point,
      width: 22,
      height: 22,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF4285F4),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMarkerTap(TennisCourt court) async {
    debugPrint('Marker tapped for court: ${court.name}');
    _zoomToMarker(court);
    _showCourtInfo(court);
  }

  void _zoomToMarker(TennisCourt court) {
    if (!_mapReady) return;
    const double focusZoomLevel = 16.0;
    _mapController.move(LatLng(court.lat, court.lon), focusZoomLevel);
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

  void _goToUserLocation() {
    if (_mapReady && _userLocation != null) {
      _mapController.move(_userLocation!, 15);
      _currentZoom = 15;
    }
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    _mapController.move(camera.center, (camera.zoom + delta).clamp(2.0, 19.0));
  }

  Widget _mapButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        splashColor: const Color(0xFF3B82F6).withValues(alpha: 0.1),
        highlightColor: const Color(0xFF3B82F6).withValues(alpha: 0.05),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: active
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
            icon,
            color: active ? Colors.white : const Color(0xFF3B82F6),
            size: 29,
          ),
        ),
      ),
    );
  }

  Widget _zoomButtons() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _zoomBy(1),
          ),
          const SizedBox(width: 30, child: Divider(height: 1)),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => _zoomBy(-1),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocationLoaded || _userLocation == null) {
      return Scaffold(
        body: Container(
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
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userLocation!,
              initialZoom: _currentZoom,
              minZoom: 2,
              maxZoom: 19,
              onMapReady: () {
                _mapReady = true;
                debugPrint(
                    'Map ready at: ${_userLocation!.latitude}, ${_userLocation!.longitude}');
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _loadCourtsInViewport();
                });
              },
              onPositionChanged: (camera, hasGesture) {
                _currentZoom = camera.zoom;
                _debouncedLoadCourtsInViewport();
              },
            ),
            children: [
              if (_isSatelliteView)
                TileLayer(
                  // Esri imagery uses {z}/{y}/{x} order
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.example.bagel',
                )
              else
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.bagel',
                ),
              MarkerLayer(
                markers: [
                  for (final court in _visibleCourts) _buildCourtMarker(court),
                  _buildUserMarker(_userLocation!),
                ],
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          // Floating buttons, top-left
          Positioned(
            top: 6,
            left: 10,
            child: SafeArea(
              child: Column(
                children: [
                  _mapButton(
                    icon: Icons.refresh_rounded,
                    onTap: _refreshCourts,
                  ),
                  const SizedBox(height: 8),
                  _mapButton(
                    icon: Icons.my_location_rounded,
                    onTap: _goToUserLocation,
                  ),
                  const SizedBox(height: 8),
                  _mapButton(
                    icon: Icons.layers_rounded,
                    active: _isSatelliteView,
                    onTap: () =>
                        setState(() => _isSatelliteView = !_isSatelliteView),
                  ),
                ],
              ),
            ),
          ),
          // Zoom controls, bottom-right
          Positioned(
            right: 10,
            bottom: 24,
            child: SafeArea(child: _zoomButtons()),
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