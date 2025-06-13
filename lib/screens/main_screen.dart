import 'package:flutter/material.dart';
import 'maps_screen.dart';
import 'rewards_screen.dart';
import 'account_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // iOS Blue color scheme
  static const Color iosBlue = Color(0xFF007AFF);
  static const Color iosGray = Color(0xFF8E8E93);

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Maps screen is always present as the base layer
          const MapsScreen(),
          
          // Overlay screens
          if (_currentIndex == 1)
            Container(
              color: Colors.white,
              child: const RewardsScreen(),
            ),
          if (_currentIndex == 2)
            Container(
              color: Colors.white,
              child: const AccountScreen(),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
              spreadRadius: 0,
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate the available width after padding
                final availableWidth = constraints.maxWidth;
                final buttonWidth = availableWidth / 3;
                
                return Row(
                  children: [
                    _buildNavItem(0, Icons.sports_tennis_outlined, Icons.sports_tennis, 'Courts', buttonWidth),
                    _buildNavItem(1, Icons.emoji_events_outlined, Icons.emoji_events, 'Rewards', buttonWidth),
                    _buildNavItem(2, Icons.person_outline, Icons.person, 'Account', buttonWidth),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData outlinedIcon, IconData filledIcon, String label, double width) {
    final bool isSelected = _currentIndex == index;
    
    return SizedBox(
      width: width,
      height: double.infinity,
      child: GestureDetector(
        onTap: () => _onTabTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? filledIcon : outlinedIcon,
              color: isSelected ? iosBlue : iosGray,
              size: 23,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? iosBlue : iosGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}