import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/login.dart';
import '../screens/saved_screen.dart';
import '../screens/reminders_screen.dart';
import '../screens/journal_history_screen.dart';
import '../screens/emotion_checkin_screen.dart';
import '../screens/profile/feedback_screen.dart';
import '../screens/profile/privacy_screen.dart';
import '../screens/profile/terms_screen.dart';
import '../auth/changePassword.dart';

class SakinahDrawer extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onPrimarySelected;
  final String displayName;
  final String email;
  final String? photoBase64;
  final String? photoUrl;

  const SakinahDrawer({
    super.key,
    required this.currentIndex,
    required this.onPrimarySelected,
    required this.displayName,
    required this.email,
    this.photoBase64,
    this.photoUrl,
  });

  static const _primaryItems = <_NavSpec>[
    _NavSpec(0, Icons.home_rounded, 'Home'),
    _NavSpec(1, Icons.task_alt_rounded, 'Habits'),
    _NavSpec(2, Icons.camera_alt_rounded, 'Daily Check-in'),
    _NavSpec(3, Icons.people_outline_rounded, 'Community'),
    _NavSpec(4, Icons.person_outline_rounded, 'Profile'),
  ];

  ImageProvider? get _avatarImage {
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      return MemoryImage(base64Decode(photoBase64!));
    }
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return NetworkImage(photoUrl!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      width: 304,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _sectionLabel('NAVIGATE'),
                  for (final item in _primaryItems)
                    _DrawerItem(
                      icon: item.icon,
                      label: item.label,
                      selected: currentIndex == item.index && item.index != 2,
                      onTap: () {
                        Navigator.of(context).pop();
                        if (item.index == 2) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EmotionCheckinScreen(),
                            ),
                          );
                          return;
                        }
                        onPrimarySelected(item.index);
                      },
                    ),
                  const SizedBox(height: 18),
                  _sectionLabel('JOURNEY'),
                  _DrawerItem(
                    icon: Icons.star_outline_rounded,
                    label: 'Saved Advice',
                    onTap: () => _push(context, const SavedScreen()),
                  ),
                  _DrawerItem(
                    icon: Icons.notifications_outlined,
                    label: 'Reminders',
                    onTap: () => _push(context, const RemindersScreen()),
                  ),
                  _DrawerItem(
                    icon: Icons.menu_book_rounded,
                    label: 'Journal History',
                    onTap: () => _push(context, const JournalHistoryScreen()),
                  ),
                  const SizedBox(height: 18),
                  _sectionLabel('ACCOUNT'),
                  _DrawerItem(
                    icon: Icons.lock_outline_rounded,
                    label: 'Change Password',
                    onTap: () => _push(context, const ChangePasswordPage()),
                  ),
                  _DrawerItem(
                    icon: Icons.shield_outlined,
                    label: 'Privacy Policy',
                    onTap: () => _push(context, const PrivacyScreen()),
                  ),
                  _DrawerItem(
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    onTap: () => _push(context, const TermsScreen()),
                  ),
                  _DrawerItem(
                    icon: Icons.feedback_outlined,
                    label: 'Send Feedback',
                    onTap: () => _push(context, const FeedbackScreen()),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _DrawerItem(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                danger: true,
                onTap: () => _confirmSignOut(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFDCFCE7),
            backgroundImage: _avatarImage,
            child: _avatarImage == null
                ? Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : 'S',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Sign out?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        content: const Text(
          'You can sign back in anytime to continue your reflections.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF374151),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Color(0xFFB91C1C)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }
}

class _NavSpec {
  final int index;
  final IconData icon;
  final String label;
  const _NavSpec(this.index, this.icon, this.label);
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool danger;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger
        ? const Color(0xFFB91C1C)
        : selected
            ? const Color(0xFF064E3B)
            : const Color(0xFF374151);
    final bg = selected
        ? const Color(0xFF15803D).withOpacity(0.10)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                if (selected)
                  Container(
                    width: 4,
                    height: 18,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF15803D),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                else
                  const SizedBox(width: 14),
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
