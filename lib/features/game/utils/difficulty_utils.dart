/// Shared helpers for translating difficulty keys, display labels, and speed tuning.

/// Canonical ordered list for fixed difficulty levels (non-adaptive).
const List<String> kDifficultySequence = ['easy', 'medium', 'hard', 'veryHard'];

/// Display labels for user-facing UI and logs.
const Map<String, String> _difficultyDisplayNames = {
  'easy': 'Easy',
  'medium': 'Medium',
  'hard': 'Difficult',
  'veryHard': 'Very Difficult',
  'adaptive': 'Adaptive',
  'adaptiveFast': 'Adaptive – Fast',
};

/// Speed multipliers applied relative to the medium baseline speed.
const Map<String, double> difficultySpeedMultipliers = {
  'easy': 0.85,
  'medium': 1.2,
  'hard': 1.45,
  'veryHard': 1.65,
};

/// Returns the best display name for a given difficulty key.
String displayDifficultyName(String key) {
  return _difficultyDisplayNames[key] ?? _fallbackTitleCase(key);
}

/// Bounds lookup into [kDifficultySequence] and returns the matching key.
String difficultyKeyForIndex(int index) {
  if (kDifficultySequence.isEmpty) {
    return 'easy';
  }
  final clamped = index.clamp(0, kDifficultySequence.length - 1);
  return kDifficultySequence[clamped];
}

/// Returns the speed multiplier for the provided difficulty key.
double getDifficultySpeedMultiplier(String key) {
  return difficultySpeedMultipliers[key] ?? 1.0;
}

String _fallbackTitleCase(String raw) {
  if (raw.isEmpty) return raw;
  final parts = raw
      .replaceAll(RegExp(r'[_-]'), ' ')
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return raw;
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.isEmpty) continue;
    final lower = part.toLowerCase();
    buffer.write(lower[0].toUpperCase());
    if (lower.length > 1) {
      buffer.write(lower.substring(1));
    }
    if (i < parts.length - 1) buffer.write(' ');
  }
  return buffer.toString();
}

/// Utility to clamp an adaptive difficulty level to the known sequence and return the key.
String adaptiveKeyForLevel(int level) {
  return difficultyKeyForIndex(level);
}

/// Applies the adaptive slider multiplier to the base difficulty multiplier.
double composeAdaptiveMultiplier({
  required int level,
  required double sliderMultiplier,
}) {
  final base = getDifficultySpeedMultiplier(adaptiveKeyForLevel(level));
  final slider = sliderMultiplier.clamp(0.1, 4.0);
  return (base * slider).clamp(0.05, 10.0);
}

/// Converts a difficulty key into its ordinal index within [kDifficultySequence].
int indexForDifficultyKey(String key) {
  final idx = kDifficultySequence.indexOf(key);
  return idx >= 0 ? idx : 0;
}

/// Attempts to map arbitrary user-visible labels or stored values back to a canonical key.
String? difficultyKeyFromRaw(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  final simple = cleaned.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  switch (simple) {
    case 'easy':
      return 'easy';
    case 'medium':
      return 'medium';
    case 'hard':
    case 'difficult':
      return 'hard';
    case 'veryhard':
    case 'verydifficult':
      return 'veryHard';
    case 'adaptive':
      return 'adaptive';
    case 'adaptivefast':
      return 'adaptiveFast';
    default:
      return null;
  }
}

/// Converts any stored/string difficulty into a display label.
String displayDifficultyFromRaw(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Unknown';
  }
  final key = difficultyKeyFromRaw(raw);
  if (key != null) {
    return displayDifficultyName(key);
  }
  return displayDifficultyName(raw.trim());
}
