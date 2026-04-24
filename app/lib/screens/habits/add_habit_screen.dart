import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/notification_service.dart';
import 'habit_tracker_screen.dart' show habitIconMap;

class AddHabitScreen extends StatefulWidget {
  final String? habitId;
  final Map<String, dynamic>? habitData;

  const AddHabitScreen({super.key, this.habitId, this.habitData});

  @override
  State<AddHabitScreen> createState() => _AddHabitScreenState();
}

class _AddHabitScreenState extends State<AddHabitScreen> {
  final _titleController = TextEditingController();
  String _category = 'custom';
  String _selectedIcon = 'star';
  String _selectedColor = '#15803D';
  String _frequency = 'daily';
  int _targetPerWeek = 3; // only applies when frequency == 'weekly'
  bool _saving = false;
  // Optional daily reminder time. null = no reminder.
  TimeOfDay? _reminderTime;

  bool get _isEditing => widget.habitId != null;

  final _categoryOptions = [
    {'value': 'prayer', 'label': 'Prayer'},
    {'value': 'quran', 'label': 'Quran'},
    {'value': 'dhikr', 'label': 'Dhikr'},
    {'value': 'wellness', 'label': 'Wellness'},
    {'value': 'custom', 'label': 'Custom'},
  ];

  final _colorOptions = [
    '#15803D', // Green
    '#2563EB', // Blue
    '#7C3AED', // Purple
    '#EA580C', // Orange
    '#0D9488', // Teal
    '#DC2626', // Red
    '#D97706', // Amber
    '#4F46E5', // Indigo
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing && widget.habitData != null) {
      _titleController.text = widget.habitData!['title'] ?? '';
      _category = widget.habitData!['category'] ?? 'custom';
      _selectedIcon = widget.habitData!['icon'] ?? 'star';
      _selectedColor = widget.habitData!['color'] ?? '#15803D';
      _frequency = widget.habitData!['frequency'] ?? 'daily';
      final tpw = widget.habitData!['targetPerWeek'];
      if (tpw is int && tpw >= 1 && tpw <= 7) _targetPerWeek = tpw;
      final h = widget.habitData!['reminderHour'];
      final m = widget.habitData!['reminderMinute'];
      if (h is int && m is int && h >= 0 && h < 24 && m >= 0 && m < 60) {
        _reminderTime = TimeOfDay(hour: h, minute: m);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF15803D);
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a habit name')),
      );
      return;
    }

    setState(() => _saving = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final data = <String, dynamic>{
      'title': title,
      'category': _category,
      'icon': _selectedIcon,
      'color': _selectedColor,
      'frequency': _frequency,
      'isActive': true,
      if (_frequency == 'weekly') 'targetPerWeek': _targetPerWeek,
      if (_reminderTime != null) 'reminderHour': _reminderTime!.hour,
      if (_reminderTime != null) 'reminderMinute': _reminderTime!.minute,
    };

    try {
      String habitId;
      if (_isEditing) {
        // On edit, explicitly clear fields that should no longer apply.
        if (_frequency != 'weekly') data['targetPerWeek'] = FieldValue.delete();
        if (_reminderTime == null) {
          data['reminderHour'] = FieldValue.delete();
          data['reminderMinute'] = FieldValue.delete();
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('habits')
            .doc(widget.habitId)
            .update(data);
        habitId = widget.habitId!;
      } else {
        final ref = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('habits')
            .add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
        habitId = ref.id;
      }

      // Schedule/cancel the local reminder to match the doc's current state.
      if (_reminderTime != null) {
        await NotificationService.instance.requestPermission();
        await NotificationService.instance.scheduleHabitReminder(
          habitId: habitId,
          habitTitle: title,
          hour: _reminderTime!.hour,
          minute: _reminderTime!.minute,
        );
      } else {
        await NotificationService.instance.cancelHabitReminder(habitId);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Habit' : 'New Habit',
          style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF15803D)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Text('Habit Name', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'e.g. Read Quran daily',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF15803D), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Category
            const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categoryOptions.map((opt) {
                final selected = _category == opt['value'];
                return ChoiceChip(
                  label: Text(opt['label']!),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = opt['value']!),
                  selectedColor: const Color(0xFFDCFCE7),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? const Color(0xFF15803D) : const Color(0xFF6B7280),
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: selected ? const Color(0xFF15803D) : Colors.grey.shade300,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Icon Picker
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: habitIconMap.entries.map((entry) {
                  final selected = _selectedIcon == entry.key;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = entry.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected
                            ? _parseColor(_selectedColor).withOpacity(0.15)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                        border: selected
                            ? Border.all(color: _parseColor(_selectedColor), width: 2)
                            : null,
                      ),
                      child: Icon(
                        entry.value,
                        size: 22,
                        color: selected ? _parseColor(_selectedColor) : const Color(0xFF6B7280),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Color Picker
            const Text('Color', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: _colorOptions.map((hex) {
                final selected = _selectedColor == hex;
                final color = _parseColor(hex);
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = hex),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: selected
                          ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Frequency
            const Text('Frequency', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildFreqChip('Daily', 'daily'),
                const SizedBox(width: 12),
                _buildFreqChip('Weekly', 'weekly'),
              ],
            ),

            // Weekly target picker — how many times per week counts as success
            if (_frequency == 'weekly') ...[
              const SizedBox(height: 20),
              const Text(
                'Target per week',
                style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151)),
              ),
              const SizedBox(height: 4),
              const Text(
                'A week is successful when you complete this many days.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: List.generate(7, (i) {
                  final target = i + 1;
                  final selected = _targetPerWeek == target;
                  return ChoiceChip(
                    label: Text('$target × /week'),
                    selected: selected,
                    onSelected: (_) => setState(() => _targetPerWeek = target),
                    selectedColor: const Color(0xFFDCFCE7),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selected ? const Color(0xFF15803D) : const Color(0xFF6B7280),
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: selected ? const Color(0xFF15803D) : Colors.grey.shade300,
                      ),
                    ),
                  );
                }),
              ),
            ],
            const SizedBox(height: 24),

            // Reminder time — optional; when set, schedules a daily local notification
            const Text(
              'Daily reminder',
              style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _reminderTime ?? const TimeOfDay(hour: 8, minute: 0),
                      );
                      if (picked != null) {
                        setState(() => _reminderTime = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm_rounded,
                              size: 18, color: Color(0xFF15803D)),
                          const SizedBox(width: 8),
                          Text(
                            _reminderTime == null
                                ? 'No reminder'
                                : _reminderTime!.format(context),
                            style: TextStyle(
                              fontSize: 14,
                              color: _reminderTime == null
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF1F2937),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded,
                              size: 18, color: Color(0xFF9CA3AF)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_reminderTime != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Clear reminder',
                    onPressed: () => setState(() => _reminderTime = null),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF6B7280)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 40),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        _isEditing ? 'Save Changes' : 'Create Habit',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreqChip(String label, String value) {
    final selected = _frequency == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _frequency = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFDCFCE7) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF15803D) : Colors.grey.shade300,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? const Color(0xFF15803D) : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
