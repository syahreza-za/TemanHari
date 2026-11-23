import 'package:flutter/material.dart';

class MoodOption {
  const MoodOption({
    required this.key,
    required this.label,
    required this.emoji,
    required this.score,
  });

  final String key;
  final String label;
  final String emoji;
  final int score;
}

const kMoodOptions = <MoodOption>[
  MoodOption(key: 'senang', label: 'Senang', emoji: '😊', score: 5),
  MoodOption(key: 'semangat', label: 'Semangat', emoji: '✨', score: 5),
  MoodOption(key: 'tenang', label: 'Tenang', emoji: '😌', score: 4),
  MoodOption(key: 'lelah', label: 'Lelah', emoji: '😮‍💨', score: 2),
  MoodOption(key: 'cemas', label: 'Cemas', emoji: '😟', score: 2),
  MoodOption(key: 'sedih', label: 'Sedih', emoji: '🥺', score: 1),
];

class MoodCheckinBar extends StatelessWidget {
  const MoodCheckinBar({
    super.key,
    required this.selectedMood,
    required this.onMoodSelected,
  });

  final String? selectedMood;
  final void Function(MoodOption mood) onMoodSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Gimana perasaanmu saat ini?',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: kMoodOptions.map((option) {
                final isSelected = selectedMood == option.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: isSelected,
                    showCheckmark: false,
                    label: Text('${option.emoji} ${option.label}'),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    selectedColor: scheme.primary.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: isSelected
                          ? scheme.primary
                          : scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    onSelected: (_) => onMoodSelected(option),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
