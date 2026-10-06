import 'dart:ui';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'theme.dart';

/// Halaman dengan latar gradien abu-kebiruan + cahaya buram (desain v3).
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.child, this.bottom, this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24)});
  final Widget child;
  final Widget? bottom;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(children: [
        const Positioned.fill(child: _Backdrop()),
        SafeArea(bottom: bottom == null, child: Padding(padding: padding, child: child)),
      ]),
      bottomNavigationBar: bottom,
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();
  @override
  Widget build(BuildContext context) {
    Widget orb(double x, double y, double s, Color c) => Positioned(
        left: x, top: y, child: Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: c)));
    return Stack(children: [
      const DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.bgTop, AppColors.bgBottom], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SizedBox.expand(),
      ),
      orb(-120, -80, 340, const Color(0x337DB8FF)),
      orb(200, 120, 320, const Color(0x59B9D8FF)),
      orb(-60, 520, 300, const Color(0x267DB8FF)),
      Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70), child: const SizedBox())),
    ]);
  }
}

/// Kartu kaca. [strong] = putih lebih pekat untuk konten padat.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 26, this.strong = false, this.onTap, this.border});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool strong;
  final VoidCallback? onTap;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: const [BoxShadow(color: Color(0x141E3A8A), blurRadius: 24, offset: Offset(0, 8))]),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: strong ? AppColors.glassStrong : AppColors.glass,
            shape: RoundedRectangleBorder(
                borderRadius: r, side: border?.top ?? const BorderSide(color: AppColors.glassStroke, width: 1.5)),
            child: InkWell(onTap: onTap, borderRadius: r, child: Padding(padding: padding, child: child)),
          ),
        ),
      ),
    );
  }
}

/// Kartu biru bergradien (hero, perangkat menyala, ringkasan).
class BlueCard extends StatelessWidget {
  const BlueCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.radius = 32, this.gradient = AppColors.blueGradient, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Gradient gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: gradient,
        boxShadow: [BoxShadow(color: gradient.colors.first.withValues(alpha: 0.3), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: r, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, this.size = 40, this.filled = false, this.color = AppColors.blue, this.bg});
  final IconData icon;
  final double size;
  final bool filled;
  final Color color;
  final Color? bg;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.34),
          color: filled ? null : (bg ?? AppColors.tint),
          gradient: filled ? AppColors.blueGradient : null,
        ),
        child: Icon(icon, size: size * 0.5, color: filled ? Colors.white : color),
      );
}

({Color dot, Color bg, Color ink}) levelColors(Level l) => switch (l) {
      Level.good => (dot: AppColors.green, bg: const Color(0xFFEEF3FA), ink: AppColors.ink2),
      Level.warn => (dot: AppColors.amber, bg: const Color(0x1FF5A524), ink: AppColors.amberInk),
      Level.danger => (dot: AppColors.red, bg: const Color(0x14EF4E5A), ink: AppColors.redInk),
      Level.unknown => (dot: const Color(0xFFB8C3D6), bg: const Color(0xFFEEF3FA), ink: AppColors.ink2),
    };

class StatusPill extends StatelessWidget {
  const StatusPill(this.level, this.text, {super.key});
  final Level level;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = levelColors(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c.dot, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(text, style: T.s(12, w: FontWeight.w600, c: c.ink)),
      ]),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, this.icon, this.onPressed, this.loading = false, this.trailingIcon, this.color, this.height = 60});
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final r = BorderRadius.circular(height / 2);
    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          color: color,
          gradient: color == null ? AppColors.blueGradient : null,
          boxShadow: [BoxShadow(color: (color ?? AppColors.blue).withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 10))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Center(
                child: loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 10)],
                        Flexible(child: Text(label, style: T.s(17, w: FontWeight.w600, c: Colors.white), overflow: TextOverflow.ellipsis)),
                        if (trailingIcon != null) ...[const SizedBox(width: 10), Icon(trailingIcon, color: Colors.white, size: 22)],
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton(this.label, {super.key, this.icon, this.onPressed, this.color = AppColors.blue, this.height = 56});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.line),
            shape: const StadiumBorder(),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: color, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, style: T.s(16, w: FontWeight.w600, c: color), overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton(this.icon, {super.key, this.onPressed, this.filled = false, this.size = 48, this.badge});
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final double size;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: filled ? null : AppColors.glassStrong,
      shape: CircleBorder(side: filled ? BorderSide.none : const BorderSide(color: AppColors.glassStroke, width: 1.5)),
      child: Ink(
        decoration: filled ? const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient) : null,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: 22, color: filled ? Colors.white : AppColors.ink)),
        ),
      ),
    );
    if (badge == null || badge == 0) return btn;
    return Stack(clipBehavior: Clip.none, children: [
      btn,
      Positioned(
        right: -2,
        top: -2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 2)),
          child: Text('$badge', style: T.s(11, w: FontWeight.w700, c: Colors.white)),
        ),
      ),
    ]);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.trailing});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(title, style: T.h2)),
        if (trailing != null) Text(trailing!, style: T.small),
        if (action != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(children: [
                Text(action!, style: T.s(15, w: FontWeight.w500, c: AppColors.blue)),
                const Icon(Icons.chevron_right_rounded, color: AppColors.blue, size: 20),
              ]),
            ),
          ),
      ]);
}

/// Sakelar besar (52×32) sesuai desain.
class BigSwitch extends StatelessWidget {
  const BigSwitch({super.key, required this.value, this.onChanged, this.onDark = false});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 56,
            height: 34,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              color: value ? (onDark ? Colors.white : AppColors.blue) : const Color(0xFFD8E0F5),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(shape: BoxShape.circle, color: value && onDark ? AppColors.blue : Colors.white),
            ),
          ),
        ),
      );
}

class SelectChip extends StatelessWidget {
  const SelectChip(this.label, {super.key, required this.selected, this.onTap, this.dot, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Colors.white : AppColors.glassStrong,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.blue : AppColors.glassStroke, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot != null) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 6)],
              if (icon != null) ...[Icon(icon, size: 18, color: selected ? AppColors.blue : AppColors.ink2), const SizedBox(width: 6)],
              Text(label, style: T.s(15, w: selected ? FontWeight.w600 : FontWeight.w500, c: selected ? AppColors.blue : AppColors.ink)),
            ]),
          ),
        ),
      );
}

/// Grafik batang sederhana. Batang di bawah ambang waspada diberi warna amber.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.values, this.height = 160, this.levelOf, this.maxY, this.labels = const [], this.compact = false});
  final List<double> values;
  final double height;
  final Level Function(double v)? levelOf;
  final double? maxY;
  final List<String> labels;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(height: height, child: Center(child: Text('Belum ada data', style: T.small)));
    }
    final hi = maxY ?? (values.reduce((a, b) => a > b ? a : b) * 1.15);
    return Column(children: [
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 1.5 : 2),
                child: Container(
                  height: hi <= 0 ? 0 : (v / hi).clamp(0.04, 1.0) * height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(compact ? 3 : 8), bottom: const Radius.circular(3)),
                    gradient: switch (levelOf?.call(v) ?? Level.good) {
                      Level.warn => const LinearGradient(colors: [Color(0xFFF5A524), Color(0xFFFFD27A)], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                      Level.danger => const LinearGradient(colors: [AppColors.red, Color(0xFFFF8A92)], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                      _ => const LinearGradient(colors: [AppColors.blue, AppColors.blue2], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                    },
                  ),
                ),
              ),
            ),
        ]),
      ),
      if (labels.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final l in labels) Text(l, style: T.s(11, c: AppColors.ink2))]),
      ],
    ]);
  }
}

/// Bola gradien biru — "wajah" asisten AI.
class AiOrb extends StatelessWidget {
  const AiOrb({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.3, -0.4),
            radius: 0.9,
            colors: [Colors.white, Color(0xFFBFE0FF), AppColors.blue2, AppColors.blue],
            stops: [0, 0.3, 0.65, 1],
          ),
          boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: size * 0.35, offset: Offset(0, size * 0.15))],
        ),
      );
}

class Divided extends StatelessWidget {
  const Divided({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4), this.strong = false});
  final List<Widget> children;
  final EdgeInsets padding;
  final bool strong;

  @override
  Widget build(BuildContext context) => Glass(
        padding: padding,
        strong: strong,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.line),
            children[i],
          ],
        ]),
      );
}

class ListRow extends StatelessWidget {
  const ListRow({super.key, this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.titleColor});
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: T.s(15, w: FontWeight.w600, c: titleColor ?? AppColors.ink)),
                if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: T.small)],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      );
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text)));
