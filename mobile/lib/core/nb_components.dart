/// Reusable Neo-Brutalist UI components for the AfterMath app.
library;

import 'package:flutter/material.dart';
import 'package:aftermath/core/app_theme.dart';

// ---------------------------------------------------------------------------
// NBCard — Card container with thick border + offset shadow
// ---------------------------------------------------------------------------

class NBCard extends StatelessWidget {
  const NBCard({
    super.key,
    required this.child,
    this.color,
    this.padding,
    this.margin,
    this.borderColor,
    this.shadow = true,
  });

  final Widget child;
  final Color? color;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color ?? AppTheme.nbCard,
        borderRadius: BorderRadius.circular(AppTheme.nbRadius),
        border: Border.all(
          color: borderColor ?? AppTheme.nbInk,
          width: AppTheme.nbBorder,
        ),
        boxShadow: shadow ? AppTheme.nbShadowSm : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NBBadge — Status badge / tag with thick border
// ---------------------------------------------------------------------------

class NBBadge extends StatelessWidget {
  const NBBadge({
    super.key,
    required this.label,
    this.color,
    this.textColor,
  });

  final String label;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppTheme.nbAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor ?? AppTheme.nbInk,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NBIconBox — Icon in a bordered box (used for feature rows, etc.)
// ---------------------------------------------------------------------------

class NBIconBox extends StatelessWidget {
  const NBIconBox({
    super.key,
    required this.icon,
    this.color,
    this.bgColor,
    this.size = 40,
  });

  final IconData icon;
  final Color? color;
  final Color? bgColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor ?? AppTheme.nbAccent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: color ?? AppTheme.nbInk,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NBSectionHeader — Section label with bold NB style
// ---------------------------------------------------------------------------

class NBSectionHeader extends StatelessWidget {
  const NBSectionHeader({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          NBIconBox(icon: icon!, size: 28, bgColor: AppTheme.nbAccent2.withValues(alpha: 0.15)),
          const SizedBox(width: 10),
        ],
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.nbInk,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// NBButton — Primary action button with NB shadow
// ---------------------------------------------------------------------------

class NBButton extends StatelessWidget {
  const NBButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.textColor,
    this.isLoading = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final Color? textColor;
  final bool isLoading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppTheme.nbInk;
    final fg = textColor ?? AppTheme.nbCard;

    final button = GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: onPressed == null
              ? bg.withValues(alpha: 0.4)
              : bg,
          borderRadius: BorderRadius.circular(AppTheme.nbRadius),
          border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
          boxShadow: onPressed == null ? null : AppTheme.nbShadowSm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: fg,
                ),
              )
            else ...[
              if (icon != null) ...[
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return expanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}
