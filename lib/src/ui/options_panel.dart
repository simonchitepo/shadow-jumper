import 'package:flutter/material.dart';

import '../core/math_structs.dart'; // RetryMode lives here

// ===============================
// Options panel widget
// ===============================

class OptionsPanel extends StatelessWidget {
  const OptionsPanel({
    super.key,
    required this.settings,
    required this.unlocked,
    required this.totalLevels,
    required this.retryMode,
    required this.onChanged,
  });

  final GameSettings settings;
  final int unlocked;
  final int totalLevels;
  final RetryMode retryMode;
  final ValueChanged<GameSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget row(String left, Widget right) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                left,
                style: const TextStyle(fontSize: 13, height: 1.2),
              ),
            ),
            right,
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(
          "On-screen touch controls",
          Switch(
            value: settings.touchControlsEnabled,
            onChanged: (v) => onChanged(settings.copyWith(touchControlsEnabled: v)),
          ),
        ),
        row(
          "HUD hint text",
          Switch(
            value: settings.showHudHint,
            onChanged: (v) => onChanged(settings.copyWith(showHudHint: v)),
          ),
        ),
        row(
          "Retry mode",
          SegmentedButton<RetryMode>(
            segments: [
              ButtonSegment(value: RetryMode.safe, label: Text("Safe")),
              ButtonSegment(value: RetryMode.fast, label: Text("Fast")),
            ],
            selected: {retryMode},
            onSelectionChanged: (s) {
              final v = s.first;
              onChanged(settings.copyWith(retryMode: v));
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Progress: $unlocked / $totalLevels unlocked",
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
        ),
      ],
    );
  }
}

@immutable
class GameSettings {
  const GameSettings({
    this.touchControlsEnabled = true,
    this.showHudHint = true,
    this.retryMode = RetryMode.safe,
  });

  final bool touchControlsEnabled;
  final bool showHudHint;
  final RetryMode retryMode;

  GameSettings copyWith({
    bool? touchControlsEnabled,
    bool? showHudHint,
    RetryMode? retryMode,
  }) {
    return GameSettings(
      touchControlsEnabled: touchControlsEnabled ?? this.touchControlsEnabled,
      showHudHint: showHudHint ?? this.showHudHint,
      retryMode: retryMode ?? this.retryMode,
    );
  }
}