import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../utils/app_theme.dart';
import 'driver_track_truck_screen.dart';

class ViewDailyRoutesScreen extends StatefulWidget {
  final UserData user;
  const ViewDailyRoutesScreen({super.key, required this.user});

  @override
  State<ViewDailyRoutesScreen> createState() => _ViewDailyRoutesScreenState();
}

class _ViewDailyRoutesScreenState extends State<ViewDailyRoutesScreen> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  List<Map<String, dynamic>> _routes = [];

  @override
  void initState() {
    super.initState();
    _fetchRoutesForDate(_selectedDate);
  }

  Future<void> _fetchRoutesForDate(DateTime date) async {
    setState(() {
      _isLoading = true;
      _selectedDate = date;
    });

    final String dateStr = DateFormat('yyyy-MM-dd').format(date);
    
    try {
      // Query driver_routes by driver_id
      // We filter by date locally because RTDB doesn't support multiple filters well 
      // without composite keys, and a driver's total routes shouldn't be massive.
      final snapshot = await _database.ref('driver_routes')
          .orderByChild('driver_id')
          .equalTo(widget.user.userId)
          .get();

      final List<Map<String, dynamic>> filteredRoutes = [];
      if (snapshot.exists && snapshot.value != null) {
        final Map data = snapshot.value as Map;
        data.forEach((key, value) {
          final Map routeData = value as Map;
          if (routeData['date'] == dateStr) {
            filteredRoutes.add({
              ...routeData,
              'id': key.toString(),
            });
          }
        });
      }

      // Sort by start time / timestamp desc
      filteredRoutes.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

      if (mounted) {
        setState(() {
          _routes = filteredRoutes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching routes: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load routes: $e")),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.tealText,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      _fetchRoutesForDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("View Daily Routes", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF2C3E50),
      ),
      body: Column(
        children: [
          _buildDateHeader(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.tealText))
              : _routes.isEmpty 
                  ? _buildEmptyState()
                  : _buildRoutesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: InkWell(
        onTap: () => _selectDate(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.tealText.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Selected Date", style: TextStyle(color: AppColors.tealText, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(
                    DateFormat('MMMM dd, yyyy').format(_selectedDate),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2C3E50)),
                  ),
                ],
              ),
              const Icon(Icons.calendar_month_rounded, color: AppColors.tealText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.route_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "No routes recorded for this date.",
            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text("Try selecting a different date from the calendar.", style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildRoutesList() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _routes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final route = _routes[index];
        final String startTime = route['start_time'] ?? "--:--";
        final String finishTime = route['end_time'] ?? route['finishTime'] ?? "Ongoing";
        final double distance = (route['total_distance'] ?? 0.0).toDouble();
        final String status = (route['route_status'] ?? "ACTIVE").toString().toUpperCase();
        
        Color statusColor = status == "COMPLETED" ? Colors.green : Colors.blue;
        if (status == "ACTIVE") statusColor = Colors.orange;

        return InkWell(
          onTap: () => _openHistoricalMap(route['id']),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10)),
                    ),
                    Text(
                      "Trip #${_routes.length - index}",
                      style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("DURATION", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text("$startTime - $finishTime", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF2C3E50))),
                        ],
                      ),
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade200),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("DISTANCE", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text("${distance.toStringAsFixed(2)} km", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF2C3E50))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(route['truck_id'] ?? "Unknown", style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const Row(
                      children: [
                        Text("View Map", style: TextStyle(color: AppColors.tealText, fontWeight: FontWeight.w800, fontSize: 13)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.tealText),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openHistoricalMap(String sessionId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverTrackTruckScreen(
          currentSessionId: sessionId,
          isHistorical: true,
        ),
      ),
    );
  }
}
