import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_map_gps/core/coordinate_mapper.dart';

void main() {
  group('CoordinateMapper', () {
    // Reset singleton between tests if possible, but singleton is hard to reset.
    // We can just set new calibration.
    
    test('gpsToPdf maps correctly with simple identity transform', () {
      final mapper = CoordinateMapper();
      
      // Setup: 1 degree = 100 pixels. No rotation.
      // GPS: (0,0) -> PDF: (0,0)
      // GPS: (1,1) -> PDF: (100, 100) -> Wait.
      // Lat is Y. Lng is X.
      // GPS (0,0) -> Lat=0, Lng=0.
      // GPS (1,1) -> Lat=1, Lng=1.
      
      mapper.setCalibration(
        gps1: const Point(0, 0), // Lat=0, Lng=0
        pdf1: const Point(0, 0),
        gps2: const Point(1, 1), // Lat=1, Lng=1
        pdf2: const Point(100, 100),
        gps3: const Point(0, 1), // Lat=0, Lng=1 (third point for affine)
        pdf3: const Point(0, 100),
      );
      
      // Test 1: Midpoint
      // Lat=0.5, Lng=0.5. Should be (50, 50).
      final result1 = mapper.gpsToPdf(latitude: 0.5, longitude: 0.5);
      expect(result1!.x, closeTo(50, 0.001));
      expect(result1.y, closeTo(50, 0.001));
    });
    
    test('gpsToPdf handles rotation (90 degrees)', () {
      final mapper = CoordinateMapper();
      
      // Rotate 90 degrees clockwise?
      // GPS: Up is North (Lat increases).
      // PDF: Down is Y increases.
      // Let's set up a mapping where "North" on map is "Right" on PDF.
      
      // P1: Lat=0, Lng=0 -> PDF(0,0)
      // P2: Lat=1, Lng=0 (North) -> PDF(100, 0) (Right)
      // So North (GPS +Y) -> PDF (+X).
      
      mapper.setCalibration(
        gps1: const Point(0, 0),
        pdf1: const Point(0, 0),
        gps2: const Point(1, 0),
        pdf2: const Point(100, 0),
        gps3: const Point(0, 1), // Third point to complete affine
        pdf3: const Point(0, -100),
      );
      
      // Test: Lat=0, Lng=1 (East).
      // GPS Angle P1->P2 (North) is 90 deg (if East is 0). Wait.
      // Lat/Lng:
      // X=Lng, Y=Lat.
      // P1=(0,0). P2=(0,1). Vector=(0,1). Angle=90 deg (pi/2).
      
      // PDF P1=(0,0). P2=(100,0). Vector=(100,0). Angle=0 deg.
      
      // Rotation Delta = PDF - GPS = 0 - 90 = -90 deg.
      
      // Test Point: Lat=0, Lng=1 (East). 
      // GPS Vector from P1: (1, 0).
      // Rotate by -90:
      // x' = x*cos(-90) - y*sin(-90) = 1*0 - 0*(-1) = 0.
      // y' = x*sin(-90) + y*cos(-90) = 1*(-1) + 0 = -1.
      
      // Scale: 
      // GPS Len P1->P2 = 1. PDF Len = 100. Scale = 100.
      
      // Scaled: (0, -100).
      // Translate P1(0,0) + (0, -100) = (0, -100).
      
      final result = mapper.gpsToPdf(latitude: 0, longitude: 1);
      
      expect(result!.x, closeTo(0, 0.001));
      expect(result.y, closeTo(-100, 0.001));
    });
  });
}
