import 'package:flutter/material.dart';

class LocationMarker extends StatefulWidget {
  final double rotation;
  final bool isGpsHeading;
  final double radius;

  const LocationMarker({
    super.key,
    required this.rotation,
    required this.isGpsHeading,
    required this.radius,
  });

  @override
  State<LocationMarker> createState() => _LocationMarkerState();
}

class _LocationMarkerState extends State<LocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: widget.rotation,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size(widget.radius * 2, widget.radius * 2),
            painter: LocationMarkerPainter(
              isGpsHeading: widget.isGpsHeading,
              pulseValue: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

class LocationMarkerPainter extends CustomPainter {
  final bool isGpsHeading;
  final double pulseValue;

  LocationMarkerPainter({
    required this.isGpsHeading,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Pulsing Shadow / Halo
    // Expands from 0.8 to 1.2 radius, fades out
    final pulseRadius = radius * (0.8 + (0.4 * pulseValue));
    final pulseOpacity = (1.0 - pulseValue) * 0.5;
    
    final pulsePaint = Paint()
      ..color = const Color(0xFF4285F4).withOpacity(pulseOpacity)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, pulseRadius, pulsePaint);

    // 2. White Border / Background
    // Draw a static shadow for the white circle
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center + const Offset(0, 2), radius * 0.75, shadowPaint);

    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, radius * 0.75, bgPaint);

    // 3. Inner Blue Circle
    final corePaint = Paint()
      ..color = const Color(0xFF4285F4) // Python/Google Blue
      ..style = PaintingStyle.fill;
      
    canvas.drawCircle(center, radius * 0.6, corePaint);

    // 4. Direction Arrow / Beam
    // A white arrow/triangle pointing UP
    final arrowPath = Path();
    final arrowSize = radius * 0.6; // Size reference
    
    // Tip of arrow
    arrowPath.moveTo(center.dx, center.dy - arrowSize * 0.6);
    // Bottom Left
    arrowPath.lineTo(center.dx - arrowSize * 0.4, center.dy + arrowSize * 0.4);
    // Inner center point (to make it look like a stealth bomber shape / arrow)
    arrowPath.lineTo(center.dx, center.dy + arrowSize * 0.1);
    // Bottom Right
    arrowPath.lineTo(center.dx + arrowSize * 0.4, center.dy + arrowSize * 0.4);
    arrowPath.close();

    final arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
      
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant LocationMarkerPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue || 
           oldDelegate.isGpsHeading != isGpsHeading;
  }
}
