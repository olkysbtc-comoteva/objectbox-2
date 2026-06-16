import 'package:flutter/material.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:comoteva/app_theme.dart';

@NowaGenerated()
class GlassContainer extends StatelessWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.height,
    this.width,
    this.opacity = 0.4,
    this.blur = 20,
  });

  final Widget child;

  final EdgeInsetsGeometry? padding;

  final EdgeInsetsGeometry? margin;

  final double? height;

  final double? width;

  final double opacity;

  final double blur;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      height: height,
      width: width,
      child: ClipRRect(
        borderRadius: AppTheme.squircleRadius,
        child: BackdropFilter(
          filter: ColorFilter.mode(
            Colors.black.withValues(alpha: opacity),
            BlendMode.darken,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AppTheme.surfaceGray.withValues(alpha: opacity),
              borderRadius: AppTheme.squircleRadius,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
