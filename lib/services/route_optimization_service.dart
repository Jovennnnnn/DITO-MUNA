import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class RouteOptimizationService {
  final String _mapboxToken = "pk.eyJ1IjoicHJpbmNlNjcwMyIsImEiOiJjbW9zeHB2ODIwNDFnMnRwdWxsam9sYWJmIn0.8DQhyf9Z9-yP8lCuP2WS3g";
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final Dio _dio = Dio();

  Future<Map<String, dynamic>?> getOptimizedRoute({
    required String sessionId,
    required double currentLat,
    required double currentLng,
    required List<Map<String, dynamic>> remainingPuroks,
    String? configHash,
  }) async {
    debugPrint("========== [OPTIMIZER] ROUTE OPTIMIZATION START ==========");
    debugPrint("PLATFORM: ${kIsWeb ? 'WEB' : 'NATIVE'}");
    debugPrint("STAGE: LOAD_STOPS");
    debugPrint("DRIVER GPS: $currentLat, $currentLng");
    debugPrint("SESSION ID: $sessionId");
    debugPrint("CONFIG HASH: $configHash");
    debugPrint("PENDING STOP COUNT: ${remainingPuroks.length}");

    if (remainingPuroks.isEmpty) {
      debugPrint("FAILURE: No pending collection areas found.");
      return {'success': false, 'error': 'NO_PENDING_STOPS', 'message': 'No pending collection areas found.'};
    }

    // Validate Coordinates first
    List<Map<String, dynamic>> validPuroks = [];
    List<String> invalidPuroks = [];

    for (var p in remainingPuroks) {
      final double lat = ((p['latitude'] ?? p['lat'] ?? 0.0) as num).toDouble();
      final double lng = ((p['longitude'] ?? p['lng'] ?? 0.0) as num).toDouble();
      final String name = (p['name'] ?? 'Unknown').toString();

      if (lat < -90 || lat > 90 || lng < -180 || lng > 180 || (lat == 0 && lng == 0)) {
        invalidPuroks.add(name);
        debugPrint("[OPTIMIZER] INVALID COORDINATES for $name: $lat, $lng");
      } else {
        validPuroks.add({
          'name': name,
          'lat': lat,
          'lng': lng,
        });
      }
    }

    if (invalidPuroks.isNotEmpty) {
      debugPrint("FAILURE: Invalid coordinates found for: ${invalidPuroks.join(', ')}");
      return {
        'success': false, 
        'error': 'INVALID_COORDINATES', 
        'message': 'Missing or invalid coordinates for: ${invalidPuroks.join(', ')}'
      };
    }

    // WEB PROXY LOGIC (With direct Mapbox fallback)
    if (kIsWeb) {
      debugPrint("TRANSPORT: HOSTINGER_PROXY_WITH_FALLBACK");
      final proxyResult = await _getOptimizedRouteViaProxy(
        sessionId: sessionId,
        currentLat: currentLat,
        currentLng: currentLng,
        remainingPuroks: validPuroks,
        configHash: configHash,
      );

      if (proxyResult != null && proxyResult['success'] == true) {
        return proxyResult;
      }
      debugPrint("[OPTIMIZER] Proxy service returned non-success. Attempting direct Mapbox fallback on Web...");
    }

    debugPrint("TRANSPORT: DIRECT_MAPBOX");
    return await _getOptimizedRouteDirectMapbox(
      sessionId: sessionId,
      currentLat: currentLat,
      currentLng: currentLng,
      validPuroks: validPuroks,
      configHash: configHash,
    );
  }

  Future<Map<String, dynamic>> _getOptimizedRouteDirectMapbox({
    required String sessionId,
    required double currentLat,
    required double currentLng,
    required List<Map<String, dynamic>> validPuroks,
    String? configHash,
  }) async {
    try {
      // Build Coordinates List (Index 0 = Driver) - MUST BE lng,lat
      List<List<double>> allCoords = [[currentLng, currentLat]];
      for (var p in validPuroks) {
        allCoords.add([(p['lng'] as num).toDouble(), (p['lat'] as num).toDouble()]);
      }

      String coordsString = allCoords.map((c) => "${c[0]},${c[1]}").join(";");

      debugPrint("STAGE: MATRIX");
      debugPrint("COORDINATE COUNT: ${allCoords.length}");
      debugPrint("COORDINATES: $coordsString");
      
      final String matrixUrl = "https://api.mapbox.com/directions-matrix/v1/mapbox/driving/$coordsString";
      
      final matrixResponse = await _dio.get(
        matrixUrl, 
        queryParameters: {
          "access_token": _mapboxToken,
          "annotations": "duration,distance",
          "sources": "0", 
        },
        options: Options(
          headers: {'Accept': 'application/json'},
          validateStatus: (status) => true,
        ),
      );

      debugPrint("MATRIX HTTP STATUS: ${matrixResponse.statusCode}");

      if (matrixResponse.statusCode != 200 || matrixResponse.data == null || matrixResponse.data['code'] != 'Ok') {
        String msg = matrixResponse.data?['message'] ?? 'Mapbox Matrix service returned status ${matrixResponse.statusCode}';
        debugPrint("[OPTIMIZER] MATRIX MAPBOX ERROR: $msg");
        return {
          'success': false, 
          'error': 'MATRIX_API_FAILED', 
          'message': 'Routing Matrix API error: $msg'
        };
      }

      final List durationsFromStart = matrixResponse.data['durations'][0];
      List<int> optimizedIndices = _solveNN(durationsFromStart);
      debugPrint("[OPTIMIZER] OPTIMIZED ORDER INDICES: ${optimizedIndices.join(' -> ')}");

      // Map back to Purok objects
      List<Map<String, dynamic>> optimizedStops = [];
      for (int i = 0; i < optimizedIndices.length; i++) {
        int originalIndex = optimizedIndices[i] - 1; 
        final purok = validPuroks[originalIndex];
        optimizedStops.add({
          'area_name': purok['name'],
          'latitude': purok['lat'],
          'longitude': purok['lng'],
          'sequence': i + 1,
          'status': 'PENDING',
        });
      }

      // Mapbox Directions API for Geometry along roads
      debugPrint("STAGE: DIRECTIONS");
      List<List<double>> routeWaypoints = [[currentLng, currentLat]];
      for (var s in optimizedStops) {
        routeWaypoints.add([(s['longitude'] as num).toDouble(), (s['latitude'] as num).toDouble()]);
      }

      String directionsCoords = routeWaypoints.map((c) => "${c[0]},${c[1]}").join(";");
      final String directionsUrl = "https://api.mapbox.com/directions/v1/mapbox/driving/$directionsCoords";

      final dirResponse = await _dio.get(
        directionsUrl, 
        queryParameters: {
          "access_token": _mapboxToken,
          "geometries": "geojson",
          "overview": "full",
          "steps": "true",
        },
        options: Options(
          headers: {'Accept': 'application/json'},
          validateStatus: (status) => true,
        ),
      );

      debugPrint("DIRECTIONS HTTP STATUS: ${dirResponse.statusCode}");

      if (dirResponse.statusCode != 200 || dirResponse.data == null || dirResponse.data['code'] != 'Ok') {
        String msg = dirResponse.data?['message'] ?? 'Mapbox Directions service returned status ${dirResponse.statusCode}';
        debugPrint("[OPTIMIZER] DIRECTIONS MAPBOX ERROR: $msg");
        return {
          'success': false, 
          'error': 'DIRECTIONS_API_FAILED', 
          'message': 'Directions API error: $msg'
        };
      }

      final route = dirResponse.data['routes'][0];
      final List legs = route['legs'];
      final DateTime now = DateTime.now();
      double cumulativeDuration = 0;

      for (int i = 0; i < optimizedStops.length; i++) {
        cumulativeDuration += (legs[i]['duration'] as num).toDouble();
        optimizedStops[i]['estimated_arrival'] = DateFormat('h:mm a').format(
          now.add(Duration(seconds: cumulativeDuration.toInt()))
        );
        optimizedStops[i]['distance_to_reach'] = ((legs[i]['distance'] as num).toDouble()) / 1000.0;
      }

      final double totalDistanceKm = ((route['distance'] as num).toDouble()) / 1000.0;
      final int totalDurationMins = (((route['duration'] as num).toDouble()) / 60.0).round();

      final Map<String, dynamic> optimizedData = {
        'generated_at': ServerValue.timestamp,
        'config_hash': configHash,
        'start_lat': currentLat,
        'start_lng': currentLng,
        'total_distance_km': totalDistanceKm,
        'estimated_duration_minutes': totalDurationMins,
        'estimated_completion': DateFormat('h:mm a').format(
          now.add(Duration(seconds: ((route['duration'] as num).toDouble()).toInt()))
        ),
        'geometry': jsonEncode(route['geometry']),
        'stops': optimizedStops,
        'success': true,
      };

      try {
        await _database.ref('driver_routes/$sessionId/optimized_route').set(optimizedData);
        debugPrint("[OPTIMIZER] FIREBASE SAVE SUCCESS for optimized route");
      } catch (e) {
        debugPrint("[OPTIMIZER] FIREBASE SAVE FAILED: $e");
        optimizedData['firebase_save_error'] = e.toString();
      }

      return optimizedData;
    } on DioException catch (e) {
      debugPrint("[OPTIMIZER] DIO EXCEPTION IN DIRECT MAPBOX: ${e.message}");
      return {
        'success': false,
        'error': 'NETWORK_ERROR',
        'message': e.response == null 
            ? 'Network Error: Unable to connect to routing service.' 
            : 'Routing Service Error: HTTP ${e.response?.statusCode}'
      };
    } catch (e) {
      debugPrint("[OPTIMIZER] CRITICAL FAILURE IN DIRECT MAPBOX: $e");
      return {'success': false, 'error': 'CRITICAL_FAILURE', 'message': 'Route optimization failed: $e'};
    }
  }

  /// Greedy Nearest Neighbor solver
  List<int> _solveNN(List durationsFromStart) {
    List<MapEntry<int, double>> stops = [];
    for (int i = 1; i < durationsFromStart.length; i++) {
      stops.add(MapEntry(i, (durationsFromStart[i] as num).toDouble()));
    }
    stops.sort((a, b) => a.value.compareTo(b.value));
    return stops.map((e) => e.key).toList();
  }

  Future<Map<String, dynamic>?> _getOptimizedRouteViaProxy({
    required String sessionId,
    required double currentLat,
    required double currentLng,
    required List<Map<String, dynamic>> remainingPuroks,
    String? configHash,
  }) async {
    try {
      final String proxyUrl = "https://indigo-bear-885857.hostingersite.com/backend/route_optimization.php";
      final response = await _dio.post(
        proxyUrl,
        data: {
          "driver_lat": currentLat,
          "driver_lng": currentLng,
          "stops": remainingPuroks.map((p) => {
            "name": p['name'],
            "lat": (p['lat'] as num).toDouble(),
            "lng": (p['lng'] as num).toDouble(),
          }).toList()
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => true,
        ),
      );

      if (response.statusCode == 200 && response.data != null && response.data['success'] == true) {
        final Map<String, dynamic> optimizedData = Map<String, dynamic>.from(response.data);
        optimizedData['config_hash'] = configHash;
        
        try {
          await _database.ref('driver_routes/$sessionId/optimized_route').set(optimizedData);
        } catch (fbErr) {
          debugPrint("[OPTIMIZER] PROXY: Firebase sync failed: $fbErr");
        }
        return optimizedData;
      }
      return {'success': false, 'message': 'Proxy server error: ${response.statusCode}'};
    } catch (e) {
      debugPrint("[OPTIMIZER] PROXY EXCEPTION: $e");
      return {'success': false, 'message': 'Proxy exception: $e'};
    }
  }
}
