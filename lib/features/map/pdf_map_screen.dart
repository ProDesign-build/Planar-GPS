import 'dart:typed_data';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pdfx/pdfx.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:flutter_compass/flutter_compass.dart';
import '../../core/coordinate_mapper.dart';
import '../../core/app_theme.dart';
import 'location_marker.dart';
import '../calibration/calibration_screen.dart';
import '../../core/map_repository.dart';
import '../../core/ui_utils.dart';

class PdfMapScreen extends StatefulWidget {
  final bool autoPick;
  final SavedMap? initialMap;
  
  const PdfMapScreen({super.key, this.autoPick = false, this.initialMap});

  @override
  State<PdfMapScreen> createState() => _PdfMapScreenState();
}

class _PdfMapScreenState extends State<PdfMapScreen> with SingleTickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  PdfDocument? _document;
  PdfPageImage? _pageImage;
  Uint8List? _imageBytes; // For direct image display
  int _imageWidth = 0;
  int _imageHeight = 0;
  Uint8List? _pdfData; 
  bool _isLoading = false;
  String _fileName = "No File Selected";
  String? _filePath;
  bool _isImage = false; // Track if loaded file is an image
  
  StreamSubscription<Position>? _positionStream;
  Point<double>? _userPdfLocation;
  double _currentGpsAccuracy = 0.0;
  double _currentLat = 0.0;
  double _currentLng = 0.0;
  bool _showCalibrationSuccess = false;
  
  // Compass & Heading
  StreamSubscription<CompassEvent>? _compassStream;
  double _magnetometerHeading = 0.0;
  double _gpsHeading = 0.0;
  double _currentSpeed = 0.0;
  bool _isFollowingUser = false;
  
  // Animation
  AnimationController? _mapAnimController;
  Animation<Matrix4>? _mapAnimation;

  @override
  void initState() {
    super.initState();
    _mapAnimController = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 500),
    );
    _mapAnimController!.addListener(() {
       _transformController.value = _mapAnimation!.value;
    });

    _checkPermissionsAndStartStream();
    _startCompassStream();
    
    // Add listener to rebuild when zoom changes (for dynamic arrow)
    _transformController.addListener(_onTransformChange);
    
    if (widget.initialMap != null) {
       _loadSavedMap(widget.initialMap!);
    } else if (widget.autoPick) {
       WidgetsBinding.instance.addPostFrameCallback((_) => _pickPdf());
    }
  }

  void _onTransformChange() {
    if (mounted) {
      setState(() {}); // Rebuild to update arrow size
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _compassStream?.cancel();
    _transformController.removeListener(_onTransformChange);
    _transformController.dispose();
    _mapAnimController?.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    setState(() => _isLoading = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final fileName = result.files.single.name.toLowerCase();
        final isImageFile = fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || fileName.endsWith('.png');
        
        // Clear calibration when loading new file (Issue #1)
        CoordinateMapper().clearCalibration();
        
        setState(() {
          _isLoading = true;
          _fileName = result.files.single.name;
          // Create a copy of bytes to avoid detached buffer issues on web when passing to workers
          _pdfData = Uint8List.fromList(result.files.single.bytes!);
          _filePath = result.files.single.path;
          _isImage = isImageFile;
          _userPdfLocation = null; // Clear user location marker
        });

        if (isImageFile) {
          // Pass a copy so the master _pdfData isn't detached by the loader
          await _loadImage(Uint8List.fromList(_pdfData!));
        } else {
          // Pass a copy so the master _pdfData isn't detached by the loader
          await _loadPdf(Uint8List.fromList(_pdfData!));
        }
      } else {
        if (mounted) {
           UiUtils.showInfoSnackBar(context, 'No file selected');
           // If canceled and no file loaded, and it's not an initial map, go back
           if (_pageImage == null && widget.initialMap == null) {
             Navigator.pop(context);
           }
        }
      }
    } catch (e) {
        debugPrint('Error picking file: $e');
        if (mounted) {
          UiUtils.showErrorSnackBar(context, 'Error picking file: $e');
        }
    } finally {
        if (mounted) setState(() => _isLoading = false);
      }
  }

  Future<void> _loadSavedMap(SavedMap map) async {
    setState(() => _isLoading = true);
    try {
      _fileName = map.name;
      _filePath = map.filePath;
      
      // Detect if it's an image
      final fileName = map.filePath.toLowerCase();
      final isImageFile = fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || fileName.endsWith('.png');
      _isImage = isImageFile;
      
      if (isImageFile) {
        // Load as image
        final file = File(map.filePath);
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
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
      } else {
        // Load as PDF
        _document = await PdfDocument.openFile(map.filePath);
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
      }

      // Restore Calibration
      CoordinateMapper().setCalibration(
        gps1: map.gps1, 
        pdf1: map.pdf1, 
        gps2: map.gps2, 
        pdf2: map.pdf2,
        gps3: map.gps3,
        pdf3: map.pdf3,
      );
    } catch (e) {
       debugPrint("Error loading saved map: $e");
       if (mounted) {
          UiUtils.showErrorSnackBar(context, "Failed to load map: $e");
          setState(() => _isLoading = false);
       }
    }
  }

  Future<void> _loadPdf(Uint8List data) async {
    try {
      _document = await PdfDocument.openData(data);
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
      debugPrint('Error loading PDF: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadImage(Uint8List data) async {
    try {
      final codec = await ui.instantiateImageCodec(data);
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

  Future<void> _checkPermissionsAndStartStream() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1, 
    );
    
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        debugPrint("Position Update: ${position.latitude}, ${position.longitude}, Acc: ${position.accuracy}");
        if (mounted) {
           setState(() {
             _currentGpsAccuracy = position.accuracy;
             _currentLat = position.latitude;
             _currentLng = position.longitude;
             _currentSpeed = position.speed; 
             // Trust GPS heading only if moving > 1 m/s (approx 3.6 km/h)
             if (position.speed > 1.0) {
                 _gpsHeading = position.heading;
             }
           });
           
           // Force update location logic even if seemingly unchanged
           _updateUserLocation(position.latitude, position.longitude);
           
           if (_isFollowingUser && _userPdfLocation != null) {
              _centerMap(calculateZoom: false);
           }
        }
      },
      onError: (e) {
         debugPrint("Position Stream Error: $e");
      }
    );
  }

  void _startCompassStream() {
    _compassStream = FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _magnetometerHeading = event.heading ?? 0.0;
        });
      }
    });
  }

  void _updateUserLocation(double lat, double lng) {
    if (!CoordinateMapper().isCalibrated) return;
    final pdfPoint = CoordinateMapper().gpsToPdf(latitude: lat, longitude: lng);
    if (pdfPoint != null && mounted) {
      setState(() => _userPdfLocation = pdfPoint);
    }
  }

  void _openCalibration() async {
    if (_pdfData == null && _imageBytes == null && widget.initialMap == null) {
      UiUtils.showInfoSnackBar(context, "No map loaded. Please select a file first.");
      return;
    }

    if (CoordinateMapper().isCalibrated) {
      final shouldRecalibrate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Recalibrate Map?"),
          content: const Text("This will overwrite the current calibration."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Recalibrate"),
            ),
          ],
        ),
      );
      
      if (shouldRecalibrate != true) return;
    }
    
    // Use _pdfData/_imageBytes if available, otherwise load from file for initialMap case
    Uint8List? dataToUse = _pdfData ?? _imageBytes;
    
    if (dataToUse == null) {
      
      if (widget.initialMap != null) {
        try {
          final file = File(widget.initialMap!.filePath);
          dataToUse = await file.readAsBytes();
        } catch (e) {
          if (mounted) {
            UiUtils.showErrorSnackBar(context, "Could not load file: $e");
          }
          return;
        }
      }
    }

    if (dataToUse == null) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CalibrationScreen(
        pdfData: Uint8List.fromList(dataToUse!),
        isImage: _isImage,
      )),
    );

    if (result == true && mounted) {
      setState(() {}); // Refresh to show updated calibration status
      
      // Also refresh location
      try {
        final position = await Geolocator.getCurrentPosition();
        _updateUserLocation(position.latitude, position.longitude);
      } catch (e) { /* ignore */ }
    }
  }


  void _zoomIn() {
    final screenSize = MediaQuery.of(context).size;
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.2).clamp(0.1, 20.0);
    
    // Determine focal point in content coordinates based on calibration state
    double contentX, contentY;
    
    if (CoordinateMapper().isCalibrated && _userPdfLocation != null) {
      // If calibrated, zoom toward user location arrow
      contentX = _userPdfLocation!.x * 2.0;
      contentY = _userPdfLocation!.y * 2.0;
    } else {
      // If not calibrated, zoom toward center of map
      final displayWidth = _isImage ? _imageWidth.toDouble() : (_pageImage?.width ?? 0).toDouble();
      final displayHeight = _isImage ? _imageHeight.toDouble() : (_pageImage?.height ?? 0).toDouble();
      contentX = displayWidth / 2;
      contentY = displayHeight / 2;
    }
    
    // Calculate translation so focal point appears at screen center
    // Formula: translate + scale * content_point = screenCenter
    // Therefore: translate = screenCenter - scale * content_point
    final targetX = screenSize.width / 2 - (contentX * newScale);
    final targetY = screenSize.height / 2 - (contentY * newScale);
    
    final newMatrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(newScale);
    
    _transformController.value = newMatrix;
  }

  void _zoomOut() {
    final screenSize = MediaQuery.of(context).size;
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 0.8).clamp(0.1, 20.0);
    
    // Determine focal point in content coordinates based on calibration state
    double contentX, contentY;
    
    if (CoordinateMapper().isCalibrated && _userPdfLocation != null) {
      // If calibrated, zoom toward user location arrow
      contentX = _userPdfLocation!.x * 2.0;
      contentY = _userPdfLocation!.y * 2.0;
    } else {
      // If not calibrated, zoom toward center of map
      final displayWidth = _isImage ? _imageWidth.toDouble() : (_pageImage?.width ?? 0).toDouble();
      final displayHeight = _isImage ? _imageHeight.toDouble() : (_pageImage?.height ?? 0).toDouble();
      contentX = displayWidth / 2;
      contentY = displayHeight / 2;
    }
    
    // Calculate translation so focal point appears at screen center
    // Formula: translate + scale * content_point = screenCenter
    // Therefore: translate = screenCenter - scale * content_point
    final targetX = screenSize.width / 2 - (contentX * newScale);
    final targetY = screenSize.height / 2 - (contentY * newScale);
    
    final newMatrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(newScale);
    
    _transformController.value = newMatrix;
  }



  void _centerMap({bool calculateZoom = false}) {
    if (_userPdfLocation == null) return;
    
    print("[PdfMapScreen] Centering map on user location: $_userPdfLocation");
    
    final screenSize = MediaQuery.of(context).size;
    var targetScale = _transformController.value.getMaxScaleOnAxis();

    if (calculateZoom) {
      final pixelsPerMeter = CoordinateMapper().pixelsPerMeter;
      if (pixelsPerMeter != null) {
        // Target: 200 meters (100m each side) visible width
        const visibleMeters = 200.0;
        // pixelsPerMeter is based on "1x" coordinates (half-size of display)
        // InteractiveViewer content is "2x" size.
        // So we need to multiply by 2.0 to get "Display Pixels per Meter"
        final requiredDisplayPixels = visibleMeters * pixelsPerMeter * 2.0;
        
        // Scale = ScreenWidth / RequiredDisplayPixels
        if (requiredDisplayPixels > 0) {
            targetScale = screenSize.width / requiredDisplayPixels;
            // Clamp scale to reasonable limits (matching InteractiveViewer)
            targetScale = targetScale.clamp(0.1, 20.0);
        }
      }
    }
    
    // We want the user's PDF location to be at the center of the screen
    // The InteractiveViewer applies: screen_point = matrix * pdf_point_in_content
    // Our content is scaled 2x relative to CoordinateMapper output.
    // So content_point = userLocation * 2.0
    
    final contentX = _userPdfLocation!.x * 2.0;
    final contentY = _userPdfLocation!.y * 2.0;
    
    // We need: translate + scale * content_point = screenCenter
    // Therefore: translate = screenCenter - scale * content_point
    
    final targetX = screenSize.width / 2 - (contentX * targetScale);
    final targetY = screenSize.height / 2 - (contentY * targetScale);
    
    final newMatrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(targetScale);
    
    if (_mapAnimController != null) {
      _mapAnimation = Matrix4Tween(
        begin: _transformController.value,
        end: newMatrix,
      ).animate(CurvedAnimation(parent: _mapAnimController!, curve: Curves.fastOutSlowIn));
      _mapAnimController!.forward(from: 0);
    } else {
      _transformController.value = newMatrix;
    }
  }

  Future<void> _saveMapState() async {
    if (_pdfData == null && widget.initialMap == null) return;
    // If loaded from initialMap, we might not have _pdfData set if we used openFile.
    // Ensure we have a path.
    
    if (!CoordinateMapper().isCalibrated) {
      UiUtils.showInfoSnackBar(context, "Calibrate map before saving.");
      return;
    }
    
    // We need the file path. 
    // If picked via file picker 'withData', we have bytes but maybe not a persistent path on all platforms?
    // On Windows/Mobile file picker returns path.
    // If we only have bytes (Web), we can't persist easily without file system.
    // Assuming Windows/Mobile.
    
    // I need to update _pickPdf to store path.
    if (_filePath == null && widget.initialMap != null) {
       _filePath = widget.initialMap!.filePath;
    }

    if (_filePath == null) {
       print("[PdfMapScreen] ERROR: _filePath is null!");
       UiUtils.showErrorSnackBar(context, "Cannot save: File path missing.");
       return;
    }

    try {
      print("[PdfMapScreen] Creating SavedMap object...");
      final map = SavedMap(
        id: widget.initialMap?.id ?? DateTime.now().toIso8601String(),
        name: _fileName,
        filePath: _filePath!,
        gps1: CoordinateMapper().gpsRef1!,
        pdf1: CoordinateMapper().pdfRef1!,
        gps2: CoordinateMapper().gpsRef2!,
        pdf2: CoordinateMapper().pdfRef2!,
        gps3: CoordinateMapper().gpsRef3!,
        pdf3: CoordinateMapper().pdfRef3!,
        lastOpened: DateTime.now(),
      );
      print("[PdfMapScreen] SavedMap created: ${map.name}, id: ${map.id}");
      
      print("[PdfMapScreen] Calling MapRepository.saveMap...");
      await MapRepository.saveMap(map);
      print("[PdfMapScreen] SaveMap completed");
      
      if (mounted) {
        UiUtils.showSuccessSnackBar(context, "Map saved to History");
      }
    } catch (e) {
      print("[PdfMapScreen] ERROR saving map: $e");
      if (mounted) {
        UiUtils.showErrorSnackBar(context, "Error saving: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E5E5), // Light grid background like design? Or dark?
      // Design shows light grid in one image, dark in another? 
      // The implementation plan said "Dark Mode". The screenshot 1 is light, 2 and 3 are dark.
      // I will stick to Dark Mode AppTheme background with a light grid overlay or similar.
      // Actually let's use AppTheme background and a subtle grid.
      // Wait, the "Pick PDF Map" screen is dark. The "Point 1 Selection" is dark.
      // The map screenshot (first one) has a LIGHT background.
      // User said "Use this UI" and showed 3 images. 1 is Light Map, 2 is Dark Modal, 3 is Dark Home.
      // A hybrid might be intended, or the map is just what the PDF looks like?
      // "Site_Plan_Level_1.pdf" is the PDF itself. The PDF background is white/transparent?
      // If the PDF is transparent, and I put it on dark background, lines might be invisible if they are black.
      // Architectural PDFs usually have black lines. They need a WHITE background or LIGHT background.
      // So the "Grid" should probably be light, and the PDF rendered on top.
      body: Stack(
        children: [
          // 1. Grid Background (Light to support PDF visibility)
          Positioned.fill(
            child: CustomPaint(
              painter: GridBackgroundPainter(),
            ),
          ),

          // 2. Map or Picker Button
          Positioned.fill(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (_pageImage == null && _imageBytes == null)
                  ? Center(child: ElevatedButton(onPressed: _pickPdf, child: const Text("Pick PDF")))
                  : _buildInteractiveMap(),
          ),

          // 3. Top Info Bar
          Positioned(
            top: 40,
            left: 16,
            child: _buildTopBar(),
          ),

          // 4. Right Controls
          Positioned(
            top: 100,
            right: 16,
            child: Column(
              children: [
                _buildFloatBtn(Icons.tune, _openCalibration),
                const SizedBox(height: 16),
                _buildFloatBtn(Icons.save, _saveMapState),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F3646),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      _buildFloatBtn(Icons.add, _zoomIn, transparent: true),
                      Container(height: 1, width: 20, color: Colors.grey.withOpacity(0.3)),
                      _buildFloatBtn(Icons.remove, _zoomOut, transparent: true),
                    ],
                  ),
                )
              ],
            ),
          ),

          // 5. Bottom Info
          Positioned(
            bottom: 30,
            left: 16,
            child: _buildLatLongBox(),
          ),

          // 6. FAB
          Positioned(
             bottom: 30,
             right: 16,
             child: FloatingActionButton(
               backgroundColor: AppTheme.primary,
               onPressed: () async {
                   setState(() => _isFollowingUser = true);
                   
                   // Center map first if we have location
                   if (_userPdfLocation != null) {
                      _centerMap(calculateZoom: true);
                   }
                   
                   try {
                     final position = await Geolocator.getCurrentPosition();
                     _updateUserLocation(position.latitude, position.longitude);
                     
                     if (!mounted) return;
                     if (_userPdfLocation != null) {
                        _centerMap(calculateZoom: true); 
                     } else {
                        UiUtils.showInfoSnackBar(context, 'Calibrate first!');
                     }
                   } catch (e) {
                     if (mounted) {
                        UiUtils.showErrorSnackBar(context, 'Error getting location');
                     }
                   }
               },
               shape: const CircleBorder(),
               child: Icon(
                 _isFollowingUser ? Icons.gps_fixed : Icons.my_location, 
                 color: Colors.white
               ),
             ),
          ),

          // 7. Calibration Status
          if (!CoordinateMapper().isCalibrated && _pageImage != null)
             Positioned(
               bottom: 100,
               left: 16,
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                 decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(8)),
                 child: const Row(children: [Icon(Icons.warning, color: Colors.white, size: 16), SizedBox(width: 8), Text("Not Calibrated", style: TextStyle(color: Colors.white))]),
               ),
             ),
             
          // 8. Calibration Success Check (Mockup shows green pill "Calibration Complete")
              if (CoordinateMapper().isCalibrated && _showCalibrationSuccess)
                 Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                     decoration: BoxDecoration(color: const Color(0xFF2F3646), borderRadius: BorderRadius.circular(24)),
                     child: const Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.check_circle, color: AppTheme.success),
                         SizedBox(width: 8),
                         Text("Calibration Complete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                       ],
                     ),
                   ),
                 ),
              )
        ],
      ),
    );
  }

  Widget _buildInteractiveMap() {
    // Determine what to display based on what's loaded
    final Uint8List? displayBytes = _imageBytes ?? _pageImage?.bytes;
    final double displayWidth = _isImage ? _imageWidth.toDouble() : (_pageImage?.width ?? 0).toDouble();
    final double displayHeight = _isImage ? _imageHeight.toDouble() : (_pageImage?.height ?? 0).toDouble();
    
    if (displayBytes == null) return const SizedBox.shrink();
    
    final screenSize = MediaQuery.of(context).size;
    
    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.1,
      maxScale: 20.0,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(double.infinity), // Allow infinite panning (Fixes snapping)
      onInteractionStart: (_) {
        if (_isFollowingUser) {
          setState(() => _isFollowingUser = false);
        }
      },
      child: Center(
        child: SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: Stack(
            clipBehavior: Clip.none, // Allow marker to exceed bounds (Fixes missing arrow)
            children: [
              Image.memory(
                displayBytes,
                width: displayWidth,
                height: displayHeight,
                fit: BoxFit.none,
              ),
              if (_userPdfLocation != null)
                 _buildUserMarker(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserMarker() {
     final screenWidth = MediaQuery.of(context).size.width;
     final currentScale = _transformController.value.getMaxScaleOnAxis();
     
     // Target size: 12.5% of viewport width
     final targetDisplaySize = screenWidth * 0.125;
     
     // Size in content coordinates
     final markerDiameter = targetDisplaySize / currentScale;
     final radius = markerDiameter / 2;
     
     // Rotation Logic
     final northAngle = CoordinateMapper().northAngleRad;
     
     // Hybrid Heading: Use GPS bearing if moving > 1.0 m/s, else Magnetometer
     double deviceHeading = _magnetometerHeading;
     bool isGps = false;
     
     if (_currentSpeed > 1.0) {
        deviceHeading = _gpsHeading;
        isGps = true;
     }

     final headingRad = deviceHeading * (pi / 180);
     final rotation = northAngle + headingRad + (pi / 2);

     return AnimatedPositioned(
        duration: const Duration(milliseconds: 1000),
        curve: Curves.linear,
        left: (_userPdfLocation!.x * 2.0) - radius,
        top: (_userPdfLocation!.y * 2.0) - radius,
        child: LocationMarker(
           rotation: rotation,
           isGpsHeading: isGps,
           radius: radius,
        ),
     );
  }

   Widget _buildTopBar() {
   bool isCalibrated = CoordinateMapper().isCalibrated;
   return Container(
     decoration: BoxDecoration(
       color: const Color(0xFF2F3646),
       borderRadius: BorderRadius.circular(8),
     ),
     child: Row(
       mainAxisSize: MainAxisSize.min,
       children: [
         IconButton(
           icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
           onPressed: () => Navigator.pop(context),
           padding: const EdgeInsets.all(8),
           constraints: const BoxConstraints(),
         ),
         Container(
           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
           child: Row(
             mainAxisSize: MainAxisSize.min,
             children: [
               Container(
                   padding: const EdgeInsets.all(4), 
                   decoration: BoxDecoration(
                       color: isCalibrated ? AppTheme.success.withOpacity(0.2) : AppTheme.error.withOpacity(0.2), 
                       borderRadius: BorderRadius.circular(4)
                   ), 
                   child: Icon(
                       isCalibrated ? Icons.link : Icons.link_off, 
                       color: isCalibrated ? AppTheme.success : AppTheme.error, 
                       size: 14
                   )
               ),
               const SizedBox(width: 8),
               Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Text(_fileName, 
                     style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                   ),
                   Row(children: [
                     Container(width: 6, height: 6, decoration: BoxDecoration(color: _currentGpsAccuracy < 10 ? AppTheme.success : AppTheme.error, shape: BoxShape.circle)),
                     const SizedBox(width: 4),
                     Text("GPS: ±${_currentGpsAccuracy.toStringAsFixed(1)}m", style: const TextStyle(color: Colors.grey, fontSize: 10)),
                   ])
                 ],
               )
             ],
           ),
         ),
       ],
     ),
   );
}

  Widget _buildFloatBtn(IconData icon, VoidCallback onTap, {Color color = const Color(0xFF2F3646), bool transparent = false}) {
     return GestureDetector(
       onTap: onTap,
       child: Container(
         width: 48, height: 48,
         decoration: transparent ? null : BoxDecoration(color: color, shape: BoxShape.circle),
         child: Icon(icon, color: Colors.white),
       ),
     );
  }
  
  Widget _buildLatLongBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
         color: const Color(0xFF2F3646),
         borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("LAT / LONG", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("${_currentLat.toStringAsFixed(5)}° N", style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
          Text("${_currentLng.toStringAsFixed(5)}° W", style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
        ],
      ),
    );
  }


}

class GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Light grid on light gray background
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1.0;

    const double spacing = 40;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
