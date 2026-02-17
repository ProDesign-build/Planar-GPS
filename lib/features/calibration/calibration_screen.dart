import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/coordinate_mapper.dart';
import '../../core/app_theme.dart';
import '../../core/ui_utils.dart';

class CalibrationScreen extends StatefulWidget {
  final Uint8List pdfData;
  final bool isImage; // Add flag to bypass PDF loading for images

  const CalibrationScreen({super.key, required this.pdfData, this.isImage = false});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final TransformationController _transformController = TransformationController();
  
  // Data State
  PdfDocument? _document;
  PdfPageImage? _pageImage;
  Uint8List? _imageBytes; // For image files
  int _imageWidth = 0;
  int _imageHeight = 0;
  bool _isLoading = true;
  
  // Calibration State
  final List<Point<double>> _pdfPoints = [];
  final List<Point<double>> _gpsPoints = [];
  
  // UI State
  int _currentStep = 1; // 1, 2, or 3
  Offset? _tempTapPosition; // Where user just tapped
  
  // Controllers
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.isImage) {
      _loadImage();
    } else {
      _loadPdf();
    }
  }

  Future<void> _loadPdf() async {
    try {
      // Try to load as PDF first. Pass a copy so original data isn't detached on failure
      _document = await PdfDocument.openData(Uint8List.fromList(widget.pdfData));
      final page = await _document!.getPage(1);
      final renderer = await page.render(
        width: page.width * 2, 
        height: page.height * 2, 
      );
      await page.close();
      
      if (mounted) {
        setState(() {
          _pageImage = renderer;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading as PDF: $e, trying as image...');
      // If PDF loading fails, try loading as image
      await _loadImage();
    }
  }

  Future<void> _loadImage() async {
    try {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(widget.pdfData));
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null && mounted) {
        setState(() {
          _imageBytes = byteData.buffer.asUint8List();
          _imageWidth = image.width;
          _imageHeight = image.height;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading image: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onImageTap(TapUpDetails details) {
    if (_currentStep > 3) return;

    setState(() {
      _tempTapPosition = details.localPosition;
    });
    setState(() {
      _tempTapPosition = details.localPosition;
    });
  }

  Future<void> _useCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _latController.text = position.latitude.toString();
      _lngController.text = position.longitude.toString();
    });
  }

  void _savePoint() {
    print("CalibrationScreen: _savePoint called. Step: $_currentStep");
    if (_tempTapPosition == null) {
      print("CalibrationScreen: _tempTapPosition is null");
      return;
    }
    
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);
    
    if (lat == null || lng == null) {
      print("CalibrationScreen: Invalid lat/lng: ${_latController.text}, ${_lngController.text}");
      UiUtils.showErrorSnackBar(context, "Please enter valid GPS coordinates");
      return;
    }

    // Check for identical/too close points
    for (final point in _gpsPoints) {
      final distance = Geolocator.distanceBetween(point.x, point.y, lat, lng);
      if (distance < 1.0) { // 1 meter threshold
        print("CalibrationScreen: Point too close to existing point ($distance m).");
        UiUtils.showErrorSnackBar(context, "Points must be at least 1m apart. Please move.");
        return;
      }
    }

    setState(() {
      _pdfPoints.add(Point(_tempTapPosition!.dx / 2.0, _tempTapPosition!.dy / 2.0));
      _gpsPoints.add(Point(lat, lng));
      
      print("CalibrationScreen: Point $_currentStep saved. GPS: $lat, $lng");

      
      _latController.clear();
      _lngController.clear();
      _tempTapPosition = null;
      _currentStep++;
    });

    if (_pdfPoints.length == 3) {
      print("CalibrationScreen: 3 points collected. Finishing.");
      _finishCalibration();
    }
  }

  void _finishCalibration() {
    print("CalibrationScreen: _finishCalibration called.");
    CoordinateMapper().setCalibration(
      gps1: _gpsPoints[0],
      pdf1: _pdfPoints[0],
      gps2: _gpsPoints[1],
      pdf2: _pdfPoints[1],
      gps3: _gpsPoints[2],
      pdf3: _pdfPoints[2],
    );
    
    UiUtils.showSuccessSnackBar(context, 'Calibration Complete!');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background, // Match theme
      resizeToAvoidBottomInset: false, // Don't squash map when keyboard opens
      body: Stack(
        children: [
          // 1. Map Layer
          Positioned.fill(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _buildMap(),
          ),
          
          // 2. Dimming Overlay (optional, maybe not needed if map is dark enough or strictly functional)
          
          // 3. Top Bar (Back Button & Title)
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(backgroundColor: AppTheme.surface.withOpacity(0.8)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "Calibrate Map (Step $_currentStep/3)",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ),
                const SizedBox(width: 48), // Balance spacing
              ],
            ),
          ),

          // 4. Bottom Card
          if (_currentStep <= 3)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4, // Max 40% of screen
                ),
                child: _buildInputCard(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    // Determine what to display based on what's loaded
    final Uint8List? displayBytes = _imageBytes ?? _pageImage?.bytes;
    final double displayWidth = (_imageBytes != null) ? _imageWidth.toDouble() : (_pageImage?.width ?? 0).toDouble();
    final double displayHeight = (_imageBytes != null) ? _imageHeight.toDouble() : (_pageImage?.height ?? 0).toDouble();
    
    if (displayBytes == null) return const SizedBox.shrink();

    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.1,
      maxScale: 5.0,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(2000), // Large margin to allow panning beyond screen
      child: GestureDetector(
        onTapUp: _onImageTap,
        child: Stack(
          children: [
            Image.memory(
              displayBytes,
              width: displayWidth,
              height: displayHeight,
              fit: BoxFit.none,
            ),
            // Confirmed Points
            ..._pdfPoints.asMap().entries.map((entry) {
               final idx = entry.key + 1;
               final p = entry.value;
               return Positioned(
                 left: p.x * 2.0 - 15,
                 top: p.y * 2.0 - 15,
                 child: Container(
                   width: 30,
                   height: 30,
                   decoration: const BoxDecoration(
                     color: AppTheme.success,
                     shape: BoxShape.circle,
                   ),
                   child: Center(child: Text("$idx", style: const TextStyle(fontWeight: FontWeight.bold))),
                 ),
               );
            }),
            // Temporary Tap Point
            if (_tempTapPosition != null)
              Positioned(
                left: _tempTapPosition!.dx - 20,
                top: _tempTapPosition!.dy - 20,
                child: Icon(Icons.location_searching, color: AppTheme.primary, size: 40),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Card(
      color: AppTheme.surface,
      elevation: 8,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Point $_currentStep Selection", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    const Text("Tap map to position, then enter GPS", style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), shape: BoxShape.circle),
                  child: Center(child: Text("$_currentStep", style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold))),
                )
              ],
            ),
            const SizedBox(height: 16),
            
            // PDF Coords readout
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: AppTheme.accent), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(children: [Icon(Icons.image, size: 16, color: AppTheme.textSecondary), SizedBox(width: 8), Text("PDF COORDS", style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))]),
                  if (_tempTapPosition != null)
                    Text("X: ${(_tempTapPosition!.dx / 2.0).toStringAsFixed(1)} | Y: ${(_tempTapPosition!.dy / 2.0).toStringAsFixed(1)}", style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold))
                  else
                    const Text("Tap on map...", style: TextStyle(color: AppTheme.textSecondary, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location),
                label: const Text("Use Current GPS Position"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            const Row(children: [
               Expanded(child: Divider(color: AppTheme.accent)),
               Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("OR ENTER MANUALLY", style: TextStyle(fontSize: 10, color: AppTheme.textSecondary))),
               Expanded(child: Divider(color: AppTheme.accent)),
            ]),
            const SizedBox(height: 16),

            TextField(
              controller: _latController,
              decoration: const InputDecoration(labelText: "Latitude (Decimal Degrees)", hintText: "e.g. 40.712776"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lngController,
              decoration: const InputDecoration(labelText: "Longitude (Decimal Degrees)", hintText: "e.g. -74.005974"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)))),
                const SizedBox(width: 16),
                Expanded(child: ElevatedButton(onPressed: _tempTapPosition == null ? null : _savePoint, child: Text("Save Point $_currentStep"))),
              ],
            )
          ],
        ),
      ),
    ),
  );
}
}
