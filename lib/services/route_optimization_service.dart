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
    debugPrint("========== ROUTE OPTIMIZATION START ==========");
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

    // WEB PROXY LOGIC
    // If running on Web, use the Hostinger backend as a proxy to bypass origin restrictions.
    if (kIsWeb) {
      debugPrint("TRANSPORT: HOSTINGER_PROXY");
      return await _getOptimizedRouteViaProxy(
        sessionId: sessionId,
        currentLat: currentLat,
        currentLng: currentLng,
        remainingPuroks: remainingPuroks,
        configHash: configHash,
      );
    }

    debugPrint("TRANSPORT: DIRECT_MAPBOX");
    try {
      // 1. Validate Coordinates
      List<Map<String, dynamic>> validPuroks = [];
      List<String> invalidPuroks = [];

      for (var p in remainingPuroks) {
        final double lat = (p['latitude'] ?? p['lat'] ?? 0.0).toDouble();
        final double lng = (p['longitude'] ?? p['lng'] ?? 0.0).toDouble();
        final String name = p['name'] ?? 'Unknown';

        if (lat < -90 || lat > 90 || lng < -180 || lng > 180 || (lat == 0 && lng == 0)) {
          invalidPuroks.add(name);
          debugPrint("INVALID COORDINATES for $name: $lat, $lng");
        } else {
          validPuroks.add(p);
        }
      }

      if (invalidPuroks.isNotEmpty) {
        debugPrint("FAILURE: Invalid coordinates found for: ${invalidPuroks.join(', ')}");
        return {
          'success': false, 
          'error': 'INVALID_COORDINATES', 
          'message': 'Missing/invalid coordinates for: ${invalidPuroks.join(', ')}'
        };
      }

      // 2. Build Coordinates List (Index 0 = Driver) - MUST BE lng,lat
      List<List<double>> allCoords = [[currentLng, currentLat]];
      for (var p in validPuroks) {
        allCoords.add([(p['longitude'] ?? p['lng'] as num).toDouble(), (p['latitude'] ?? p['lat'] as num).toDouble()]);
      }

      String coordsString = allCoords.map((c) => "${c[0]},${c[1]}").join(";");

      // 3. STAGE C: Mapbox Matrix API
      debugPrint("STAGE: MATRIX");
      debugPrint("COORDINATE COUNT: ${allCoords.length}");
      debugPrint("COORDINATES: $coordsString");
      debugPrint("REQUEST HOST: api.mapbox.com");
      debugPrint("PROFILE: mapbox/driving");
      
      final String matrixUrl = "https://api.mapbox.com/directions-matrix/v1/mapbox/driving/$coordsString";
      
      try {
        debugPrint("========== MAPBOX MATRIX REQUEST ==========");
        debugPrint("URL: $matrixUrl");
        debugPrint("METHOD: GET");
        debugPrint("COORDINATE COUNT: ${allCoords.length}");

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
        debugPrint("MATRIX RESPONSE BODY: ${matrixResponse.data}");

        if (matrixResponse.statusCode != 200 || matrixResponse.data['code'] != 'Ok') {
          debugPrint("MATRIX MAPBOX MESSAGE: ${matrixResponse.data['message']}");
          return {
            'success': false, 
            'error': 'MATRIX_API_FAILED', 
            'message': 'Matrix API failed: ${matrixResponse.data['message'] ?? matrixResponse.statusCode}'
          };
        }

        final List durationsFromStart = matrixResponse.data['durations'][0];
        debugPrint("MATRIX DIMENSIONS: 1 x ${durationsFromStart.length}");

        // 4. STAGE D: Solve Order (Greedy Nearest Neighbor)
        debugPrint("NN START NODE: 0");
        List<int> optimizedIndices = _solveNN(durationsFromStart);
        debugPrint("NN ORDER: ${optimizedIndices.join(' -> ')}");

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

        // 5. STAGE E: Mapbox Directions API for Geometry
        debugPrint("========== MAPBOX DIRECTIONS REQUEST ==========");
        List<List<double>> routeWaypoints = [[currentLng, currentLat]];
        for (var s in optimizedStops) {
          routeWaypoints.add([s['longitude'], s['latitude']]);
        }

        String directionsCoords = routeWaypoints.map((c) => "${c[0]},${c[1]}").join(";");
        final String directionsUrl = "https://api.mapbox.com/directions/v1/mapbox/driving/$directionsCoords";
        
        debugPrint("URL: $directionsUrl");
        debugPrint("WAYPOINT COUNT: ${routeWaypoints.length}");

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
        debugPrint("DIRECTIONS RESPONSE BODY: ${dirResponse.data}");

        if (dirResponse.statusCode != 200 || dirResponse.data['code'] != 'Ok') {
          debugPrint("DIRECTIONS MAPBOX MESSAGE: ${dirResponse.data['message']}");
          return {
            'success': false, 
            'error': 'DIRECTIONS_API_FAILED', 
            'message': 'Directions API failed: ${dirResponse.data['message'] ?? dirResponse.statusCode}'
          };
        }

        final route = dirResponse.data['routes'][0];
        final List legs = route['legs'];
        final DateTime now = DateTime.now();
        double cumulativeDuration = 0;

        debugPrint("DIRECTIONS ROUTE DISTANCE: ${route['distance']}");
        debugPrint("DIRECTIONS ROUTE DURATION: ${route['duration']}");

        // Update stops with precise road-based ETAs and distances
        for (int i = 0; i < optimizedStops.length; i++) {
          cumulativeDuration += legs[i]['duration'];
          optimizedStops[i]['estimated_arrival'] = DateFormat('h:mm a').format(
            now.add(Duration(seconds: cumulativeDuration.toInt()))
          );
          optimizedStops[i]['distance_to_reach'] = legs[i]['distance'] / 1000.0;
        }

        final Map<String, dynamic> optimizedData = {
          'generated_at': ServerValue.timestamp,
          'config_hash': configHash,
          'start_lat': currentLat,
          'start_lng': currentLng,
          'total_distance_km': route['distance'] / 1000.0,
          'estimated_duration_minutes': (route['duration'] / 60.0).round(),
          'estimated_completion': DateFormat('h:mm a').format(
            now.add(Duration(seconds: route['duration'].toInt()))
          ),
          'geometry': jsonEncode(route['geometry']),
          'stops': optimizedStops,
        };

        // 6. STAGE F: Firebase Save
        debugPrint("========== FIREBASE SAVE ==========");
        try {
          await _database.ref('driver_routes/$sessionId/optimized_route').set(optimizedData);
          debugPrint("FIREBASE SAVE SUCCESS");
        } catch (e) {
          debugPrint("FIREBASE SAVE FAILED: $e");
          optimizedData['firebase_save_error'] = e.toString();
        }

        optimizedData['success'] = true;
        debugPrint("========== ROUTE OPTIMIZATION COMPLETE ==========");
        return optimizedData;

      } on DioException catch (e) {
        debugPrint("========== ROUTE OPTIMIZATION ERROR ==========");
        debugPrint("DIO TYPE: ${e.type}");
        debugPrint("MESSAGE: ${e.message}");
        debugPrint("URL: ${e.requestOptions.uri}");
        debugPrint("STATUS: ${e.response?.statusCode}");
        debugPrint("RESPONSE DATA: ${e.response?.data}");
        debugPrint("RESPONSE HEADERS: ${e.response?.headers}");
        if (e.response == null) {
          debugPrint("NO HTTP RESPONSE RECEIVED (CORS or Network error)");
        }
        debugPrint("==========================================");
        return {
          'success': false, 
          'error': 'NETWORK_ERROR', 
          'message': e.response == null ? 'Network Error: Browser or origin block' : 'Server Error: ${e.response?.statusCode}'
        };
      }
    } catch (e) {
      debugPrint("CRITICAL ROUTE OPTIMIZATION FAILURE: $e");
      return {'success': false, 'error': 'CRITICAL_FAILURE', 'message': 'Critical Error: $e'};
    }
  }

  /// Greedy Nearest Neighbor solver
  List<int> _solveNN(List durationsFromStart) {
    // durationsFromStart[i] is the duration from driver to stop i
    List<MapEntry<int, double>> stops = [];
    for (int i = 1; i < durationsFromStart.length; i++) {
      stops.add(MapEntry(i, (durationsFromStart[i] as num).toDouble()));
    }
    
    // Sort by duration (Nearest first)
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
      debugPrint("--- PROXY OPTIMIZATION START (WEB) ---");
      final String proxyUrl = "https://indigo-bear-885857.hostingersite.com/backend/route_optimization.php";
      debugPrint("PROXY URL: $proxyUrl");
      debugPrint("DRIVER GPS SENT TO PROXY: $currentLat, $currentLng");
      debugPrint("STOP COUNT SENT: ${remainingPuroks.length}");

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

      debugPrint("PROXY HTTP STATUS: ${response.statusCode}");
      debugPrint("PROXY RESPONSE DATA: ${response.data}");

      if (response.statusCode == 200 && response.data['success'] == true) {
        final Map<String, dynamic> optimizedData = Map<String, dynamic>.from(response.data);
        // Inject hash into the proxied response before persistence
        optimizedData['config_hash'] = configHash;
        
        // Save result to Firebase locally for tracking sync (persistence)
        try {
          await _database.ref('driver_routes/$sessionId/optimized_route').set(optimizedData);
          debugPrint("PROXY: Result synced to Firebase (Hash: $configHash).");
        } catch (fbErr) {
          debugPrint("PROXY: Firebase sync failed: $fbErr");
        }
        
        debugPrint("--- PROXY OPTIMIZATION COMPLETE ---");
        return optimizedData;
      } else {
        String stage = response.data['stage'] ?? 'UNKNOWN';
        String errorMsg = response.data['message'] ?? 'Backend proxy failed';
        int? httpStatus = response.data['http_status'];
        String? mapboxCode = response.data['mapbox_code'];
        
        debugPrint("PROXY FAILURE at STAGE $stage");
        debugPrint("HTTP STATUS: $httpStatus");
        debugPrint("MAPBOX CODE: $mapboxCode");
        debugPrint("MESSAGE: $errorMsg");
        
        return {
          'success': false,
          'error': 'PROXY_FAILED',
          'stage': stage,
          'message': errorMsg,
          'http_status': httpStatus,
          'mapbox_code': mapboxCode
        };
      }
    } on DioException catch (e) {
      debugPrint("========== PROXY ERROR ==========");
      debugPrint("TYPE: ${e.type}");
      debugPrint("MESSAGE: ${e.message}");
      debugPrint("STATUS: ${e.response?.statusCode}");
      return {
        'success': false,
        'error': 'PROXY_NETWORK_ERROR',
        'message': e.response == null ? 'Network Error: Unable to reach backend proxy.' : 'Proxy Server Error: ${e.response?.statusCode}'
      };
    } catch (e) {
      debugPrint("CRITICAL PROXY FAILURE: $e");
      return {
        'success': false,
        'error': 'PROXY_CRITICAL',
        'message': 'Critical Error: $e'
      };
    }
  }
}
