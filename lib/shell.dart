import 'package:flutter/material.dart';

// Relative imports are safer regardless of the pubspec name.
import 'screens/home_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/courses_screen.dart';
import 'screens/profile_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0; // which nav item is selected

  // Pages to switch between (kept alive via IndexedStack)
  final _pages = const [
    HomeScreen(),
    CoursesScreen(),
    CalendarScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Keep each tab's state alive
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Courses'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}