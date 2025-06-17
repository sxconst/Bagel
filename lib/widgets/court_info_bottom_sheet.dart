import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tennis_court.dart';
import '../providers/courts_provider.dart';
import '../providers/user_provider.dart';
import '../auth/auth_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';

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
  OverlayEntry? _tooltipOverlay;
  bool _isUpdating = false;
  late AnimationController _scaleController;
  late AnimationController _rippleController;
  int? _lastTappedIndex;

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
  }

  @override
  void dispose() {
    _hideTooltip();
    _scaleController.dispose();
    _rippleController.dispose();
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

  void _showTooltip(GlobalKey key, String message) {
    _hideTooltip();
    
    final RenderBox renderBox = key.currentContext?.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenWidth = MediaQuery.of(context).size.width;
    
    _tooltipOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: (screenWidth / 2) - 80, // Center horizontally
        top: position.dy + size.height + 8,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 160,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .95),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_tooltipOverlay!);

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      _hideTooltip();
    });
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

  String _getAccessMessage(String access) {
    switch (access.toLowerCase()) {
      case 'public':
        return 'Access is public';
      case 'yes':
        return 'Access is public';
      case 'private':
        return 'Access is private';
      case 'no':
        return 'Access is private';
      default:
        return 'Access is unknown';
    }
  }

  String _getSurfaceMessage(String surface) {
    switch (surface.toLowerCase()) {
      case 'acrylic':
        return 'Surface is acrylic';
      case 'painted':
        return 'Surface is painted';
      case 'concrete':
        return 'Surface is concrete';
      case 'asphalt':
        return 'Surface is asphalt';
      case 'clay':
        return 'Surface is clay';
      case 'grass':
        return 'Surface is grass';
      default:
        return 'Surface is unknown';
    }
  }

  String _getLightsMessage(bool hasLights) {
    return hasLights 
        ? 'Lights are available'
        : 'Lights are unavailable';
  }

  void _hideTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  void _openDirections() {
    // TODO: Implement opening directions in native maps app
    // This will use url_launcher to open maps with the court's coordinates
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening directions...'),
        backgroundColor: Color(0xFF007AFF),
        duration: Duration(seconds: 1),
      ),
    );
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
  
  // Use colors based on this specific button's value, not the overall court status
  final primaryColor = _getPrimaryColorForValue(index, widget.court.totalCourts);
  final glowColor = _getGlowColorForValue(index, widget.court.totalCourts);
  
  return Expanded(
    child: GestureDetector(
      onTapDown: (_) {
        _scaleController.forward();
      },
      onTapUp: (_) {
        _scaleController.reverse();
      },
      onTapCancel: () {
        _scaleController.reverse();
      },
      onTap: () => _handleUsageButtonTap(index),
      child: AnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) {
          final scale = 1.0 - (_scaleController.value * 0.05);
          return Transform.scale(
            scale: scale,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 56,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                    : LinearGradient(
                        colors: [Colors.white, Colors.grey[50]!],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected 
                      ? primaryColor 
                      : Colors.grey[300]!,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  if (isSelected) ...[
                    BoxShadow(
                      color: glowColor,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ] else ...[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ],
              ),
              child: Stack(
                children: [
                  // Ripple effect
                  if (isUpdating)
                    AnimatedBuilder(
                      animation: _rippleController,
                      builder: (context, child) {
                        return Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
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
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
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
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              shadows: isSelected ? [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ] : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (isSelected)
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                color: Colors.white,
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
    if (_isUpdating || (index == _selectedCourtsInUse && widget.court.status != CourtStatus.noRecentReport)) return;
    
    await AuthGuard.protectAsync(
      context,
      () => _performCourtUpdate(index),
      message: 'Sign in to update courts and earn 100 tokens!',
    );
  }

  @override
  Widget build(BuildContext context) {
    final accessKey = GlobalKey();
    final surfaceKey = GlobalKey();
    final lightsKey = GlobalKey();

    return Container(
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with title and directions button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.court.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Directions button
                      ElevatedButton.icon(
                        onPressed: _openDirections,
                        icon: const Icon(Icons.directions_outlined, size: 16),
                        label: const Text('Directions'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          foregroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Court detail icons and edit button row
                  Row(
                    children: [
                      // Icons section
                      Expanded(
                        child: Row(
                          children: [
                            GestureDetector(
                              key: accessKey,
                              onTap: () => _showTooltip(accessKey, _getAccessMessage(widget.court.access)),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: _getAccessColor(widget.court.access),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.lock_outline,
                                  size: 20,
                                  color: _getIconColor(_getAccessColor(widget.court.access)),
                                ),
                              ),
                            ),
                            GestureDetector(
                              key: surfaceKey,
                              onTap: () => _showTooltip(surfaceKey, _getSurfaceMessage(widget.court.surface)),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: _getSurfaceColor(widget.court.surface),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.texture,
                                  size: 20,
                                  color: _getIconColor(_getSurfaceColor(widget.court.surface)),
                                ),
                              ),
                            ),
                            GestureDetector(
                              key: lightsKey,
                              onTap: () => _showTooltip(lightsKey, _getLightsMessage(widget.court.lights)),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _getLightsColor(widget.court.lights),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.lightbulb_outline,
                                  size: 20,
                                  color: _getIconColor(_getLightsColor(widget.court.lights)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Edit button
                      ElevatedButton.icon(
                        onPressed: _showEditDialog,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Update Info'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          foregroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Text(
                    widget.court.status == CourtStatus.noRecentReport
                        ? 'No report in the last 60 minutes'
                        : 'Last updated ${widget.court.timeSinceLastUpdate} minutes ago by ${widget.court.lastUpdatedBy}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.grey,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  const Text(
                    'How many courts are in use?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Premium usage selector
                  Row(
                    children: List.generate(widget.court.totalCourts + 1, (index) {
                      return _buildPremiumUsageButton(index);
                    }),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Sign-in hint
                  if (!AuthGuard.isSignedIn) ...[
                    Text(
                      'Sign in to update courts and earn 100 tokens per report',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
      await userProvider.addTokens(100);
      await userProvider.updateNumReports();

      if (mounted) {
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Court updated successfully!'),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stars, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        '+100',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF007AFF),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
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
}