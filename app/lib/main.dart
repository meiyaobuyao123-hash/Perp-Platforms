import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/data_page.dart';
import 'pages/discover_page.dart';
import 'pages/tools_page.dart';
import 'pages/profile_page.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const PerpToolsApp());
}

class PerpToolsApp extends StatelessWidget {
  const PerpToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Perp Tools',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    DataPage(),
    DiscoverPage(),
    ToolsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
        selectedItemColor: const Color(0xFF007AFF),
        unselectedItemColor: const Color(0xFFC7C7CC),
        selectedFontSize: 10,
        unselectedFontSize: 10,
        iconSize: 24,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: '数据',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            label: '发现',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.widgets_outlined),
            label: '工具',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
