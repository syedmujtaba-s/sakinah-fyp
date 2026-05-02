import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dashboard_screen.dart';
import 'emotion_checkin_screen.dart';
import 'habits/habit_tracker_screen.dart';
import 'profile/profile_screen.dart';
import '../community/community.dart';
import '../widgets/sakinah_drawer.dart';

class HomeMain extends StatefulWidget {
  const HomeMain({super.key});

  @override
  State<HomeMain> createState() => _HomeMainState();
}

class _HomeMainState extends State<HomeMain> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final PageController _pageController = PageController();

  // Bottom-nav index (0..4 with 2 = check-in modal). Drives the selected
  // bottom-nav item; the swipeable PageView uses a separate page index
  // because the check-in button is not a swipeable page.
  int _currentIndex = 0;

  String _displayName = 'Seeker';
  String _email = '';
  String? _photoBase64;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadUserSummary();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadUserSummary() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _displayName = (data['firstName'] as String?) ??
            user.displayName?.split(' ').first ??
            'Seeker';
        _email = user.email ?? '';
        _photoBase64 = data['photoBase64'] as String?;
        _photoUrl = (data['photoUrl'] as String?) ?? user.photoURL;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _displayName = user.displayName?.split(' ').first ?? 'Seeker';
        _email = user.email ?? '';
      });
    }
  }

  // ── nav-index ↔ page-index mapping ─────────────────────────────────────
  // Bottom nav has 5 slots; slot 2 is the check-in button (modal route, not
  // a page). The PageView holds 4 children only — Home, Habits, Community,
  // Profile.
  int _navToPage(int navIndex) =>
      navIndex < 2 ? navIndex : navIndex - 1;

  int _pageToNav(int pageIndex) =>
      pageIndex < 2 ? pageIndex : pageIndex + 1;

  void _switchTab(int navIndex) {
    if (navIndex == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EmotionCheckinScreen()),
      );
      return;
    }
    final targetPage = _navToPage(navIndex);
    if (_pageController.hasClients &&
        (_pageController.page?.round() ?? 0) != targetPage) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    setState(() => _currentIndex = navIndex);
  }

  void _onPageChanged(int pageIndex) {
    final navIndex = _pageToNav(pageIndex);
    if (navIndex != _currentIndex) {
      setState(() => _currentIndex = navIndex);
    }
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _KeepAlive(
        child: DashboardScreen(
          onNavigateToTab: _switchTab,
          onOpenDrawer: _openDrawer,
        ),
      ),
      const _KeepAlive(child: HabitTrackerScreen()),
      const _KeepAlive(child: CommunityScreen()),
      const _KeepAlive(child: ProfileScreen()),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: SakinahDrawer(
        currentIndex: _currentIndex,
        onPrimarySelected: _switchTab,
        displayName: _displayName,
        email: _email,
        photoBase64: _photoBase64,
        photoUrl: _photoUrl,
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const ClampingScrollPhysics(),
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _switchTab,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF15803D),
          unselectedItemColor: Colors.grey.shade400,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          elevation: 0,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.task_alt_rounded),
              label: 'Habits',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF15803D),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF15803D).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                ),
              ),
              label: '',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              label: 'Community',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a PageView child alive when off-screen so its internal State (scroll
/// position, Firestore stream subscriptions, form input, etc.) survives a
/// swipe to a sibling tab and back.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
