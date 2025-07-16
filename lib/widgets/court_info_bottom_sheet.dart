import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tennis_court.dart';
import '../providers/courts_provider.dart';
import '../providers/user_provider.dart';
import '../auth/auth_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

class CourtInfoBottomSheet extends StatefulWidget {
  final TennisCourt court;
  final VoidCallback? onCourtUpdated;

  const CourtInfoBottomSheet({
    super.key, 
    required this.court,
    this.onCourtUpdated,
  });

  @override
  State<CourtInfoBottomSheet> createState() => _CourtInfoBottomSheetState();
}

Color _getIconColor(Color color) {
  // Use white for dark colors, black for light colors
  return color.computeLuminance() < 0.5 ? Colors.white : Colors.black;
}

String _mapAccessValue(String access) {
  switch (access.toLowerCase().trim()) {
    case 'yes':
    case 'public':
      return 'Public';
    case 'no':
    case 'private':
      return 'Private';
    default:
      return 'Public'; // Default fallback
  }
}

String _mapSurfaceValue(String surface) {
  switch (surface.toLowerCase().trim()) {
    case 'acrylic':
    case 'painted':
      return 'Acrylic';
    case 'concrete':
      return 'Concrete';
    case 'asphalt':
      return 'Asphalt';
    case 'clay':
      return 'Clay';
    case 'grass':
      return 'Grass';
    default:
      return 'Concrete'; // Default fallback
  }
}

class _CourtInfoBottomSheetState extends State<CourtInfoBottomSheet> with TickerProviderStateMixin {
  int _selectedCourtsInUse = 0;
  bool _isUpdating = false;
  bool _isDetailsExpanded = false;
  late AnimationController _scaleController;
  late AnimationController _rippleController;
  late AnimationController _expandController;
  int? _lastTappedIndex;
  
  // Add spam prevention for location error messages
  bool _isLocationErrorVisible = false;
  OverlayEntry? _locationErrorOverlay;

  @override
  void initState() {
    super.initState();
    _selectedCourtsInUse = widget.court.courtsInUse;
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _rippleController.dispose();
    _expandController.dispose();
    _locationErrorOverlay?.remove();
    super.dispose();
  }

  void _showEditDialog() {
    final nameController = TextEditingController(text: widget.court.name);
    
    // More robust value mapping with fallbacks
    String selectedAccess = _mapAccessValue(widget.court.access);
    String selectedSurface = _mapSurfaceValue(widget.court.surface);
    String selectedLights = widget.court.lights ? 'Available' : 'Unavailable';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit Court Info',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 20),
                
                _buildEditField('Court Name', nameController, Icons.sports_tennis),
                const SizedBox(height: 16),
                _buildDropdownField(
                  'Access', 
                  selectedAccess, 
                  ['Public', 'Private'], 
                  Icons.lock_outline,
                  (value) => setState(() => selectedAccess = value!)
                ),
                const SizedBox(height: 16),
                _buildDropdownField(
                  'Surface', 
                  selectedSurface, 
                  ['Acrylic', 'Concrete', 'Asphalt', 'Clay', 'Grass'], 
                  Icons.texture,
                  (value) => setState(() => selectedSurface = value!)
                ),
                const SizedBox(height: 16),
                _buildDropdownField(
                  'Lights', 
                  selectedLights, 
                  ['Available', 'Unavailable'], 
                  Icons.lightbulb_outline,
                  (value) => setState(() => selectedLights = value!)
                ),
                
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          ApiService.updateCourtDetails(
                            courtId: widget.court.clusterId,
                            userId: Supabase.instance.client.auth.currentUser?.id ?? '',
                            name: nameController.text.trim(),
                            access: selectedAccess.toLowerCase(),
                            surface: selectedSurface.toLowerCase(),
                            lights: selectedLights == 'Available' ? 'Available' : 'Unavailable',
                          );
                          widget.onCourtUpdated?.call();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Thanks for keeping court info up to date!'),
                              backgroundColor: Color(0xFF007AFF),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF007AFF)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> options, IconData icon, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF007AFF)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          items: options.map((String option) {
            return DropdownMenuItem<String>(
              value: option,
              child: Text(option),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Color _getAccessColor(String access) {
    switch (access.toLowerCase()) {
      case 'public':
        return Colors.green;
      case 'yes':
        return Colors.green;
      case 'private':
        return Colors.red;
      case 'no':
        return Colors.red;
      default:
        return Colors.grey[600]!;
    }
  }

  Color _getSurfaceColor(String surface) {
    switch (surface.toLowerCase()) {
      case 'acrylic':
        return Colors.blue;
      case 'painted':
        return Colors.blue;
      case 'concrete':
        return Colors.grey;
      case 'asphalt':
        return Colors.black;
      case 'clay':
        return const Color(0xFFD2691E); // Burnt orange
      case 'grass':
        return Colors.green;
      default:
        return Colors.grey[600]!;
    }
  }

  Color _getLightsColor(bool hasLights) {
    return hasLights 
        ? const Color(0xFFFDD835) // Easy on the eyes yellow
        : const Color(0xFF2E1065); // Midnight purple
  }

  String _getAccessText(String access) {
    switch (access.toLowerCase()) {
      case 'public':
      case 'yes':
        return 'Open to the public';
      case 'private':
      case 'no':
        return 'Closed to the public';
      default:
        return 'Unknown access';
    }
  }

  String _getSurfaceText(String surface) {
    switch (surface.toLowerCase()) {
      case 'acrylic':
        return 'Acrylic';
      case 'painted':
        return 'Painted';
      case 'concrete':
        return 'Concrete';
      case 'asphalt':
        return 'Asphalt';
      case 'clay':
        return 'Clay';
      case 'grass':
        return 'Grass';
      default:
        return 'Unknown surface';
    }
  }

  String _getLightsText(bool hasLights) {
    return hasLights ? 'Available' : 'Unavailable';
  }

  // Simple implementation using Google Maps SDK approach
  void _openDirections() async {
    final double lat = widget.court.lat;
    final double lng = widget.court.lon;
    
    // Use Google Maps URL scheme that works universally
    final String googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving';
    
    try {
      if (await canLaunchUrl(Uri.parse(googleMapsUrl))) {
        await launchUrl(
          Uri.parse(googleMapsUrl),
          mode: LaunchMode.externalApplication, // This ensures it opens in the Maps app if available
        );
      } else {
        throw 'Could not launch Google Maps';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open directions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _checkLocationPermissionAndProximity() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError('Location services are disabled. Please enable location services to report court usage.');
        return false;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Location permission denied. Please allow location access to report court usage.');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationError('Location permission permanently denied. Please enable location access in settings to report court usage.');
        return false;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Calculate distance to court
      double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        widget.court.lat,
        widget.court.lon,
      );

      if (distanceInMeters > 600000000) { // 600 million meters or 600,000 km
        _showLocationError('You must be within 1000m of the court to report usage. You are ${distanceInMeters.round()}m away.');
        return false;
      }

      return true;
    } catch (e) {
      _showLocationError('Unable to get your location. Please check your location settings and try again.');
      return false;
    }
  }

  void _showLocationError(String message) {
    // Prevent spam by checking if error is already visible
    if (_isLocationErrorVisible || !mounted) return;
    
    _isLocationErrorVisible = true;
    
    // Create overlay entry for the error message
    _locationErrorOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.location_off, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    // Insert the overlay
    Overlay.of(context).insert(_locationErrorOverlay!);
    
    // Auto-remove after duration
    Future.delayed(const Duration(seconds: 4), () {
      _locationErrorOverlay?.remove();
      _locationErrorOverlay = null;
      _isLocationErrorVisible = false;
    });
  }

  Color _getPrimaryColorForValue(int value, int totalCourts) {
    if (_isUpdating && _lastTappedIndex == value) {
      // Use the color for the selected value, regardless of court.status
      if (value == 0) return const Color(0xFF22C55E);
      if (value == totalCourts) return const Color(0xFFDC2626);
      return const Color(0xFFEAB308);
    }

    // Default fallback to court status logic
    if (widget.court.status == CourtStatus.noRecentReport) {
      return Colors.grey[300]!; // No Higlhight
    } else if (value == 0) {
      return const Color(0xFF22C55E); // Green
    } else if (value == totalCourts) {
      return const Color(0xFFDC2626); // Red
    } else {
      return const Color(0xFFEAB308); // Yellow
    }
  }

  Color _getGlowColorForValue(int value, int totalCourts) {
    if (widget.court.status == CourtStatus.noRecentReport && !(_isUpdating && _lastTappedIndex == value)) {
      return Colors.transparent;
    }

    final baseColor = _getPrimaryColorForValue(value, totalCourts);
    return baseColor.withValues(alpha: 0.3);
  }

  bool _shouldButtonAppearSelected(int index) {
     // Show as selected if:
    // 1. Currently updating this specific button, OR
    // 2. There's a recent report AND it matches the current usage
    return (_isUpdating && _lastTappedIndex == index) || 
          (widget.court.status != CourtStatus.noRecentReport && _selectedCourtsInUse == index);
  }

  Widget _buildPremiumUsageButton(int index) {
    final isSelected = _shouldButtonAppearSelected(index);
    final isUpdating = _isUpdating && _lastTappedIndex == index;
    
    final primaryColor = _getPrimaryColorForValue(index, widget.court.totalCourts);
    final glowColor = _getGlowColorForValue(index, widget.court.totalCourts);
    
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) => _scaleController.forward(),
        onTapUp: (_) => _scaleController.reverse(),
        onTapCancel: () => _scaleController.reverse(),
        onTap: () => _handleUsageButtonTap(index),
        child: AnimatedBuilder(
          animation: _scaleController,
          builder: (context, child) {
            final scale = 1.0 - (_scaleController.value * 0.03);
            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 64, // Slightly taller
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [primaryColor, primaryColor.withValues(alpha: 0.9)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : LinearGradient(
                          colors: [Colors.white, Colors.grey[50]!],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                  borderRadius: BorderRadius.circular(20), // More rounded
                  border: Border.all(
                    color: isSelected 
                        ? primaryColor 
                        : Colors.grey[300]!,
                    width: isSelected ? 2.5 : 1.5, // Slightly thicker borders
                  ),
                  boxShadow: [
                    if (isSelected) ...[
                      BoxShadow(
                        color: glowColor,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ] else ...[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ],
                ),
                child: Stack(
                  children: [
                    // Ripple effect (unchanged)
                    if (isUpdating)
                      AnimatedBuilder(
                        animation: _rippleController,
                        builder: (context, child) {
                          return Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: RadialGradient(
                                  center: Alignment.center,
                                  radius: _rippleController.value * 1.5,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.6),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    
                    // Main content
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isUpdating) ...[
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isSelected ? Colors.white : primaryColor,
                                ),
                              ),
                            ),
                          ] else ...[
                            Text(
                              '$index',
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.grey[800],
                                fontWeight: FontWeight.w800, // Heavier weight
                                fontSize: 24, // Larger text
                                shadows: isSelected ? [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    offset: const Offset(0, 1),
                                    blurRadius: 3,
                                  ),
                                ] : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (isSelected)
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleUsageButtonTap(int index) async {
    if (_isUpdating) return;
    
    if (!AuthGuard.isSignedIn) {
      await AuthGuard.protectAsync(
        context,
        () => Future.value(),
        message: 'Sign in to update courts and earn 100 tokens!',
      );
      setState(() {});
      return;
    }

    bool isWithinRange = await _checkLocationPermissionAndProximity();
    if (!isWithinRange) {
      return;
    }

    await _performCourtUpdate(index);
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color iconColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10), // Slightly larger padding
          decoration: BoxDecoration(
            color: iconColor,
            borderRadius: BorderRadius.circular(10), // More rounded
          ),
          child: Icon(
            icon,
            size: 20,
            color: _getIconColor(iconColor),
          ),
        ),
        const SizedBox(width: 16), // More space
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600, // Slightly heavier
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope (
      canPop: !_isUpdating, // Prevent back button/gesture dismiss during update
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SECTION 1: Header with title and directions
                    _buildHeaderSection(),
                    
                    const SizedBox(height: 12), // More breathing room
                    
                    // SECTION 2: Court details
                    _buildCourtDetailsSection(),
                    
                    const SizedBox(height: 14), // Clear section separation
                    
                    // SECTION 3: Usage reporting
                    _buildUsageReportingSection(),
                    
                    const SizedBox(height: 16),
                    
                    // SECTION 4: Sign-in hint (if needed)
                    if (!AuthGuard.isSignedIn) _buildSignInHint(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performCourtUpdate(int newUsageCount) async {
    setState(() {
      _isUpdating = true;
      _lastTappedIndex = newUsageCount;
      _selectedCourtsInUse = newUsageCount;
    });

    _rippleController.forward().then((_) {
      _rippleController.reset();
    });

    final courtsProvider = Provider.of<CourtsProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    try {
      await courtsProvider.updateCourtUsage(widget.court.clusterId, newUsageCount);
      
      bool tokensAwarded = false;
      if (userProvider.tokens24h < 500) {
        await userProvider.addTokens(100);
        tokensAwarded = true;
      }
      await userProvider.updateNumReports();

      if (mounted) {
        Navigator.pop(context);
        
        _showCustomSnackBar(context, tokensAwarded);
        widget.onCourtUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedCourtsInUse = widget.court.courtsInUse; // Revert on error
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Failed to update court. Please try again.'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
          _lastTappedIndex = null;
        });
      }
    }
  }

  void _showCustomSnackBar(BuildContext context, bool tokensAwarded) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).size.height * 0.11,
        left: MediaQuery.of(context).size.width * 0.4,
        right: MediaQuery.of(context).size.width * 0.4,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF),
              borderRadius: BorderRadius.circular(36),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.stars,
                  color: Colors.white,
                  size: 24,
                ),
                SizedBox(width: 6),
                Text(
                  tokensAwarded ? '+100' : '+0',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // Auto-remove after duration
    Future.delayed(Duration(milliseconds: 3000), () {
      overlayEntry.remove();
    });
  }

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.court.name,
                style: const TextStyle(
                  fontSize: 28, // Larger, more prominent
                  fontWeight: FontWeight.w700, // Heavier weight
                  color: Colors.black,
                  height: 1.1, // Tighter line height
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Improved directions button
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openDirections,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.directions_outlined, 
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Directions',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCourtDetailsSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () {
              setState(() {
                _isDetailsExpanded = !_isDetailsExpanded;
              });
              if (_isDetailsExpanded) {
                _expandController.forward();
              } else {
                _expandController.reverse();
              }
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 20, 20, 20), // Remove left padding
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Court Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _isDetailsExpanded ? 0.5 : 0, // Changed to point down when expanded
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down, // Changed from chevron_right to keyboard_arrow_down
                      color: Colors.grey[600],
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded content
          AnimatedBuilder(
            animation: _expandController,
            builder: (context, child) {
              return ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: _expandController.value,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      children: [
                        Container(
                          height: 1,
                          color: Colors.grey[200],
                          margin: const EdgeInsets.only(bottom: 20),
                        ),
                        
                        // Details grid
                        Column(
                          children: [
                            _buildDetailRow(
                              'Access',
                              _getAccessText(widget.court.access),
                              Icons.lock_outline,
                              _getAccessColor(widget.court.access),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailRow(
                              'Surface',
                              _getSurfaceText(widget.court.surface),
                              Icons.texture,
                              _getSurfaceColor(widget.court.surface),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailRow(
                              'Lights',
                              _getLightsText(widget.court.lights),
                              Icons.lightbulb_outline,
                              _getLightsColor(widget.court.lights),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Update button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _showEditDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF007AFF),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFF007AFF)),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Update Court Information',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUsageReportingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        const Text(
          'How many courts are in use?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Status with dot indicator
        Row(
          children: [
            // Status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.court.status == CourtStatus.noRecentReport 
                    ? Colors.grey[400]
                    : _getStatusColor(),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            
            // Status text
            Expanded(
              child: Text(
                widget.court.status == CourtStatus.noRecentReport
                    ? 'No reports in the last 60 minutes'
                    : 'Last updated by ${widget.court.lastUpdatedBy} ${widget.court.timeSinceLastUpdate}m ago',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 20),
        
        // Usage buttons
        Row(
          children: List.generate(widget.court.totalCourts + 1, (index) {
            return _buildPremiumUsageButton(index);
          }),
        ),
      ],
    );
  }

  Widget _buildSignInHint() {
    return InkWell(
      onTap: () async {
        await AuthGuard.protectAsync(
          context,
          () => Future.value(),
          message: 'Sign in to update courts and earn 100 tokens!',
        );
        setState(() {});
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF007AFF).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF007AFF).withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.stars_outlined,
              color: const Color(0xFF007AFF),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sign in to report court usage and earn tokens!',
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF007AFF),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (widget.court.timeSinceLastUpdate <= 15) {
      return Colors.green; // Recent report
    } else if (widget.court.timeSinceLastUpdate <= 45) {
      return Colors.orange; // Somewhat recent
    } else {
      return Colors.grey[400]!; // Old report
    }
  }
}