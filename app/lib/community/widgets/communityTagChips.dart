import 'package:flutter/material.dart';

class CommunityTagChips extends StatelessWidget {
  final List<String> tags;
  final int selectedTag;
  final ValueChanged<int> onTagSelected;

  const CommunityTagChips({
    super.key,
    required this.tags,
    required this.selectedTag,
    required this.onTagSelected,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF15803D); // Sakinah Green

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(tags.length, (i) {
          final isSelected = selectedTag == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                tags[i],
                style: TextStyle(
                  color: isSelected ? primaryColor : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              selected: isSelected,
              selectedColor: const Color(0xFFDCFCE7), // Light Green
              backgroundColor: Colors.white,
              onSelected: (_) => onTagSelected(i),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? primaryColor : Colors.grey.shade300,
                ),
              ),
              showCheckmark: false,
            ),
          );
        }),
      ),
    );
  }
}