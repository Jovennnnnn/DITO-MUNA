import 'dart:math';
import 'holiday_tracker.dart';

class PredictionEngine {
  // Constants from Municipality Standards (as described in Kotlin spec)
  static const double wasteDensityPerSqm = 0.0217; // kg per sqm
  static const double truckCapacityKg = 5000.0;

  // Purok Areas (Estimated sqm for Balintawak)
  static final Map<String, double> purokAreas = {
    "Purok 1": 15000,
    "Purok 2": 12000,
    "Purok 3": 18000,
    "Purok 4": 10000,
    "Dos Riles": 25000,
    "Sentro": 30000,
    "San Isidro": 20000,
    "Paraiso": 15000,
    "Riverside": 12000,
    "Kalaw Street": 8000,
    "Home Subdivision": 40000,
    "Tanco Road / Ayala Highway": 35000,
  };

  /// 1. Waste Volume Prediction Logic
  /// Formula: Area * Density * HolidayMultiplier + PerformanceRefinement
  static double predictWasteVolume(String purokName, {int stopCount = 0, DateTime? date}) {
    double area = purokAreas[purokName] ?? 10000.0; // Default if not found
    double multiplier = HolidayTracker.getMultiplier(date ?? DateTime.now());
    
    double prediction = area * wasteDensityPerSqm * multiplier;

    // Performance Refinement: More stops in previous routes suggest heavier waste
    if (stopCount > 10) {
      prediction *= 1.15; // 15% increase for heavy areas
    }

    return prediction;
  }

  /// Predict Volume for the whole week
  static double predictWeeklyVolume(String purokName, {int avgStops = 0}) {
    double total = 0;
    DateTime today = DateTime.now();
    for (int i = 0; i < 7; i++) {
      total += predictWasteVolume(purokName, stopCount: avgStops, date: today.add(Duration(days: i)));
    }
    return total;
  }

  /// 2. Arrival Estimates (Simple Linear Regression)
  /// Y = mX + b
  /// X = Distance (km)
  /// Y = Time (minutes)
  /// m = Slope (average minutes per km)
  static double estimateArrivalTime(double distanceKm, List<double> recentSpeeds) {
    if (recentSpeeds.isEmpty) return distanceKm * 5.0; // Default 5 mins per km

    // Calculate 'm' (slope) based on recent speeds (km/h)
    // Average speed in km/min
    double avgSpeedKmh = recentSpeeds.reduce((a, b) => a + b) / recentSpeeds.length;
    if (avgSpeedKmh < 1.0) avgSpeedKmh = 5.0; // Avoid division by zero, min speed 5km/h

    double minutesPerKm = 60.0 / avgSpeedKmh;
    
    // Y = mX (b is assumed 0 for simple distance/time)
    return distanceKm * minutesPerKm;
  }

  /// 3. Mean Absolute Error (MAE) for Prediction Accuracy
  /// MAE = Sum(|Actual - Predicted|) / n
  static double calculateMAE(List<double> actuals, List<double> predicteds) {
    if (actuals.isEmpty || actuals.length != predicteds.length) return 0.0;

    double totalError = 0.0;
    for (int i = 0; i < actuals.length; i++) {
      totalError += (actuals[i] - predicteds[i]).abs();
    }

    return totalError / actuals.length;
  }

  /// 4. Accuracy Percentage based on MAE
  /// Higher MAE = Lower Accuracy
  static double calculateAccuracyPercentage(double mae, double averageActual) {
    if (averageActual <= 0) return 100.0;
    double accuracy = (1 - (mae / averageActual)) * 100;
    return max(0, min(100, accuracy));
  }
}
