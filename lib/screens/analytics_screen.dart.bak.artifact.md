# Replace Mock Data with Real Firebase/API Data in Analytics Screen

The user wants to replace mock data with real data for four components in the Analytics Dashboard:
1.  **Routes Completed**
2.  **Total Coverage**
3.  **Truck Status (Donut Chart)**
4.  **Complaints (Donut Chart)**

## Proposed Changes

### [Analytics Screen](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/analytics_screen.dart)

- **State Variables**: Add `_totalRoutes`, `_completedRoutes`, and `_coveragePercent` to track route progress. Add `StreamSubscription` objects for cleanup.
- **Data Fetching**:
    - Update `_fetchChartData` to include a listener for `driver_routes` in Firebase to calculate route stats.
    - Ensure `truck_locations` and `getComplaints()` listeners correctly populate the state maps.
    - Properly manage `StreamSubscription` to avoid memory leaks.
- **UI Update**:
    - Update `_buildMetricCard` calls for "Routes Completed" and "Total Coverage" to use real state variables.
    - Update `_buildTruckDonutChart` and `_buildComplaintsDonutChart` to render sections based on real data instead of hardcoded values.
- **Cleanup**: Implement `dispose()` to cancel all active stream subscriptions.

```dart
// Example of the proposed changes in _fetchChartData
void _fetchChartData() {
  _trucksSubscription = _database.ref('truck_locations').onValue.listen((event) {
    if (event.snapshot.exists) {
      final Map data = event.snapshot.value as Map;
      final Map<String, double> counts = {"Active": 0, "Idle": 0, "Full": 0};
      data.forEach((key, value) {
        String status = value['status']?.toString().toLowerCase() ?? 'idle';
        if (status == 'active') counts['Active'] = counts['Active']! + 1;
        else if (status == 'full') counts['Full'] = counts['Full']! + 1;
        else counts['Idle'] = counts['Idle']! + 1;
      });
      if (mounted) setState(() => _truckStatusData = counts);
    }
  });

  _routesSubscription = _database.ref('driver_routes').onValue.listen((event) {
    if (event.snapshot.exists) {
      final Map data = event.snapshot.value as Map;
      int total = 0;
      int completed = 0;
      data.forEach((key, value) {
        total++;
        if (value is Map && value['route_status'] == 'COMPLETED') completed++;
      });
      if (mounted) {
        setState(() {
          _totalRoutes = total;
          _completedRoutes = completed;
          _coveragePercent = total > 0 ? (completed / total) * 100 : 0.0;
        });
      }
    }
  });

  _apiService.getComplaints().then((response) {
    if (response.data['success'] == true) {
      final List complaints = response.data['data'];
      final Map<String, double> counts = {"Pending": 0, "In Progress": 0, "Resolved": 0};
      for (var c in complaints) {
        String status = c['status'].toString().toLowerCase().replaceAll('_', ' ');
        if (status == 'pending') counts['Pending'] = counts['Pending']! + 1;
        else if (status == 'in progress') counts['In Progress'] = counts['In Progress']! + 1;
        else if (status == 'resolved') counts['Resolved'] = counts['Resolved']! + 1;
      }
      if (mounted) setState(() => _complaintStatusData = counts);
    }
  });
}
```

## Verification Plan

### Manual Verification
1.  **Open the Analytics Screen**: Navigate to the Analytics tab in the Admin Dashboard.
2.  **Verify Metrics**:
    - "Routes Completed" should show actual counts from Firebase (e.g., "1/5" instead of "0/12").
    - "Total Coverage" should show the percentage of completed routes.
3.  **Verify Charts**:
    - "Truck Status" Donut Chart should reflect the actual number of Active, Full, and Idle trucks.
    - "Complaints" Donut Chart should reflect the actual number of Pending, In Progress, and Resolved complaints.
4.  **Real-time Updates**: Modify a truck's status or a route status in Firebase and verify that the dashboard updates immediately.
