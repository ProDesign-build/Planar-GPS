import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class SavedMap {
  final String id;
  final String name;
  final String filePath;
  final Point<double> gps1;
  final Point<double> pdf1;
  final Point<double> gps2;
  final Point<double> pdf2;
  final Point<double> gps3;
  final Point<double> pdf3;
  final DateTime lastOpened;

  SavedMap({
    required this.id,
    required this.name,
    required this.filePath,
    required this.gps1,
    required this.pdf1,
    required this.gps2,
    required this.pdf2,
    required this.gps3,
    required this.pdf3,
    required this.lastOpened,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'gps1_x': gps1.x,
      'gps1_y': gps1.y,
      'pdf1_x': pdf1.x,
      'pdf1_y': pdf1.y,
      'gps2_x': gps2.x,
      'gps2_y': gps2.y,
      'pdf2_x': pdf2.x,
      'pdf2_y': pdf2.y,
      'gps3_x': gps3.x,
      'gps3_y': gps3.y,
      'pdf3_x': pdf3.x,
      'pdf3_y': pdf3.y,
      'lastOpened': lastOpened.toIso8601String(),
    };
  }

  factory SavedMap.fromJson(Map<String, dynamic> json) {
    return SavedMap(
      id: json['id'],
      name: json['name'],
      filePath: json['filePath'],
      gps1: Point(json['gps1_x'], json['gps1_y']),
      pdf1: Point(json['pdf1_x'], json['pdf1_y']),
      gps2: Point(json['gps2_x'], json['gps2_y']),
      pdf2: Point(json['pdf2_x'], json['pdf2_y']),
      gps3: Point(json['gps3_x'] ?? 0.0, json['gps3_y'] ?? 0.0), // Backward compatibility
      pdf3: Point(json['pdf3_x'] ?? 0.0, json['pdf3_y'] ?? 0.0), // Backward compatibility
      lastOpened: DateTime.parse(json['lastOpened']),
    );
  }
}

class MapRepository {
  static const String _key = 'saved_maps';

  static Future<List<SavedMap>> getMaps() async {
    final prefs = await SharedPreferences.getInstance();
    final String? mapsJson = prefs.getString(_key);
    print("[MapRepository] getMaps() called, raw data: $mapsJson");
    if (mapsJson == null) {
      print("[MapRepository] No saved maps found");
      return [];
    }
    
    final List<dynamic> list = jsonDecode(mapsJson);
    final maps = list.map((e) => SavedMap.fromJson(e)).toList();
    print("[MapRepository] Loaded ${maps.length} maps");
    
    // Sort by last opened descending
    maps.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return maps;
  }

  static Future<void> saveMap(SavedMap map) async {
    print("[MapRepository] saveMap() called for: ${map.name}");
    final prefs = await SharedPreferences.getInstance();
    final maps = await getMaps();
    
    // Remove if exists (update)
    maps.removeWhere((m) => m.id == map.id || m.filePath == map.filePath);
    
    maps.add(map);
    print("[MapRepository] Saving ${maps.length} total maps");
    
    final String updatedJson = jsonEncode(maps.map((e) => e.toJson()).toList());
    final success = await prefs.setString(_key, updatedJson);
    print("[MapRepository] Save success: $success");
  }

  static Future<void> deleteMap(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final maps = await getMaps();
    maps.removeWhere((m) => m.id == id);
    
    final String updatedJson = jsonEncode(maps.map((e) => e.toJson()).toList());
    await prefs.setString(_key, updatedJson);
  }
}
