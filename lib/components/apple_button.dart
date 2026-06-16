import 'package:flutter/material.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:comoteva/app_theme.dart';

@NowaGenerated()
class AppleButton extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const AppleButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.color = AppTheme.appleBlue,
  });

  final String text;

  final void Function() onPressed;

  final bool isLoading;

  final Color color;

  @override
  State<AppleButton> createState() {
    return _AppleButtonState();
  }
}

@NowaGenerated()
class _AppleButtonState extends State<AppleButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.isLoading ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: AppTheme.squircleRadius,
          ),
          alignment: Alignment.center,
          child: widget.isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
