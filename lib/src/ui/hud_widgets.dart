import 'dart:math';
import 'package:flutter/material.dart';

// ===============================
// HUD widgets (fixed sizing)
// ===============================

class HudMini extends StatelessWidget {
  const HudMini({
    super.key,
    required this.levelNum,
    required this.totalLevels,
    required this.deaths,
    required this.exposure,
    required this.showHint,
  });

  final int levelNum;
  final int totalLevels;
  final int deaths;
  final double exposure; // 0..1
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final exp = exposure.clamp(0.0, 1.0);
    final pct = (exp * 100).round();

    return LayoutBuilder(
      builder: (context, c) {
        // If the parent gives no width constraints (rare), pick a safe width
        final barW = c.hasBoundedWidth ? c.maxWidth : 160.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.28),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 12, height: 1.15, color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _hudLine("Lv", "$levelNum / $totalLevels"),
                const SizedBox(height: 2),
                _hudLine("Deaths", "$deaths"),
                const SizedBox(height: 2),
                _hudLine("Exp", "$pct%"),
                const SizedBox(height: 6),

                // Exposure bar: background + red fill (fills as exposure increases)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    width: barW,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: barW * exp, // <-- this is the actual fill width
                          height: double.infinity,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color.fromRGBO(255, 90, 90, 0.92),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (showHint) ...[
                  const SizedBox(height: 6),
                  Text(
                    "Move: A/D or Left/Right · Jump: W/Up/Space (hold) · P pause · O options",
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.75)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hudLine(String k, String v) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: TextStyle(color: Colors.white.withOpacity(0.92))),
        Text(
          v,
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.98)),
        ),
      ],
    );
  }
}

class PauseButton extends StatelessWidget {
  const PauseButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: "Pause",
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: const Text("II", style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}

class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class TouchBtn extends StatelessWidget {
  const TouchBtn({
    super.key,
    required this.label,
    required this.onDown,
    required this.onUp,
    this.big = false,
  });

  final String label;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final size = big ? 78.0 : 64.0;

    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.26),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _BannerBtn extends StatelessWidget {
  const _BannerBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
      ),
    );
  }
}