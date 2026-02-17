import 'dart:math' as math;
import 'package:flutter/material.dart';

class LocationMarker extends StatefulWidget {
  final double? rotation; // In Radians
  final bool isGpsHeading;
  final double radius;

  const LocationMarker({
    super.key,
    this.rotation,
    this.isGpsHeading = false,
    this.radius = 20,
  });

  @override
  State<LocationMarker> createState() => _LocationMarkerState();
}

class _LocationMarkerState extends State<LocationMarker> {
  double _displayRotation = 0;

  @override
  void didUpdateWidget(LocationMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rotation != null) {
      // Calculate shortest path
      double newRotation = widget.rotation!;
      // Normalize to prevent wild spinning
      // We want to reach 'newRotation' from '_displayRotation' via the shortest arc.
      // 1. Difference
      double diff = newRotation - _displayRotation;
      // 2. Normalize diff to -pi..pi
      while (diff < -math.pi) diff += 2 * math.pi;
      while (diff > math.pi) diff -= 2 * math.pi;
      // 3. Apply diff
      _displayRotation += diff;
    }
  }

  @override
  Widget build(BuildContext context) {
    // If moving with GPS heading, show ONLY the navigation arrow
    if (widget.isGpsHeading && widget.rotation != null) {
       return Transform.rotate(
          angle: _displayRotation,
          child: const Icon(Icons.navigation, color: Colors.blue, size: 30), // Solid arrow
       );
    }

    // Otherwise (Stationary/Compass), show Dot + Beam
    return SizedBox(
      width: widget.radius * 2,
      height: widget.radius * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Heading Beam (Only if we have rotation)
          if (widget.rotation != null)
             TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: _displayRotation, end: _displayRotation),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              builder: (context, angle, child) {
                return Transform.rotate(
                  angle: angle,
                  child: CustomPaint(
                    size: Size(widget.radius * 2, widget.radius * 2),
                    painter: BeamPainter(
                      color: Colors.blue.withOpacity(0.2),
                    ),
                  ),
                );
              },
            ),

          // 2. White Stroke
          Container(
            width: widget.radius,
            height: widget.radius,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),

          // 3. Blue Dot (No inner icon)
          Container(
            width: widget.radius * 0.7,
            height: widget.radius * 0.7,
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class BeamPainter extends CustomPainter {
  final Color color;

  BeamPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Beam logic remains the same
    final path = Path();
    path.moveTo(center.dx, center.dy);
    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 - math.pi / 4, 
      math.pi / 2, 
      false,
    );
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
