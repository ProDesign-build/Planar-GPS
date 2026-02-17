import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vector;
import 'package:geolocator/geolocator.dart';

/// A service to map real-world GPS coordinates (represented as [Point] x=lat, y=lng)
/// to PDF 2D Cartesian coordinates.
///
/// Uses a 2-point calibration system to determine Scale, Rotation, and Translation.
/// Assumes a scalable, rotatable, but aspect-ratio-preserving projection (Similarity Transformation),
/// which is valid for architectural scales (small geographic areas).
class CoordinateMapper extends ChangeNotifier {
  static final CoordinateMapper _instance = CoordinateMapper._internal();
  factory CoordinateMapper() => _instance;
  CoordinateMapper._internal();

  Point<double>? _gpsRef1;
  Point<double>? _pdfRef1;
  Point<double>? _gpsRef2;
  Point<double>? _pdfRef2;
  Point<double>? _gpsRef3;
  Point<double>? _pdfRef3;

  Point<double>? get gpsRef1 => _gpsRef1;
  Point<double>? get pdfRef1 => _pdfRef1;
  Point<double>? get gpsRef2 => _gpsRef2;
  Point<double>? get pdfRef2 => _pdfRef2;
  Point<double>? get gpsRef3 => _gpsRef3;
  Point<double>? get pdfRef3 => _pdfRef3;

  bool get isCalibrated =>
      _gpsRef1 != null && _pdfRef1 != null && 
      _gpsRef2 != null && _pdfRef2 != null &&
      _gpsRef3 != null && _pdfRef3 != null;

  /// Sets the calibration points (3-point affine transformation).
  void setCalibration({
    required Point<double> gps1,
    required Point<double> pdf1,
    required Point<double> gps2,
    required Point<double> pdf2,
    required Point<double> gps3,
    required Point<double> pdf3,
  }) {
    debugPrint("CoordinateMapper: Setting new calibration points...");
    _gpsRef1 = gps1;
    _pdfRef1 = pdf1;
    _gpsRef2 = gps2;
    _pdfRef2 = pdf2;
    _gpsRef3 = gps3;
    _pdfRef3 = pdf3;
    
    debugPrint("CoordinateMapper: Calibration set. Notifying listeners.");
    notifyListeners();
  }

  /// Clears the calibration data.
  void clearCalibration() {
    debugPrint("CoordinateMapper: Clearing calibration.");
    _gpsRef1 = null;
    _pdfRef1 = null;
    _gpsRef2 = null;
    _pdfRef2 = null;
    _gpsRef3 = null;
    _pdfRef3 = null;
    notifyListeners();
  }

  /// Converts a Lat/Lng point to PDF X/Y coordinates using affine transformation.
  /// Returns null if not calibrated.
  Point<double>? gpsToPdf({required double latitude, required double longitude}) {
    if (!isCalibrated) return null;

    // Use a standard Cartesian mapping for GPS:
    // X = Longitude, Y = Latitude
    Point<double> gpsPoint(double lat, double lng) => Point(lng, lat);

    Point<double> p1Gps = gpsPoint(_gpsRef1!.x, _gpsRef1!.y);
    Point<double> p2Gps = gpsPoint(_gpsRef2!.x, _gpsRef2!.y);
    Point<double> p3Gps = gpsPoint(_gpsRef3!.x, _gpsRef3!.y);

    Point<double> inputGps = gpsPoint(latitude, longitude);

    // Calculate affine transformation matrix using 3 point pairs
    // We solve for: pdf_x = a*gps_x + b*gps_y + tx
    //               pdf_y = c*gps_x + d*gps_y + ty
    //
    // This gives us 6 equations (2 per point) for 6 unknowns (a, b, c, d, tx, ty)
    
    // Build the system: [gps_x gps_y 1] * [a c tx] = [pdf_x pdf_y]
    //                                      [b d ty]
    
    // GPS coordinates matrix (3x3)
    final x1 = p1Gps.x, y1 = p1Gps.y;
    final x2 = p2Gps.x, y2 = p2Gps.y;
    final x3 = p3Gps.x, y3 = p3Gps.y;
    
    // PDF coordinates
    final u1 = _pdfRef1!.x, v1 = _pdfRef1!.y;
    final u2 = _pdfRef2!.x, v2 = _pdfRef2!.y;
    final u3 = _pdfRef3!.x, v3 = _pdfRef3!.y;
    
    // Calculate determinant
    final det = x1 * (y2 - y3) - y1 * (x2 - x3) + (x2 * y3 - x3 * y2);
    
    // If determinant is near zero, points are collinear.
    // Fallback to 2-point Similarity Transformation (Scale + Rotation + Translation).
    // This assumes the aspect ratio is preserved (1:1) and there is no shear,
    // which is true for standard map projections.
    if (det.abs() < 1e-10) {
       debugPrint("CoordinateMapper Warning: Calibration points are collinear (det near 0). Falling back to 2-point Similarity Transformation.");
       
       // Find the pair of GPS points furthest apart to minimize error
       final d12 = pow(x1 - x2, 2) + pow(y1 - y2, 2);
       final d13 = pow(x1 - x3, 2) + pow(y1 - y3, 2);
       final d23 = pow(x2 - x3, 2) + pow(y2 - y3, 2);
       
       double sx1, sy1, su1, sv1; // Point A
       double sx2, sy2, su2, sv2; // Point B
       
       if (d12 >= d13 && d12 >= d23) {
         sx1 = x1; sy1 = y1; su1 = u1; sv1 = v1;
         sx2 = x2; sy2 = y2; su2 = u2; sv2 = v2;
       } else if (d13 >= d12 && d13 >= d23) {
         sx1 = x1; sy1 = y1; su1 = u1; sv1 = v1;
         sx2 = x3; sy2 = y3; su2 = u3; sv2 = v3;
       } else {
         sx1 = x2; sy1 = y2; su1 = u2; sv1 = v2;
         sx2 = x3; sy2 = y3; su2 = u3; sv2 = v3;
       }
       
       // Solve for Similarity Transform:
       // u = A*x - B*y + tx
       // v = B*x + A*y + ty
       // A = s*cos(theta), B = s*sin(theta)
       
       final dx = sx2 - sx1;
       final dy = sy2 - sy1;
       final du = su2 - su1;
       final dv = sv2 - sv1;
       final distSq = dx*dx + dy*dy;
       
       if (distSq < 1e-20) return null; // Points are identical, cannot calibrate
       
       final A = (du * dx + dv * dy) / distSq;
       final B = (dv * dx - du * dy) / distSq;
       
       final tx = su1 - (A * sx1 - B * sy1);
       final ty = sv1 - (B * sx1 + A * sy1);
       
       final pdfX = A * inputGps.x - B * inputGps.y + tx;
       final pdfY = B * inputGps.x + A * inputGps.y + ty;
       
       return Point<double>(pdfX, pdfY);
    }
    
    // Solve for transformation parameters using Cramer's rule
    final a = ((u1 * (y2 - y3) + u2 * (y3 - y1) + u3 * (y1 - y2)) / det);
    final b = ((u1 * (x3 - x2) + u2 * (x1 - x3) + u3 * (x2 - x1)) / det);
    final tx = ((u1 * (x2 * y3 - x3 * y2) + u2 * (x3 * y1 - x1 * y3) + u3 * (x1 * y2 - x2 * y1)) / det);
    
    final c = ((v1 * (y2 - y3) + v2 * (y3 - y1) + v3 * (y1 - y2)) / det);
    final d = ((v1 * (x3 - x2) + v2 * (x1 - x3) + v3 * (x2 - x1)) / det);
    final ty = ((v1 * (x2 * y3 - x3 * y2) + v2 * (x3 * y1 - x1 * y3) + v3 * (x1 * y2 - x2 * y1)) / det);
    
    // Apply affine transformation to input point
    final pdfX = a * inputGps.x + b * inputGps.y + tx;
    final pdfY = c * inputGps.x + d * inputGps.y + ty;
    
    return Point<double>(pdfX, pdfY);
  }

  /// Calculates the number of PDF pixels representing 1 meter.
  /// Returns null if not calibrated.
  double? get pixelsPerMeter {
    if (!isCalibrated) return null;
    
    // Calculate distance in meters between GPS points
    final distanceMeters = Geolocator.distanceBetween(
      _gpsRef1!.x, _gpsRef1!.y, 
      _gpsRef2!.x, _gpsRef2!.y
    );
    
    if (distanceMeters == 0) return null;
    
    // Calculate distance in pixels between PDF points
    final pdfDx = _pdfRef2!.x - _pdfRef1!.x;
    final pdfDy = _pdfRef2!.y - _pdfRef1!.y;
    final distancePixels = sqrt(pdfDx * pdfDx + pdfDy * pdfDy);
    
    // If pixel distance is 0, we have an issue with calibration points
    if (distancePixels == 0) return null;
    
    return distancePixels / distanceMeters;
  }

  /// Calculates the rotation of "True North" relative to the PDF coordinate system.
  /// Returns the angle in radians where 0 is East, PI/2 is South (in screen coords).
  /// To get the rotation correction for the compass, use this angle.
  /// Returns 0.0 if not calibrated.
  double get northAngleRad {
    if (!isCalibrated) return 0.0;

    // We need to calculate the affine transform coefficients 'b' and 'd'
    // which represent how PDF x and y change with Latitude (North).
    
    // GPS coordinates matrix (3x3)
    final x1 = _gpsRef1!.x; final y1 = _gpsRef1!.y; // x=lng, y=lat
    final x2 = _gpsRef2!.x; final y2 = _gpsRef2!.y;
    final x3 = _gpsRef3!.x; final y3 = _gpsRef3!.y;
    
    // PDF coordinates
    final u1 = _pdfRef1!.x; final u2 = _pdfRef2!.x; final u3 = _pdfRef3!.x;
    final v1 = _pdfRef1!.y; final v2 = _pdfRef2!.y; final v3 = _pdfRef3!.y;
    
    // Calculate determinant
    final det = x1 * (y2 - y3) - y1 * (x2 - x3) + (x2 * y3 - x3 * y2);
    
    // If determinant is near zero, points are collinear.
    // Fallback to 2-point Similarity calculation.
    if (det.abs() < 1e-10) {
       final d12 = pow(x1 - x2, 2) + pow(y1 - y2, 2);
       final d13 = pow(x1 - x3, 2) + pow(y1 - y3, 2);
       final d23 = pow(x2 - x3, 2) + pow(y2 - y3, 2);
       
       double sx1, sy1, su1, sv1; // Point A
       double sx2, sy2, su2, sv2; // Point B
       
       if (d12 >= d13 && d12 >= d23) {
         sx1 = x1; sy1 = y1; su1 = u1; sv1 = v1;
         sx2 = x2; sy2 = y2; su2 = u2; sv2 = v2;
       } else if (d13 >= d12 && d13 >= d23) {
         sx1 = x1; sy1 = y1; su1 = u1; sv1 = v1;
         sx2 = x3; sy2 = y3; su2 = u3; sv2 = v3;
       } else {
         sx1 = x2; sy1 = y2; su1 = u2; sv1 = v2;
         sx2 = x3; sy2 = y3; su2 = u3; sv2 = v3;
       }
       
       final dx = sx2 - sx1;
       final dy = sy2 - sy1;
       final du = su2 - su1;
       final dv = sv2 - sv1;
       final distSq = dx*dx + dy*dy;
       
       if (distSq < 1e-20) return 0.0;
       
       final A = (du * dx + dv * dy) / distSq;
       final B = (dv * dx - du * dy) / distSq;
       
       // Rotation matrix is [[A, -B], [B, A]] if scaled.
       // The vector corresponding to North (increasing Lat, Y) is (-B, A). Wait.
       // u = A*x - B*y... 
       // If Latitude increases (dy=1, dx=0), then du = -B, dv = A.
       // So the North vector in PDF space is (-B, A).
       return atan2(A, -B);
    }
    
    // b corresponds to change in PDF_x per unit Latitude
    final b = ((u1 * (x3 - x2) + u2 * (x1 - x3) + u3 * (x2 - x1)) / det);
    
    // d corresponds to change in PDF_y per unit Latitude
    final d = ((v1 * (x3 - x2) + v2 * (x1 - x3) + v3 * (x2 - x1)) / det);
    
    // Vector (b, d) represents the North direction in PDF space.
    return atan2(d, b);
  }
}
