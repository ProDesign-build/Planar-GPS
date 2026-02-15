import 'dart:math';
import 'package:vector_math/vector_math.dart' as vector;
import 'package:geolocator/geolocator.dart';

/// A service to map real-world GPS coordinates (represented as [Point] x=lat, y=lng)
/// to PDF 2D Cartesian coordinates.
///
/// Uses a 2-point calibration system to determine Scale, Rotation, and Translation.
/// Assumes a scalable, rotatable, but aspect-ratio-preserving projection (Similarity Transformation),
/// which is valid for architectural scales (small geographic areas).
class CoordinateMapper {
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
    _gpsRef1 = gps1;
    _pdfRef1 = pdf1;
    _gpsRef2 = gps2;
    _pdfRef2 = pdf2;
    _gpsRef3 = gps3;
    _pdfRef3 = pdf3;
  }

  /// Clears the calibration data.
  void clearCalibration() {
    _gpsRef1 = null;
    _pdfRef1 = null;
    _gpsRef2 = null;
    _pdfRef2 = null;
    _gpsRef3 = null;
    _pdfRef3 = null;
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
    
    // Calculate determinant for matrix inversion
    final det = x1 * (y2 - y3) - y1 * (x2 - x3) + (x2 * y3 - x3 * y2);
    
    if (det.abs() < 1e-10) return null; // Points are collinear
    
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
}
