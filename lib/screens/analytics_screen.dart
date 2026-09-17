import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../utils/custom_notification.dart';
import '../widgets/custom_snackbar.dart';
import '../utils/app_theme.dart';
import '../api/api_service.dart';
import '../api/api_client.dart';
import '../utils/prediction_engine.dart';
import '../utils/system_logger.dart';

class AnalyticsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  final Function(int)? onNavigate;
  const AnalyticsScreen({super.key, this.isEmbedded = false, this.onBack, this.onNavigate});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with TickerProviderStateMixin {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  bool _showHeaderShadow = true;
  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;

  Map<String, double> _truckStatusData = {"Active": 0, "Full": 0, "Idle": 0};
  Map<String, double> _complaintStatusData = {"Pending": 0, "In Progress": 0, "Resolved": 0};
  Map<String, double> _complaintSourceData = {"Residents": 0, "Drivers": 0};
  Map<String, int> _purokFrequencyData = {};
  Map<String, int> _purokComplaintData = {};
  String _selectedArea = "All Areas";
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  bool _isDateRange = true;

  double _avgCollectionTime = 0.0;
  int _stopsPerRoute = 0;
  double _distanceCovered = 0.0;
  double _predictionAccuracy = 0.0;
  double _maeValue = 0.0;

  int _totalRoutes = 0;
  int _completedRoutes = 0;
  double _coveragePercent = 0.0;
  String? _routeTrend;
  bool _routeTrendPositive = true;

  double _issueRate = 0.0;
  String? _coverageTrend;
  bool _coverageTrendPositive = true;
  String? _issueTrend;
  bool _issueTrendPositive = true;

  StreamSubscription? _trucksSubscription;
  StreamSubscription? _routesSubscription;
  StreamSubscription? _progressSubscription;
  StreamSubscription? _truckIssuesSubscription;
  StreamSubscription? _truckRegistrySubscription;
  StreamSubscription? _residentComplaintsFbSubscription;

  // Cache for raw data
  Map _allDriverRoutes = {};
  Map _allCollectionProgress = {};
  Map _allTruckLocations = {};
  Map _truckRegistry = {};
  List<dynamic> _allResidentComplaints = [];
  List<dynamic> _allDriverIssues = [];
  List<dynamic> _allFirebaseComplaints = [];

  // AI Insights variables
  String? _geminiSummary;
  double _tomorrowWaste = 0.0;
  double _weeklyWaste = 0.0;
  final Map<String, String> _etaEstimates = {};
  String _recommendations = "Analyzing fleet...";
  String _fleetInsight = "Analyzing fleet performance patterns...";
  String _complaintInsight = "Evaluating resident feedback trends...";
  String _coverageInsight = "Reviewing area coverage efficiency...";
  bool _isAiLoading = true;

  final _purokNames = [
    "Purok 1", "Purok 2", "Purok 3", "Purok 4",
    "Dos Riles", "Sentro", "San Isidro", "Paraiso",
    "Riverside", "Kalaw Street", "Home Subdivision",
    "Tanco Road / Ayala Highway", "Brixton Area"
  ];

  @override
  void initState() {
    super.initState();
    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _fetchChartData();
    refreshAllData();
    _scrollController.addListener(() {
      if (_scrollController.offset <= 0 && !_showHeaderShadow) {
        setState(() => _showHeaderShadow = true);
      } else if (_scrollController.offset > 0 && _showHeaderShadow) {
        setState(() => _showHeaderShadow = false);
      }
    });
  }

  @override
  void dispose() {
    _refreshRotationController.dispose();
    _scrollController.dispose();
    _trucksSubscription?.cancel();
    _routesSubscription?.cancel();
    _progressSubscription?.cancel();
    _truckIssuesSubscription?.cancel();
    _truckRegistrySubscription?.cancel();
    _residentComplaintsFbSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshAllStats({bool manual = false}) async {
    if (_isRefreshing) return;
    
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _showRefreshSpinner = manual;
        _manualPullDepth = manual ? 80.0 : 0.0; // Stick at 80 if manual
      });
    }
    _refreshRotationController.repeat();

    await Future.wait([
      _calculateAnalytics(),
      _generateAiInsights(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);

    _fetchChartData();
    _recalculateRoutesMetrics();

    if (manual) {
      // Hold and keep spinning for 2 seconds after data is loaded for visual confirmation
      await Future.delayed(const Duration(seconds: 2));
    }

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
      // Delay setting _showRefreshSpinner to false to allow retreat animation
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _showRefreshSpinner = false;
          _manualPullDepth = 0.0;
        });
      }
      _refreshRotationController.stop();

      if (manual) {
        showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(0.1),
          barrierDismissible: false,
          builder: (context) {
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            });
            return Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))
                  ],
                ),
                child: const Material(
                  color: Colors.transparent,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                      SizedBox(width: 12),
                      Text(
                        "Analytics metrics synchronized",
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1A1A1A)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }
    }
  }

  Future<void> refreshAllData() async {
    await _refreshAllStats(manual: false);
  }

  void _processComplaintsAndIssues() {
    final Map<String, int> purokCounts = {};

    // 1. RAW DATA GATHERING & NORMALIZATION
    // This follows the suggestion to use a unified model in-memory
    final List<Map<String, dynamic>> normalizedItems = [];

    String normalizeStatus(dynamic s) {
      if (s == null) return 'Pending';
      String str = s.toString().toUpperCase().trim().replaceAll('_', ' ');
      if (str == 'PENDING' || str == 'SUBMITTED' || str == '0') return 'Pending';
      if (str == 'IN PROGRESS' || str == 'UNDER REVIEW' || str.contains('PROGRESS') || str == '1') return 'In Progress';
      if (str == 'RESOLVED' || str == 'COMPLETED' || str == '2') return 'Resolved';
      return 'Pending';
    }

    DateTime? parseAnyDate(dynamic raw) {
      if (raw == null) return null;
      String s = raw.toString();
      if (s.contains('-')) {
        try {
          if (s.length >= 10) return DateTime.parse(s.substring(0, 10));
        } catch (_) {}
        try {
          return DateFormat('dd-MM-yyyy').parse(s.substring(0, 10));
        } catch (_) {}
      }
      int? ts = int.tryParse(s);
      if (ts != null) {
        if (ts < 10000000000) ts *= 1000;
        return DateTime.fromMillisecondsSinceEpoch(ts);
      }
      return null;
    }

    // Add Resident Complaints (from API/MySQL)
    for (var c in _allResidentComplaints) {
      DateTime? dt = parseAnyDate(c['created_at'] ?? c['timestamp'] ?? c['date']);
      if (dt != null) {
        normalizedItems.add({
          'id': c['id']?.toString() ?? '',
          'source': 'RESIDENT',
          'status': normalizeStatus(c['status']),
          'createdAt': dt,
          'purok': c['purok']?.toString(),
        });
      }
    }

    // Add Driver Issues (from Firebase truck_issues)
    for (var i in _allDriverIssues) {
      DateTime? dt = parseAnyDate(i['createdAt'] ?? i['timestamp']);
      if (dt != null) {
        normalizedItems.add({
          'id': i['id']?.toString() ?? '',
          'source': 'DRIVER',
          'status': normalizeStatus(i['status']),
          'createdAt': dt,
          'purok': i['purok']?.toString(), // Might be null, which is fine
        });
      }
    }

    // 2. FILTERING
    final String startDayStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange.start);
    final String endDayStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange.end);

    int matchedResidents = 0;
    int matchedDrivers = 0;
    final Map<String, double> filteredStatusCounts = {"Pending": 0, "In Progress": 0, "Resolved": 0};

    for (var item in normalizedItems) {
      // 1. Date Filtering
      DateTime dt = item['createdAt'] as DateTime;
      String itemDayStr = DateFormat('yyyy-MM-dd').format(dt);
      bool dateMatch = itemDayStr.compareTo(startDayStr) >= 0 && itemDayStr.compareTo(endDayStr) <= 0;
      if (!dateMatch) continue;

      // 2. Area Filtering
      String? itemPurok = item['purok'];
      bool areaMatch = _selectedArea == "All Areas" ||
          (itemPurok != null && itemPurok.toLowerCase().trim() == _selectedArea.toLowerCase().trim());
      
      if (!areaMatch) continue;

      // 3. Update Counts for Chart & Statistics
      String status = item['status'] as String;
      filteredStatusCounts[status] = filteredStatusCounts[status]! + 1;

      if (item['source'] == 'RESIDENT') {
        matchedResidents++;
      } else {
        matchedDrivers++;
      }

      // Track per-purok frequency for heatmaps
      if (itemPurok != null) {
        purokCounts[itemPurok] = (purokCounts[itemPurok] ?? 0) + 1;
      }
    }

    if (mounted) {
      setState(() {
        // Use FILTERED counts for the visual chart and legend
        _complaintStatusData = filteredStatusCounts;

        // Use FILTERED counts for the info text breakdown
        _complaintSourceData = {"Residents": matchedResidents.toDouble(), "Drivers": matchedDrivers.toDouble()};

        _purokComplaintData = purokCounts;
        final int totalFilteredIssues = (matchedResidents + matchedDrivers);
        _issueRate = _completedRoutes > 0 ? (totalFilteredIssues / _completedRoutes) * 100 : 0.0;

        final DateTimeRange prevRange = _getPreviousPeriod(_selectedDateRange, _isDateRange);
        final Map<String, dynamic> prevMetrics = _calculateMetricsInRange(prevRange.start, prevRange.end, _selectedArea);
        _calculateIssueTrends(prevRange, _selectedArea, _completedRoutes, (prevMetrics['completed'] as int?) ?? 0);
      });
    }

    debugPrint("ANALYTICS AGGREGATION DEBUG:");
    debugPrint("- Total Raw Items: ${normalizedItems.length} (Res: ${_allResidentComplaints.length}, Drv: ${_allDriverIssues.length})");
    debugPrint("- Matched Date & Area: ${matchedResidents + matchedDrivers} (Res: $matchedResidents, Drv: $matchedDrivers)");
    debugPrint("- Status Distribution: $filteredStatusCounts");
  }

  Future<void> _generateAiInsights() async {
    if (!mounted) return;

    setState(() => _isAiLoading = true);

    const apiKey = "PASTE_YOUR_GEMINI_API_KEY_HERE";
    final model = GenerativeModel(model: 'gemini-1.5-flash-latest', apiKey: apiKey);

    // Prepare data context for AI
    StringBuffer stats = StringBuffer("System Data (Balintawak Context):\n");
    stats.writeln("Area: $_selectedArea");
    stats.writeln("Date: ${DateFormat('yyyy-MM-dd').format(_selectedDateRange.start)}${_isDateRange ? " to ${DateFormat('yyyy-MM-dd').format(_selectedDateRange.end)}" : ""}");
    stats.writeln("Routes: $_completedRoutes/$_totalRoutes completed");
    stats.writeln("Complaints: ${_complaintStatusData['Pending']?.toInt() ?? 0} pending");
    stats.writeln("Efficiency: ${_avgCollectionTime.toStringAsFixed(2)} hours avg time, $_distanceCovered km covered");
    stats.writeln("MAE Accuracy: ${_predictionAccuracy.toStringAsFixed(1)}% (MAE: ${_maeValue.toStringAsFixed(2)} mins)");

    String topArea = _selectedArea == "All Areas"
        ? (_purokFrequencyData.entries.isNotEmpty
        ? _purokFrequencyData.entries.reduce((a, b) => a.value > b.value ? a : b).key
        : "Sentro")
        : _selectedArea;

    double predictedVol = PredictionEngine.predictWasteVolume(topArea, stopCount: _stopsPerRoute);
    double weeklyVol = PredictionEngine.predictWeeklyVolume(topArea, avgStops: _stopsPerRoute);

    // Dynamic ETA logic: Find nearby puroks or specific area
    _etaEstimates.clear();
    final List<String> targetPuroks = _selectedArea == "All Areas"
        ? _purokNames // Populate all for "View All" modal
        : [_selectedArea];

    for (var p in targetPuroks) {
      // Estimate based on system average speed or fallback to 20km/h
      double avgSysSpeed = (_avgCollectionTime > 0 && _distanceCovered > 0)
          ? (_distanceCovered / _avgCollectionTime)
          : 20.0;

      double dist = (_purokNames.indexOf(p) + 1) * 0.8; // Rough distance estimate
      double mins = PredictionEngine.estimateArrivalTime(dist, [avgSysSpeed, avgSysSpeed * 0.9]);
      DateTime arrival = DateTime.now().add(Duration(minutes: mins.toInt()));
      _etaEstimates[p] = DateFormat('h:mm a').format(arrival);
    }

    if (mounted) {
      setState(() {
        _tomorrowWaste = predictedVol;
        _weeklyWaste = weeklyVol;
      });
    }

    if (_selectedArea == "All Areas") {
      _purokFrequencyData.forEach((key, value) {
        stats.writeln("$key: $value visits this month");
      });
    }

    final prompt = """
        You are the Garbage Tracking System AI (Gemini 1.5 Flash) for the Municipality of Balintawak. 
        Analyze this collection and system performance data to provide a professional, detailed executive report.
        
        DATA CONTEXT:
        - Focus Area: $_selectedArea
        - Report Date: ${DateFormat('yyyy-MM-dd').format(_selectedDateRange.start)}${_isDateRange ? " to ${DateFormat('yyyy-MM-dd').format(_selectedDateRange.end)}" : ""}
        - $stats
        
        INSTRUCTIONS:
        1. Provide a long and detailed analytical summary of the performance.
        2. Identify bottlenecks or exceptional performance areas.
        3. Provide data-driven predictions for volume and arrival ETAs.
        4. Give 3-5 strategic recommendations for the fleet manager.

        RESPONSE FORMAT (STRICT):
        FLEET_INSIGHT: [Detailed 2-3 sentence analysis of truck status and efficiency]
        COMPLAINT_INSIGHT: [Detailed 2-3 sentence analysis of resident complaints and resolution rates]
        COVERAGE_INSIGHT: [Detailed 2-3 sentence analysis of area visits and coverage frequency]
        WASTE_VOLUME: Predicted: ${predictedVol.toStringAsFixed(0)}kg for $topArea
        ARRIVAL: ETA: ${(_avgCollectionTime * 60 * 0.8).toStringAsFixed(0)} mins for 2km
        RECOMMENDATIONS: [Strategic bullet points]
        OVERALL_CONCLUSION: [Final executive summary]
    """;

    try {
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      final text = response.text ?? "";

      if (mounted) {
        setState(() {
          if (text.contains("FLEET_INSIGHT:")) _fleetInsight = text.split("FLEET_INSIGHT:")[1].split("COMPLAINT_INSIGHT:")[0].trim();
          if (text.contains("COMPLAINT_INSIGHT:")) _complaintInsight = text.split("COMPLAINT_INSIGHT:")[1].split("COVERAGE_INSIGHT:")[0].trim();
          if (text.contains("COVERAGE_INSIGHT:")) _coverageInsight = text.split("COVERAGE_INSIGHT:")[1].split("WASTE_VOLUME:")[0].trim();

          if (text.contains("RECOMMENDATIONS:")) {
            _recommendations = text.split("RECOMMENDATIONS:")[1].split("OVERALL_CONCLUSION:")[0].trim();
          }
          if (text.contains("OVERALL_CONCLUSION:")) {
            _geminiSummary = text.split("OVERALL_CONCLUSION:")[1].trim();
          }
          _isAiLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _geminiSummary = "Unable to generate real-time AI insights. Please check connection.";
        });
      }
    }
  }

  Future<void> _exportReport(String category, String format) async {
    if (format.contains('PDF')) {
      _showPdfConfirmationDialog(category);
      return;
    }

    final String exportUrl = "${ApiClient.baseUrl}export_report.php";
    final String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange.start);
    final String endDateStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange.end);

    String wasteTomorrow = "${_tomorrowWaste.toInt()} kg";
    String wasteWeekly = "${_weeklyWaste.toInt()} kg";

    CustomNotification.showTopNotification(context, "Exporting $category to Excel...", false);

    final queryParams = {
      'type': _selectedArea == "All Areas" ? category : "$category - $_selectedArea",
      'format': 'xls',
      'start_date': dateStr,
      'end_date': endDateStr,
      'res_rate': "${_coveragePercent.toInt()}%",
      'avg_time': "${_avgCollectionTime.toStringAsFixed(1)} hours",
      'coverage': "${_coveragePercent.toInt()}%",
      'routes_done': "$_completedRoutes/$_totalRoutes",
      'active_count': "${_truckStatusData['Active']?.toInt() ?? 0}",
      'collecting_count': "${_truckStatusData['Active']?.toInt() ?? 0}",
      'full_count': "${_truckStatusData['Full']?.toInt() ?? 0}",
      'inactive_count': "${_truckStatusData['Idle']?.toInt() ?? 0}",
      'pending_count': "${_complaintStatusData['Pending']?.toInt() ?? 0}",
      'in_progress_count': "${_complaintStatusData['In Progress']?.toInt() ?? 0}",
      'resolved_count': "${_complaintStatusData['Resolved']?.toInt() ?? 0}",
      'dist': "${_distanceCovered.toStringAsFixed(1)} km",
      'stops': "$_stopsPerRoute",
      'coll_time': "${_avgCollectionTime.toStringAsFixed(1)} hours",
      'waste_tomorrow': wasteTomorrow,
      'waste_weekly': wasteWeekly,
      'insight1': _geminiSummary ?? "System performing normally.",
      'insight2': _recommendations,
      'total_drivers': "${_allDriverRoutes.values.map((e) => e['driver_id']).toSet().length}",
    };

    final uri = Uri.parse(exportUrl).replace(queryParameters: queryParams);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      await SystemLogger.logEvent("EXPORT", "Exported Excel report for $_selectedArea");

      if (mounted) {
        _showSuccessDialog(context, "Excel Report Generated",
            "Your analytics report for $_selectedArea has been generated and is downloading.");
      }
    } else {
      if (mounted) {
        CustomNotification.showTopNotification(context, "Could not launch export tool.", true);
      }
    }
  }

  void _showSuccessDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00897B))),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 14)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPdfConfirmationDialog(String category) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Confirm PDF Generation",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00897B))),
              const SizedBox(height: 12),
              Text("You are about to generate a detailed analytics report for $_selectedArea.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 14)),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _exportToNativePdf(category);
                        CustomNotification.showTopNotification(context, "Generating PDF report...", false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text("GENERATE", style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToNativePdf(String category) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('MMMM dd, yyyy').format(_selectedDateRange.start);
    final rangeStr = _isDateRange ? " to ${DateFormat('MMMM dd, yyyy').format(_selectedDateRange.end)}" : "";
    final genTime = DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now());
    final primaryColor = PdfColor.fromHex('#00BFA5');
    final textColor = PdfColor.fromHex('#2C3E50');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (pw.Context context) => pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("GARBAGE TRACKING SYSTEM", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    pw.Text("Official Analytics & Performance Report", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Area: $_selectedArea", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Period: $dateStr$rangeStr", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Generated: $genTime", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: primaryColor, thickness: 1),
            pw.SizedBox(height: 20),
          ],
        ),
        footer: (pw.Context context) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey300),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("GarbageBiz System | Confidential Performance Data", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                pw.Text("Page ${context.pageNumber} of ${context.pagesCount}", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
              ],
            ),
          ],
        ),
        build: (pw.Context context) => [
          pw.Text("1. Introduction", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: textColor)),
          pw.SizedBox(height: 10),
          pw.Text(
            "This document provides a comprehensive summary of the garbage collection system's performance.",
            style: pw.TextStyle(fontSize: 10, color: textColor, lineSpacing: 1.5),
          ),
          pw.SizedBox(height: 25),
          pw.Text("2. Fleet Performance & Visual Analytics", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: textColor)),
          pw.SizedBox(height: 15),
          pw.Row(
            children: [
              _buildPdfAnalysisCard("Truck Status Distribution", _truckStatusData, [PdfColors.green, PdfColors.amber, PdfColors.grey400], ["Active", "Full", "Idle"]),
              pw.SizedBox(width: 15),
              _buildPdfAnalysisCard("Complaint Status Overview", _complaintStatusData, [PdfColors.red, PdfColors.blue, PdfColors.green], ["Pending", "In Progress", "Resolved"]),
            ],
          ),
          pw.SizedBox(height: 15),
          _buildPdfInsightBox("Fleet Performance Analysis", _fleetInsight, primaryColor),
          pw.SizedBox(height: 30),
          pw.Text("3. Resident Feedback & Complaints Analysis", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: textColor)),
          pw.SizedBox(height: 15),
          _buildPdfInsightBox("Complaints Documentation", _complaintInsight, PdfColors.red),
          pw.SizedBox(height: 15),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              _buildPdfTableRow("Issue Type", "Distribution", isHeader: true),
              _buildPdfTableRow("Pending Complaints", "${_complaintStatusData['Pending']?.toInt() ?? 0}"),
              _buildPdfTableRow("Resolved Issues", "${_complaintStatusData['Resolved']?.toInt() ?? 0}"),
              _buildPdfTableRow("Active Investigations", "${_complaintStatusData['In Progress']?.toInt() ?? 0}"),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Text("4. Area Coverage & Frequency", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: textColor)),
          pw.SizedBox(height: 15),
          pw.Container(
            height: 180,
            padding: const pw.EdgeInsets.only(left: 10, right: 10, bottom: 20),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey100), borderRadius: pw.BorderRadius.circular(4)),
            child: _buildPdfBarChart(),
          ),
          pw.SizedBox(height: 15),
          _buildPdfInsightBox("Geospatial Coverage Analysis", _coverageInsight, PdfColors.blue),
          pw.SizedBox(height: 30),
          pw.Text("5. Performance Forecasts", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: textColor)),
          pw.SizedBox(height: 15),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              _buildPdfTableRow("Forecasting Metric", "Calculated Value", isHeader: true),
              _buildPdfTableRow("Tomorrow's Predicted Volume", "${_tomorrowWaste.toInt()} kg"),
              _buildPdfTableRow("Weekly Volume Projection", "${_weeklyWaste.toInt()} kg"),
              _buildPdfTableRow("Avg Stop Duration", "${_avgCollectionTime.toStringAsFixed(1)} hours"),
              _buildPdfTableRow("Prediction Confidence", "${_predictionAccuracy.toStringAsFixed(1)}%"),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Text("6. Strategic Recommendations", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: textColor)),
          pw.SizedBox(height: 10),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey200), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Text(_recommendations, style: pw.TextStyle(fontSize: 10, color: textColor, lineSpacing: 1.6)),
          ),
          pw.SizedBox(height: 30),
          pw.Text("7. Final Executive Conclusion", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: textColor)),
          pw.SizedBox(height: 15),
          pw.Container(
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E0F2F1'), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Text(
              _geminiSummary ?? "Based on the metrics above, the system is performing within expected operational boundaries.",
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor, lineSpacing: 1.5),
            ),
          ),
        ],
      ),
    );

    try {
      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: "GarbageBiz_Report_${DateFormat('yyyyMMdd').format(_selectedDateRange.start)}.pdf",
      );
      await SystemLogger.logEvent("EXPORT", "Generated PDF Report for $_selectedArea");
    } catch (e) {
      debugPrint("PDF Error: $e");
    }
  }

  pw.TableRow _buildPdfTableRow(String label, String value, {bool isHeader = false}) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(label, style: pw.TextStyle(fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 10)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(value, style: pw.TextStyle(fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 10)),
        ),
      ],
    );
  }

  pw.Widget _buildPdfDonutChart(Map<String, double> data, List<PdfColor> colors) {
    final values = data.values.toList();
    final total = values.fold(0.0, (a, b) => a + b);
    if (total == 0) return pw.Text("No Data");

    return pw.Container(
      width: 100,
      height: 100,
      child: pw.Chart(
        grid: pw.PieGrid(),
        datasets: List.generate(values.length, (index) {
          return pw.PieDataSet(
            value: values[index],
            color: colors[index % colors.length],
            drawSurface: true,
            innerRadius: 0.5,
          );
        }),
      ),
    );
  }

  pw.Widget _buildPdfAnalysisCard(String title, Map<String, double> data, List<PdfColor> colors, List<String> labels) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(15),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#F8F9FA'),
          borderRadius: pw.BorderRadius.circular(12),
          border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
        ),
        child: pw.Column(
          children: [
            pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 20),
            pw.Center(child: _buildPdfDonutChart(data, colors)),
            pw.SizedBox(height: 20),
            pw.Wrap(
              spacing: 12,
              children: List.generate(labels.length, (i) => _buildPdfLegendItem("${labels[i]} (${data[labels[i]]?.toInt()})", colors[i])),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildPdfBarChart() {
    final List<String> areas = _purokFrequencyData.keys.toList();
    if (areas.isEmpty) return pw.Text("No Frequency Data");

    final datasets = List.generate(areas.length, (index) {
      final count = _purokFrequencyData[areas[index]] ?? 0;
      return pw.BarDataSet(
        color: PdfColors.teal,
        width: 8,
        data: [pw.PointChartValue(index.toDouble(), count.toDouble())],
      );
    });

    return pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis(List.generate(areas.length, (i) => i.toDouble()), format: (v) => areas[v.toInt()], ticks: true),
        yAxis: pw.FixedAxis([0, 10, 20, 30, 40], ticks: true),
      ),
      datasets: datasets,
    );
  }

  pw.Widget _buildPdfLegendItem(String label, PdfColor color) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2))),
        pw.SizedBox(width: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
      ],
    );
  }

  pw.Widget _buildPdfInsightBox(String title, String content, PdfColor themeColor) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(left: pw.BorderSide(color: themeColor, width: 3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("AI Insight: $title", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: themeColor)),
          pw.SizedBox(height: 6),
          pw.Text(content, style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.4)),
        ],
      ),
    );
  }

  Future<void> _calculateAnalytics() async {
    final startStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange.start);
    final endStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange.end);

    final Query query = _database.ref('collection_logs').orderByChild('date');
    final event = await (_isDateRange ? query.startAt(startStr).endAt(endStr) : query.equalTo(startStr)).once();

    double totalDist = 0.0;
    int stopsCount = 0;
    double totalDuration = 0.0;
    int durationSessions = 0;

    if (event.snapshot.exists) {
      final Map data = event.snapshot.value as Map;
      data.forEach((key, value) {
        if (value is Map) {
          final zone = value['zoneName']?.toString() ?? "";
          if (_selectedArea == "All Areas" || zone == _selectedArea) {
            stopsCount++;
            if (value['duration_minutes'] != null) {
              totalDuration += double.tryParse(value['duration_minutes'].toString()) ?? 0;
              durationSessions++;
            }
            if (value['distance_km'] != null) {
              totalDist += double.tryParse(value['distance_km'].toString()) ?? 0;
            }
          }
        }
      });
    }

    // Fallback/Supplement with driver_routes if needed
    if (stopsCount == 0 || totalDist == 0) {
      _allDriverRoutes.forEach((sessionId, data) {
        if (data is Map) {
          final dateStr = data['date']?.toString() ?? "";
          if (dateStr.compareTo(startStr) >= 0 && dateStr.compareTo(endStr) <= 0) {
            totalDist += (data['final_distance'] ?? 0.0).toDouble();
            final progress = _allCollectionProgress[sessionId];
            if (progress is Map) {
              progress.forEach((k, v) {
                if (v is Map && v['completed'] == true) {
                  final areaName = v['name']?.toString() ?? "";
                  if (_selectedArea == "All Areas" || areaName == _selectedArea) {
                    stopsCount++;
                  }
                }
              });
            }
          }
        }
      });
    }

    if (mounted) {
      setState(() {
        _avgCollectionTime = durationSessions > 0 ? (totalDuration / durationSessions) / 60 : 0.0;
        _distanceCovered = totalDist;
        _stopsPerRoute = stopsCount;
        _maeValue = _avgCollectionTime > 0 ? (_avgCollectionTime * 0.08) * 60 : 1.2;
        _predictionAccuracy = PredictionEngine.calculateAccuracyPercentage(_maeValue, _avgCollectionTime * 60);
      });
    }

    final freqEvent = await _database.ref('collection_logs').once();
    if (freqEvent.snapshot.exists) {
      final Map data = freqEvent.snapshot.value as Map;
      final Map<String, int> freq = {};
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      data.forEach((key, value) {
        if (value is Map) {
          final dStr = value['date']?.toString() ?? "";
          final zone = value['zoneName']?.toString() ?? "";
          try {
            final date = DateFormat("yyyy-MM-dd").parse(dStr);
            if (date.isAfter(thirtyDaysAgo)) {
              freq[zone] = (freq[zone] ?? 0) + 1;
            }
          } catch (_) {}
        }
      });
      // if (mounted) setState(() => _purokFrequencyData = freq); // Removed to avoid overwriting coverage chart
    }
  }

  void _fetchChartData() {
    _trucksSubscription?.cancel();
    _routesSubscription?.cancel();
    _progressSubscription?.cancel();
    _truckIssuesSubscription?.cancel();
    _truckRegistrySubscription?.cancel();
    _residentComplaintsFbSubscription?.cancel();

    _truckRegistrySubscription = _database.ref('trucks').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _truckRegistry = event.snapshot.value as Map;
        _updateTruckStatusData();
      }
    });

    _trucksSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _allTruckLocations = event.snapshot.value as Map;
        _updateTruckStatusData();
      }
    });

    _routesSubscription = _database.ref('driver_routes').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _allDriverRoutes = event.snapshot.value as Map;
        _recalculateRoutesMetrics();
        _calculateAnalytics();
      }
    });

    _progressSubscription = _database.ref('collection_progress').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _allCollectionProgress = event.snapshot.value as Map;
        _recalculateRoutesMetrics();
        _calculateAnalytics();
      }
    });

    _truckIssuesSubscription = _database.ref('truck_issues').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List list = [];
        data.forEach((key, value) {
          list.add({...Map<String, dynamic>.from(value as Map), 'id': key});
        });
        _allDriverIssues = list;
        _processComplaintsAndIssues();
      }
    });

    _residentComplaintsFbSubscription = _database.ref('complaints').onValue.listen((event) {
      // Keep listener to ensure real-time consistency if system uses it,
      // but _processComplaintsAndIssues now strictly aligns with Resolve Radar (API + truck_issues).
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List list = [];
        data.forEach((key, value) {
          if (value is Map) {
            list.add({...Map<String, dynamic>.from(value), 'id': key});
          }
        });
        _allFirebaseComplaints = list;
        _processComplaintsAndIssues();
      }
    });

    _apiService.getComplaints().then((response) {
      debugPrint("API COMPLAINTS RESPONSE: ${response.data['success']}");
      if (response.data['success'] == true) {
        _allResidentComplaints = response.data['data'];
        debugPrint("API COMPLAINTS LOADED: ${_allResidentComplaints.length} records");
        _processComplaintsAndIssues();
      }
    }).catchError((e) {
      debugPrint("API COMPLAINTS ERROR: $e");
    });
  }

  void _updateTruckStatusData() {
    final Map<String, double> counts = {"Active": 0, "Idle": 0, "Full": 0};

    // Iterate over the official registry to ensure we only count valid trucks
    _truckRegistry.forEach((truckId, registryData) {
      // Find current live status from truck_locations
      final liveData = _allTruckLocations[truckId.toString()];

      if (liveData is Map) {
        String status = liveData['status']?.toString().toLowerCase() ?? 'idle';
        bool isOnline = liveData['isOnline'] == true;

        if (!isOnline) {
          counts['Idle'] = counts['Idle']! + 1;
        } else if (status == 'active' || status == 'collecting') {
          counts['Active'] = counts['Active']! + 1;
        } else if (status == 'full') {
          counts['Full'] = counts['Full']! + 1;
        } else {
          counts['Idle'] = counts['Idle']! + 1;
        }
      } else {
        // Truck exists in registry but has no live location/status record
        counts['Idle'] = counts['Idle']! + 1;
      }
    });

    debugPrint("ANALYTICS TRUCK STATUS DEBUG:");
    debugPrint("- TOTAL REGISTERED: ${_truckRegistry.length}");
    debugPrint("- FINAL COUNTS: $counts");

    if (mounted) setState(() => _truckStatusData = counts);
  }



  void _recalculateRoutesMetrics() {
    // Current period metrics
    var currentMetrics = _calculateMetricsInRange(
        _selectedDateRange.start,
        _selectedDateRange.end,
        _selectedArea,
        debug: true
    );

    // Previous period metrics for trend
    DateTimeRange prevRange = _getPreviousPeriod(_selectedDateRange, _isDateRange);
    var prevMetrics = _calculateMetricsInRange(
        prevRange.start,
        prevRange.end,
        _selectedArea,
        debug: false
    );

    if (mounted) {
      setState(() {
        _totalRoutes = currentMetrics['total'] as int;
        _completedRoutes = currentMetrics['completed'] as int;
        _coveragePercent = _totalRoutes > 0 ? (_completedRoutes / _totalRoutes) * 100 : 0.0;

        final Map<String, int> freq = {};
        if (currentMetrics['purokCompleted'] != null) {
          final Map<String, int> purokCompletedMap = currentMetrics['purokCompleted'] as Map<String, int>;
          final Map<String, int> purokExpectedMap = currentMetrics['purokExpected'] as Map<String, int>;
          purokCompletedMap.forEach((String key, int value) {
            final int total = purokExpectedMap[key] ?? 1;
            freq[key] = ((value / total) * 100).toInt();
          });
        }
        _purokFrequencyData = freq;

        // Calculate Trends
        double currentRate = _totalRoutes > 0 ? (_completedRoutes / _totalRoutes) : 0.0;
        double prevRate = prevMetrics['total']! > 0 ? (prevMetrics['completed']! / prevMetrics['total']!) : 0.0;

        if ((prevMetrics['total'] as int? ?? 0) > 0 || _totalRoutes > 0) {
          final double diff = (currentRate - prevRate) * 100;
          _routeTrend = "${diff.abs().toStringAsFixed(1)}%";
          _routeTrendPositive = diff >= 0;

          _coverageTrend = _routeTrend;
          _coverageTrendPositive = _routeTrendPositive;
        } else {
          _routeTrend = "N/A";
          _routeTrendPositive = true;
          _coverageTrend = "N/A";
        }

        // Process complaints will handle issue trends
        _processComplaintsAndIssues();
      });
    }
  }

  void _calculateIssueTrends(DateTimeRange prevRange, String areaFilter, int currentCompleted, int prevCompleted) {
    final startStr = DateFormat('yyyy-MM-dd').format(prevRange.start);
    final endStr = DateFormat('yyyy-MM-dd').format(prevRange.end);

    int prevIssues = 0;

    for (var c in _allResidentComplaints) {
      String? createdAt = c['created_at']?.toString();
      if (createdAt != null && createdAt.length >= 10) {
        String cDate = createdAt.substring(0, 10);
        if (cDate.compareTo(startStr) >= 0 && cDate.compareTo(endStr) <= 0) {
          String? purok = c['purok']?.toString();
          if (areaFilter == "All Areas" || purok == areaFilter) {
            prevIssues++;
          }
        }
      }
    }

    for (var i in _allDriverIssues) {
      dynamic rawTs = i['createdAt'];
      if (rawTs != null) {
        int ts = rawTs is int ? rawTs : int.tryParse(rawTs.toString()) ?? 0;
        if (ts > 0) {
          String iDate = DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(ts));
          if (iDate.compareTo(startStr) >= 0 && iDate.compareTo(endStr) <= 0) {
            if (areaFilter == "All Areas") prevIssues++;
          }
        }
      }
    }

    double prevRate = prevCompleted > 0 ? (prevIssues / prevCompleted) * 100 : 0.0;

    if (prevCompleted > 0 || currentCompleted > 0) {
      double diff = _issueRate - prevRate;
      _issueTrend = "${diff.abs().toStringAsFixed(1)}%";
      _issueTrendPositive = diff <= 0; // Negative is good for issues
    } else {
      _issueTrend = "N/A";
    }
  }

  // Helper for debug logging
  List<String> relevantSessionsInRange = [];

  Map<String, dynamic> _calculateMetricsInRange(DateTime start, DateTime end, String areaFilter, {bool debug = false}) {
    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);

    // Calculate days in range
    int days = end.difference(start).inDays + 1;

    // Determine which puroks to expect
    List<String> expectedPuroks = areaFilter == "All Areas" ? _purokNames : [areaFilter];

    // Key: date_areaName
    final Set<String> expectedUniqueKeys = {};
    final Set<String> completedUniqueKeys = {};

    // Per-purok stats
    final Map<String, int> purokExpected = {};
    final Map<String, int> purokCompleted = {};

    for (var p in expectedPuroks) {
      purokExpected[p] = days;
      purokCompleted[p] = 0;
      for (int i = 0; i < days; i++) {
        String dStr = DateFormat('yyyy-MM-dd').format(start.add(Duration(days: i)));
        expectedUniqueKeys.add("${dStr}_$p");
      }
    }

    int duplicatesRemoved = 0;
    int rawSessionsFound = 0;

    _allDriverRoutes.forEach((sessionId, data) {
      if (data is Map) {
        final String sId = sessionId.toString();
        final dateStr = data['date']?.toString() ?? "";
        bool inRange = dateStr.compareTo(startStr) >= 0 && dateStr.compareTo(endStr) <= 0;

        if (inRange) {
          rawSessionsFound++;
          // Check collection progress for this session
          final progress = _allCollectionProgress[sId];
          if (progress is Map) {
            progress.forEach((purokKey, purokData) {
              if (purokData is Map) {
                final areaName = purokData['name']?.toString() ?? "";
                if (areaName.isNotEmpty) {
                  // Apply area filter
                  if (areaFilter == "All Areas" || areaName == areaFilter) {
                    final String uniqueKey = "${dateStr}_$areaName";

                    if (purokData['completed'] == true) {
                      if (!completedUniqueKeys.contains(uniqueKey)) {
                        completedUniqueKeys.add(uniqueKey);
                        if (purokCompleted.containsKey(areaName)) {
                          purokCompleted[areaName] = purokCompleted[areaName]! + 1;
                        }
                      } else {
                        duplicatesRemoved++;
                      }
                    }

                    // In case a driver does a route not in our default expected set
                    if (!expectedUniqueKeys.contains(uniqueKey)) {
                      expectedUniqueKeys.add(uniqueKey);
                      purokExpected[areaName] = (purokExpected[areaName] ?? 0) + 1;
                    }
                  }
                }
              }
            });
          }
        }
      }
    });

    if (debug) {
      debugPrint("==================================================");
      debugPrint("ANALYTICS ROUTE DEBUG:");
      debugPrint("- SELECTED AREA: $areaFilter");
      debugPrint("- START DATE: $startStr");
      debugPrint("- END DATE: $endStr");
      debugPrint("- RAW SESSIONS IN RANGE: $rawSessionsFound");
      debugPrint("- TOTAL EXPECTED ASSIGNMENTS: ${expectedUniqueKeys.length}");
      debugPrint("- UNIQUE COMPLETED ROUTES: ${completedUniqueKeys.length}");
      debugPrint("- DUPLICATES REMOVED: $duplicatesRemoved");
      debugPrint("- FINAL: ${completedUniqueKeys.length} / ${expectedUniqueKeys.length}");
      debugPrint("==================================================");
    }

    return {
      'total': expectedUniqueKeys.length,
      'completed': completedUniqueKeys.length,
      'purokExpected': purokExpected,
      'purokCompleted': purokCompleted,
    };
  }

  DateTimeRange _getPreviousPeriod(DateTimeRange current, bool isRange) {
    if (!isRange) {
      // Single day: previous day
      final prevDay = current.start.subtract(const Duration(days: 1));
      return DateTimeRange(start: prevDay, end: prevDay);
    } else {
      // Date range: previous period of same duration
      final duration = current.end.difference(current.start);
      final prevEnd = current.start.subtract(const Duration(days: 1));
      final prevStart = prevEnd.subtract(duration);
      return DateTimeRange(start: prevStart, end: prevEnd);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 900;
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerMove: (event) {
                  // Track pull depth when at the very top of the scroll or already pulling
                  bool atTop = _scrollController.hasClients && _scrollController.offset <= 0;
                  if (!_isRefreshing && (atTop || _manualPullDepth > 0)) {
                    if (event.delta.dy > 0 || _manualPullDepth > 0) {
                      setState(() {
                        _manualPullDepth += event.delta.dy * 0.5; // Dampen the pull
                        if (_manualPullDepth < 0) _manualPullDepth = 0;
                        if (_manualPullDepth > 120) _manualPullDepth = 120; // Max pull depth
                        _showRefreshSpinner = _manualPullDepth > 0;
                      });
                    }
                  }
                },
                onPointerUp: (event) {
                  if (_manualPullDepth > 70 && !_isRefreshing) {
                    _refreshAllStats(manual: true);
                  } else if (!_isRefreshing) {
                    setState(() {
                      _manualPullDepth = 0;
                      _showRefreshSpinner = false;
                    });
                  }
                },
                child: Column(
                  children: [
                    _buildHeader(isMobile),
                    if (isMobile) _buildFilterBar(),
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false), // Disable glow/bounce
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          physics: (_manualPullDepth > 0 || _isRefreshing) 
                              ? const NeverScrollableScrollPhysics() 
                              : const ClampingScrollPhysics(), // Content stays 100% fixed at the top
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 48, vertical: 24),
                            child: Center(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Viewing Dashboard: $_selectedArea", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1A1A1A))),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Expanded(child: _buildMetricCard("Routes Done", "$_completedRoutes", Icons.local_shipping_rounded, const Color(0xFF4CAF50), trend: _routeTrend, isPositive: _routeTrendPositive)),
                                      const SizedBox(width: 8),
                                      Expanded(child: _buildMetricCard("Coverage", "${_coveragePercent.toInt()}%", Icons.map_rounded, const Color(0xFF2196F3), trend: _coverageTrend, isPositive: _coverageTrendPositive)),
                                      const SizedBox(width: 8),
                                      Expanded(child: _buildMetricCard("Issue Rate", "${_issueRate.toStringAsFixed(1)}%", Icons.warning_rounded, const Color(0xFFF44336), trend: _issueTrend, isPositive: _issueTrendPositive)),
                                    ],
                                  ),
                                  const SizedBox(height: 32),
                                  if (isMobile) ...[
                                    _buildChartSection("Truck Status", _buildTruckDonutChart(), legend: [
                                      _buildLegendItem("Active", (_truckStatusData['Active'] ?? 0).toInt(), Colors.green),
                                      _buildLegendItem("Full", (_truckStatusData['Full'] ?? 0).toInt(), Colors.amber),
                                      _buildLegendItem("Idle", (_truckStatusData['Idle'] ?? 0).toInt(), Colors.grey.shade300),
                                    ], onView: () => widget.onNavigate?.call(1)),
                                    const SizedBox(height: 24),
                                    _buildChartSection("Complaints", Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(height: 150, child: _buildComplaintsDonutChart()),
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                                          child: Text("Matched: ${_complaintSourceData['Residents']?.toInt()} Residents, ${_complaintSourceData['Drivers']?.toInt()} Drivers",
                                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                        ),
                                      ],
                                    ), legend: [
                                      _buildLegendItem("Pending", (_complaintStatusData['Pending'] ?? 0).toInt(), Colors.red),
                                      _buildLegendItem("In Progress", (_complaintStatusData['In Progress'] ?? 0).toInt(), Colors.blue),
                                      _buildLegendItem("Resolved", (_complaintStatusData['Resolved'] ?? 0).toInt(), Colors.green),
                                    ], onView: () => widget.onNavigate?.call(3)),
                                    const SizedBox(height: 24),
                                    _buildPurokChartSection(),
                                    const SizedBox(height: 24),
                                    _buildInsightsSection(isMobile),
                                  ] else ...[
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            children: [
                                              _buildPurokChartSection(),
                                              const SizedBox(height: 24),
                                              _buildInsightsSection(isMobile),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 24),
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            children: [
                                              _buildChartSection("Truck Status", _buildTruckDonutChart(), legend: [
                                                _buildLegendItem("Active", (_truckStatusData['Active'] ?? 0).toInt(), Colors.green),
                                                _buildLegendItem("Full", (_truckStatusData['Full'] ?? 0).toInt(), Colors.amber),
                                                _buildLegendItem("Idle", (_truckStatusData['Idle'] ?? 0).toInt(), Colors.grey.shade300),
                                              ], onView: () => widget.onNavigate?.call(1)),
                                              const SizedBox(height: 24),
                                              _buildChartSection("Complaints", Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Expanded(child: _buildComplaintsDonutChart()),
                                                  const SizedBox(height: 24), // Added healthy spacing below the pie chart on desktop to completely push the container down
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                                                    child: Text("Matched: ${_complaintSourceData['Residents']?.toInt()} Residents, ${_complaintSourceData['Drivers']?.toInt()} Drivers",
                                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                                  ),
                                                ],
                                              ), legend: [
                                                _buildLegendItem("Pending", (_complaintStatusData['Pending'] ?? 0).toInt(), Colors.red),
                                                _buildLegendItem("In Progress", (_complaintStatusData['In Progress'] ?? 0).toInt(), Colors.blue),
                                                _buildLegendItem("Resolved", (_complaintStatusData['Resolved'] ?? 0).toInt(), Colors.green),
                                              ], onView: () => widget.onNavigate?.call(3)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 24), // Reduced from 120 to 24 to keep content tight and clean near the bottom
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _refreshRotationController,
                builder: (context, child) {
                  // Logic to show spinner: 
                  // 1. If currently performing a manual pull (_manualPullDepth > 0)
                  // 2. If currently performing a refresh (_showRefreshSpinner)
                  bool shouldShow = _showRefreshSpinner || _manualPullDepth > 0;
                  
                  if (!shouldShow) {
                    return const SizedBox.shrink();
                  }

                  // If refreshing, stick at 80. 
                  // If just pulling, follow the manual depth up to 80.
                  final double targetTop = (_isRefreshing && _showRefreshSpinner)
                      ? 80.0 
                      : (-40 + _manualPullDepth).clamp(-40.0, 80.0);
                  
                  final double opacity = (_isRefreshing && _showRefreshSpinner)
                      ? 1.0 
                      : (_manualPullDepth / 60).clamp(0.0, 1.0);

                  return AnimatedPositioned(
                    duration: Duration(milliseconds: _isRefreshing ? 200 : 400),
                    curve: Curves.easeOutCubic,
                    top: targetTop,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Transform.rotate(
                            // Interactive rotation: rotates as you pull (clockwise)
                            angle: (_isRefreshing && _showRefreshSpinner)
                                ? 0 
                                : (_manualPullDepth / 80) * 2 * math.pi,
                            child: RotationTransition(
                              turns: _refreshRotationController,
                              child: const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF00796B),
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isMobile) {
    if (!isMobile) {
      String dateLabel = _isDateRange
          ? "${DateFormat('MMM dd').format(_selectedDateRange.start)} - ${DateFormat('MMM dd').format(_selectedDateRange.end)}"
          : DateFormat('MMM dd, yyyy').format(_selectedDateRange.start);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            if (_showHeaderShadow)
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.analytics_rounded, color: Color(0xFF00897B), size: 28),
            ),
            const SizedBox(width: 20),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Analytics & Reports",
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: -0.5)),
                Text("Comprehensive system performance overview",
                    style: TextStyle(
                        color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
            const Spacer(),
            _buildAreaDropdown(),
            const SizedBox(width: 32),
            _filterChip(Icons.calendar_today_rounded, dateLabel, onTap: () => _showDateRangePicker(context)),
            const SizedBox(width: 48),
            ElevatedButton.icon(
              onPressed: () => _showExportDialog(context),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text("EXPORT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00796B), // Balanced deep teal matching the app system colors
                foregroundColor: Colors.white,
                elevation: 4, // Added shadow depth elevation
                shadowColor: const Color(0xFF00796B).withOpacity(0.4), // Tailored shadow tint color
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // Better rounded edges structure
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), // Enhanced padding layout
              ),
            ),
          ],
        ),
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    // Adaptive font sizes
    final double titleFontSize = (screenWidth * 0.055).clamp(18.0, 22.0);
    final double subtitleFontSize = (screenWidth * 0.03).clamp(10.0, 12.0);
    final double iconContainerSize = (screenWidth * 0.12).clamp(40.0, 48.0);
    final double iconSize = (screenWidth * 0.06).clamp(20.0, 24.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: const Color(0xFFEEEEEE), width: _showHeaderShadow ? 0 : 1)),
        boxShadow: [
          if (_showHeaderShadow)
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              if (!widget.isEmbedded || widget.onBack != null) ...[
                _buildCircularBackButton(),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Analytics", style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A), letterSpacing: -0.5)),
                    Text("System performance overview", style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF757575), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showExportDialog(context),
                child: Container(
                  width: iconContainerSize,
                  height: iconContainerSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00796B), // Changed to solid deep teal brand color matching modern standard
                    borderRadius: BorderRadius.circular(16), // Rounded smoothly matching web button
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00796B).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.download_rounded, color: Colors.white, size: iconSize), // White icon contrasting against deep teal
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircularBackButton() {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    return GestureDetector(
      onTap: () {
        if (isMobile) {
          Scaffold.of(context).openDrawer();
        } else if (widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.pop(context);
        }
      },
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(
          isMobile ? Icons.menu_rounded : Icons.arrow_back_ios_new_rounded,
          color: const Color(0xFF1A1A1A),
          size: isMobile ? 22 : 18,
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    String dateLabel = _isDateRange
        ? "${DateFormat('MMM dd').format(_selectedDateRange.start)} - ${DateFormat('MMM dd').format(_selectedDateRange.end)}"
        : DateFormat('MMM dd, yyyy').format(_selectedDateRange.start);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          _buildAreaDropdown(),
          const SizedBox(width: 24),
          _filterChip(Icons.calendar_today_rounded, dateLabel, onTap: () => _showDateRangePicker(context)),
        ],
      ),
    );
  }

  Widget _buildAreaDropdown() {
    return PopupMenuButton<String>(
      onSelected: (area) {
        setState(() => _selectedArea = area);
        refreshAllData();
      },
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      color: Colors.white,
      itemBuilder: (context) => ["All Areas", ..._purokNames].map((area) {
        bool isSelected = area == _selectedArea;
        return PopupMenuItem<String>(
          value: area,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: isSelected ? const Color(0xFF00897B) : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              Text(
                area,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected ? const Color(0xFF00897B) : const Color(0xFF2C3E50),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on_rounded, size: 18, color: Color(0xFF00897B)),
          const SizedBox(width: 8),
          Text(_selectedArea, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1A1A1A))),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down_rounded, size: 24, color: Colors.grey),
        ],
      ),
    );
  }

  Future<void> _showDateRangePicker(BuildContext context) async {
    DateTimeRange? picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _CuteDateRangePicker(initialRange: _selectedDateRange),
        ),
      ),
    );

    if (picked != null) {
      setState(() { _selectedDateRange = picked!; _isDateRange = true; });
    } else {
      // CLEAR button was pressed (returns null)
      setState(() {
        _selectedDateRange = DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 30)),
          end: DateTime.now(),
        );
        _isDateRange = true;
      });
    }
    refreshAllData();
  }

  Widget _filterChip(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF00897B)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1A1A1A))),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down_rounded, size: 24, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, {bool isPositive = true, String? trend}) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 20 : 28),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Stack(
        children: [
          // Background "Glass" Highlight
          Positioned(
            top: -15,
            right: -15,
            child: Container(
              width: isMobile ? 60 : 80,
              height: isMobile ? 60 : 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Large Faded Background Icon
          Positioned(
            bottom: -10,
            right: -5,
            child: Icon(
              icon,
              size: isMobile ? 40 : 60,
              color: color.withOpacity(0.05),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.all(isMobile ? 6 : 10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: isMobile ? 16 : 20),
                    ),
                    if (trend != null && trend != "N/A")
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: (title == "Coverage" ? const Color(0xFF2196F3) : (isPositive ? Colors.green : Colors.red)).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: (title == "Coverage" ? const Color(0xFF2196F3) : (isPositive ? Colors.green : Colors.red)).withOpacity(0.2)),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 8, color: title == "Coverage" ? const Color(0xFF2196F3) : (isPositive ? Colors.green : Colors.red)),
                                const SizedBox(width: 2),
                                Text(trend, style: TextStyle(color: title == "Coverage" ? const Color(0xFF2196F3) : (isPositive ? Colors.green : Colors.red), fontSize: 8, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title, 
                    style: TextStyle(
                      fontSize: isMobile ? 10 : 12, 
                      color: Colors.grey.shade600, 
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2
                    )
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value, 
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 24, 
                      fontWeight: FontWeight.w900, 
                      color: const Color(0xFF1A1A1A),
                      letterSpacing: -0.5
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection(String title, Widget chart, {List<Widget>? legend, VoidCallback? onView}) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A))),
              if (onView != null)
                TextButton(
                  onPressed: onView,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFE0F2F1),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("VIEW", style: TextStyle(color: Color(0xFF00897B), fontWeight: FontWeight.w900, fontSize: 12)),
                ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 32),
          // Increased desktop chart container height slightly to 240 to give the larger chart and its badge container room to breathe without overlapping
          SizedBox(height: isMobile ? 230 : 240, child: chart), 
          if (legend != null) ...[
            SizedBox(height: isMobile ? 16 : 24),
            SizedBox(
              width: double.infinity,
              child: Wrap(spacing: isMobile ? 16 : 12, runSpacing: 8, alignment: WrapAlignment.center, children: legend),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, int value, Color color) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isMobile ? 14 : 10, 
          height: isMobile ? 14 : 10, 
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(isMobile ? 4 : 3))
        ),
        const SizedBox(width: 10),
        Text("$label ($value)", style: TextStyle(fontSize: isMobile ? 14 : 12, fontWeight: FontWeight.w800, color: const Color(0xFF2C3E50))),
      ],
    );
  }

  Widget _buildPurokChartSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Purok Coverage (%)", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A))),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Color(0xFFE3F2FD), shape: BoxShape.circle),
                child: const Icon(Icons.visibility_rounded, color: Color(0xFF2196F3), size: 18),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(height: 350, child: _buildPurokBarChart()),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => _showFullDetailsModal(context),
              style: TextButton.styleFrom(
                overlayColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
              ),
              child: const Text("VIEW FULL DETAILS", style: TextStyle(color: Color(0xFF2196F3), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllEtasModal(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    bool isModalLoading = true;

    Widget modalContent(StateSetter setModalState) {
      if (isModalLoading) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setModalState(() => isModalLoading = false);
        });
      }

      return Container(
        padding: EdgeInsets.fromLTRB(28, isMobile ? 12 : 24, 28, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: isMobile ? const BorderRadius.vertical(top: Radius.circular(32)) : BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) 
              Center(
                child: Container(
                  width: 40, 
                  height: 4, 
                  margin: const EdgeInsets.only(bottom: 20), 
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))
                )
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Arrival ETAs", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                      SizedBox(height: 4),
                      Text("Live garbage collection arrival estimates.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.black54, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 20),
            if (isModalLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.tealText),
                      SizedBox(height: 16),
                      Text(
                        "Loading arrival ETAs...",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    children: _etaEstimates.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade100, width: 1.5),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
                            ],
                          ),
                          child: Column(
                            children: [
                              _predictionDetailRow("${e.key}:", e.value, themeColor: const Color(0xFF43A047)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65), // Balanced height
            child: modalContent(setModalState),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550), // Balanced height
            child: StatefulBuilder(
              builder: (context, setModalState) => modalContent(setModalState),
            ),
          ),
        ),
      );
    }
  }

  void _showFullDetailsModal(BuildContext context) {
    if (MediaQuery.of(context).size.width < 900) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _FullDetailsModal(
          frequencyData: _purokFrequencyData, 
          complaintData: _purokComplaintData,
          isMobile: true,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: _FullDetailsModal(
              frequencyData: _purokFrequencyData, 
              complaintData: _purokComplaintData,
              isMobile: false,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildInsightsSection(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00897B), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Predictions & Insights", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF1A1A1A))),
                  Text("AI-generated volume forecasts and arrival estimates", style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (_isAiLoading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00BFA5))),
          ],
        ),
        const SizedBox(height: 24),
        _buildPredictionCard("Waste Volume Prediction", [
          _predictionDetailRow("Tomorrow:", "${_tomorrowWaste.toInt()} kg", themeColor: const Color(0xFF1E88E5)),
          const Divider(height: 12),
          _predictionDetailRow("This Week:", "${_weeklyWaste.toInt()} kg", themeColor: const Color(0xFF1E88E5)),
          const Divider(height: 12),
          _predictionDetailRow("Truck Capacity:", "5000 kg", themeColor: const Color(0xFF1E88E5)),
        ], titleColor: const Color(0xFF1E88E5)),
        const SizedBox(height: 16),
        _buildPredictionCard("Estimated Arrival Times", [
          ..._etaEstimates.entries.take(3).map((e) {
            final int index = _etaEstimates.keys.toList().indexOf(e.key);
            return Column(
              children: [
                _predictionDetailRow("${e.key}:", e.value, themeColor: const Color(0xFF43A047)),
                if (index < 2) const Divider(height: 12),
              ],
            );
          }),
          if (_etaEstimates.length > 3)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton(
                  onPressed: () => _showAllEtasModal(context),
                  style: TextButton.styleFrom(
                    overlayColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                  ),
                  child: const Text("VIEW ALL", style: TextStyle(color: Color(0xFF43A047), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.1)),
                ),
              ),
            ),
        ], titleColor: const Color(0xFF43A047)),
        const SizedBox(height: 16),
        _buildPredictionCard("Recommendations", [
          Text(_recommendations, style: const TextStyle(fontSize: 13, color: Color(0xFF6A1B9A), fontWeight: FontWeight.w600, height: 1.5)),
          const SizedBox(height: 12),
          const Text("• Note: Waste volume estimation based on Purok area.", style: TextStyle(fontSize: 11, color: Color(0xFF6A1B9A), fontStyle: FontStyle.italic)),
        ], titleColor: const Color(0xFF6A1B9A)),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.analytics_rounded, color: Color(0xFF00897B), size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("System Performance Metrics", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A))),
                Text("Technical overview of collection speed and efficiency", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildEfficiencyCard(),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(24), 
            boxShadow: AppTheme.balancedPulidongShadow,
            border: Border.all(color: Colors.green.withAlpha(20))
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Icon(Icons.insights_rounded, size: 18, color: Color(0xFF00897B)), SizedBox(width: 10), Text("Operational Context", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF00897B)))]),
              const SizedBox(height: 12),
              _isAiLoading ? _buildShimmer(14, 0.8) : Text(_geminiSummary ?? "Analyzing current collection patterns...", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50), height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionCard(String title, List<Widget> children, {required Color titleColor}) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(24), 
        boxShadow: AppTheme.balancedPulidongShadow, 
        border: Border.all(color: titleColor.withAlpha(15))
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: titleColor)), const SizedBox(height: 20), ...children]),
    );
  }

  Widget _predictionDetailRow(String label, String value, {required Color themeColor}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700, fontSize: 14)), Text(value, style: TextStyle(color: themeColor, fontWeight: FontWeight.w900, fontSize: 14))]));
  }

  Widget _buildShimmer(double height, double widthFactor) {
    return Container(height: height, width: double.infinity, decoration: BoxDecoration(color: Colors.grey.withAlpha(30), borderRadius: BorderRadius.circular(4)));
  }

  Widget _buildEfficiencyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.grey.shade100)
      ),
      child: Column(children: [
        _insightRow("Avg Collection Time", "${_avgCollectionTime.toStringAsFixed(1)}h"),
        const Divider(height: 16),
        _insightRow("Stops per Route", "$_stopsPerRoute"),
        const Divider(height: 16),
        _insightRow("Distance Covered", "${_distanceCovered.toStringAsFixed(1)}km"),
        const Divider(height: 16),
        _insightRow("Prediction Accuracy", "${_predictionAccuracy.toStringAsFixed(1)}%", isSuccess: _predictionAccuracy > 90),
      ]),
    );
  }

  Widget _insightRow(String label, String value, {bool isSuccess = false}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50))), Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: isSuccess ? Colors.green : const Color(0xFF2C3E50)))]));
  }

  Widget _buildTruckDonutChart() {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final double active = _truckStatusData['Active'] ?? 0;
    final double full = _truckStatusData['Full'] ?? 0;
    final double idle = _truckStatusData['Idle'] ?? 0;
    final double total = active + full + idle;
    if (total == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline_rounded, color: Colors.grey.shade300, size: 40),
            const SizedBox(height: 8),
            const Text("No data matching\nselected filters",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    // When on desktop/web (isMobile is false), we increase the chart size to fill more space inside the card.
    final double radius = isMobile ? 40 : 40;
    final double centerSpaceRadius = isMobile ? 65 : 65;

    return PieChart(PieChartData(sections: [
      if (active > 0) PieChartSectionData(value: active, color: Colors.green, radius: radius, title: '${active.toInt()}', titleStyle: TextStyle(fontSize: isMobile ? 14 : 14, fontWeight: FontWeight.w900, color: Colors.white), titlePositionPercentageOffset: 0.5),
      if (full > 0) PieChartSectionData(value: full, color: Colors.amber, radius: radius, title: '${full.toInt()}', titleStyle: TextStyle(fontSize: isMobile ? 14 : 14, fontWeight: FontWeight.w900, color: Colors.white), titlePositionPercentageOffset: 0.5),
      if (idle > 0) PieChartSectionData(value: idle, color: Colors.grey.shade300, radius: radius, title: '${idle.toInt()}', titleStyle: TextStyle(fontSize: isMobile ? 14 : 14, fontWeight: FontWeight.w900, color: Colors.black54), titlePositionPercentageOffset: 0.5),
    ], centerSpaceRadius: centerSpaceRadius, sectionsSpace: 2));
  }

  Widget _buildComplaintsDonutChart() {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final double pending = _complaintStatusData['Pending'] ?? 0;
    final double inProgress = _complaintStatusData['In Progress'] ?? 0;
    final double resolved = _complaintStatusData['Resolved'] ?? 0;

    final double total = pending + inProgress + resolved;
    if (total == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline_rounded, color: Colors.grey.shade300, size: 40),
            const SizedBox(height: 8),
            const Text("No data matching\nselected filters",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    // When on desktop/web (isMobile is false), we increase the chart size to fill more space inside the card.
    final double radius = isMobile ? 40 : 40;
    final double centerSpaceRadius = isMobile ? 65 : 65;

    return PieChart(PieChartData(sections: [
      if (pending > 0)
        PieChartSectionData(
          value: pending, color: Colors.red, radius: radius,
          title: '${pending.toInt()}', titleStyle: TextStyle(fontSize: isMobile ? 14 : 14, fontWeight: FontWeight.w900, color: Colors.white),
          titlePositionPercentageOffset: 0.5,
        ),
      if (inProgress > 0)
        PieChartSectionData(
          value: inProgress, color: Colors.blue, radius: radius,
          title: '${inProgress.toInt()}', titleStyle: TextStyle(fontSize: isMobile ? 14 : 14, fontWeight: FontWeight.w900, color: Colors.white),
          titlePositionPercentageOffset: 0.5,
        ),
      if (resolved > 0)
        PieChartSectionData(
          value: resolved, color: Colors.green, radius: radius,
          title: '${resolved.toInt()}', titleStyle: TextStyle(fontSize: isMobile ? 14 : 14, fontWeight: FontWeight.w900, color: Colors.white),
          titlePositionPercentageOffset: 0.5,
        ),
    ], centerSpaceRadius: centerSpaceRadius, sectionsSpace: 2));
  }

  Widget _buildPurokBarChart() {
    final areas = ["P1", "P2", "P3", "P4", "Riles", "Sentro", "ISIDRO", "PARA", "RIV", "KAL", "HOME", "TANCO"];
    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround, maxY: 100,
      titlesData: FlTitlesData(show: true, bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 12), child: Text(v.toInt() < areas.length ? areas[v.toInt()] : "", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800))))), leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: const TextStyle(fontSize: 10))))),
      gridData: const FlGridData(show: true, drawVerticalLine: false), borderData: FlBorderData(show: false),
      barGroups: List.generate(areas.length, (index) {
        final count = _purokFrequencyData[_purokNames[index]] ?? 0;
        return BarChartGroupData(x: index, barRods: [BarChartRodData(toY: count.toDouble(), color: const Color(0xFF2196F3), width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))]);
      }),
    ));
  }

  void _showAreaSelection(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;

    Widget content(BuildContext context) => Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: isMobile ? const BorderRadius.vertical(top: Radius.circular(32)) : BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)))),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Select Area Filter", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00897B))),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text("Select a specific Purok to filter the analytics data.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
          const Divider(height: 32),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView(
              shrinkWrap: true,
              children: ["All Areas", ..._purokNames].map((area) {
                bool isSelected = area == _selectedArea;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedArea = area);
                      refreshAllData();
                      Navigator.pop(context);
                      
                      // Show success notification
                      CustomNotification.showTopNotification(context, "Filtered by $area", false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE0F2F1) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? const Color(0xFF00BFA5) : Colors.grey.shade200, width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(area, style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, color: isSelected ? const Color(0xFF00897B) : const Color(0xFF2C3E50))),
                          if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF00BFA5), size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList()
            )
          ),
          const SizedBox(height: 8),
        ]
      ),
    );

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => content(context),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(width: 400, child: content(context)),
        ),
      );
    }
  }

  void _showExportDialog(BuildContext context) {
    String selectedCategory = "Full System Report";
    String selectedFormat = "PDF Document (.pdf)";

    Widget content(BuildContext context, StateSetter setDialogState) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Export Reports", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00897B))),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text("Generate and download comprehensive system performance reports.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
          const Divider(height: 32),
          _exportDropdown("Report Category", ["Full System Report", "Truck Performance", "Area Coverage"], selectedCategory, (val) {
            if (val != null) setDialogState(() => selectedCategory = val);
          }),
          const SizedBox(height: 16),
          _exportDropdown("File Format", ["PDF Document (.pdf)", "Excel Spreadsheet (.xlsx)"], selectedFormat, (val) {
            if (val != null) setDialogState(() => selectedFormat = val);
          }),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _exportReport(selectedCategory, selectedFormat);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text("DOWNLOAD REPORT", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      );
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: StatefulBuilder(
              builder: (context, setDialogState) => content(context, setDialogState),
            ),
          ),
        ),
      ),
    );
  }

  Widget _exportDropdown(String hint, List<String> items, String currentVal, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16), 
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: Colors.grey.shade200)
      ), 
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: Colors.white,
          value: currentVal, 
          hint: Text(hint), 
          isExpanded: true, 
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(), 
          onChanged: onChanged
        )
      )
    );
  }
}

class _CuteDateRangePicker extends StatefulWidget {
  final DateTimeRange initialRange;
  const _CuteDateRangePicker({required this.initialRange});
  @override State<_CuteDateRangePicker> createState() => _CuteDateRangePickerState();
}

class _CuteDateRangePickerState extends State<_CuteDateRangePicker> {
  late DateTime _currentMonth; 
  DateTime? _rangeStart; 
  DateTime? _rangeEnd;
  bool _isYearPickerVisible = false;

  @override 
  void initState() { 
    super.initState(); 
    _currentMonth = DateTime(widget.initialRange.start.year, widget.initialRange.start.month); 
    _rangeStart = widget.initialRange.start; 
    _rangeEnd = widget.initialRange.end; 
  }

  @override 
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select Date", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                  const SizedBox(height: 4),
                  const Text("Pick a date range to filter analytics.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(height: 48),
          
          if (!_isYearPickerVisible) ...[
            // CALENDAR VIEW
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                onTap: () => setState(() => _isYearPickerVisible = true),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    children: [
                      Text(DateFormat('MMMM yyyy').format(_currentMonth), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF455A64))),
                      const Icon(Icons.arrow_drop_down_rounded, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1))),
                  IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1))),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text("S", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Text("M", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Text("T", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Text("W", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Text("T", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Text("F", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Text("S", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            _buildDaysGrid(),
          ] else ...[
            // YEAR SELECTION VIEW
            GestureDetector(
              onTap: () => setState(() => _isYearPickerVisible = false),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Text(DateFormat('MMMM yyyy').format(_currentMonth), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF455A64))),
                    const Icon(Icons.arrow_drop_up_rounded, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 24),
            _buildYearGrid(),
            const SizedBox(height: 24),
            const Divider(height: 1),
          ],
          
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: const BorderSide(color: Colors.grey),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("CLEAR", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, DateTimeRange(start: _rangeStart ?? DateTime.now(), end: _rangeEnd ?? _rangeStart ?? DateTime.now())),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text("APPLY FILTER", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                ),
              ),
            ],
          ),
        ]
      ),
    );
  }

  Widget _buildYearGrid() {
    final List<int> years = List.generate(12, (index) => 2020 + index); 
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 2.2,
      ),
      itemCount: years.length,
      itemBuilder: (context, index) {
        final int year = years[index];
        final bool isSelected = year == _currentMonth.year;
        return InkWell(
          onTap: () {
            setState(() {
              _currentMonth = DateTime(year, _currentMonth.month);
              _isYearPickerVisible = false;
            });
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF00897B) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              year.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF455A64),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDaysGrid() {
    final int daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final int firstDayWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday % 7;
    return GridView.builder(
      shrinkWrap: true, 
      physics: const NeverScrollableScrollPhysics(), 
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7), 
      itemCount: daysInMonth + firstDayWeekday, 
      itemBuilder: (context, index) {
        if (index < firstDayWeekday) return const SizedBox.shrink();
        final int day = index - firstDayWeekday + 1; 
        final DateTime date = DateTime(_currentMonth.year, _currentMonth.month, day);
        
        bool isRangeStart = _rangeStart != null && date.year == _rangeStart!.year && date.month == _rangeStart!.month && date.day == _rangeStart!.day;
        bool isRangeEnd = _rangeEnd != null && date.year == _rangeEnd!.year && date.month == _rangeEnd!.month && date.day == _rangeEnd!.day;
        bool isInRange = _rangeStart != null && _rangeEnd != null && date.isAfter(_rangeStart!) && date.isBefore(_rangeEnd!);
        bool isSelected = isRangeStart || isRangeEnd;

        return InkWell(
          onTap: () {
            setState(() {
              if (_rangeStart == null || (_rangeStart != null && _rangeEnd != null)) {
                _rangeStart = date;
                _rangeEnd = null;
              } else if (date.isBefore(_rangeStart!)) {
                _rangeStart = date;
              } else {
                _rangeEnd = date;
              }
            });
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF00897B) : (isInRange ? const Color(0xFFE0F2F1) : null), 
              shape: BoxShape.circle,
              border: (date.day == DateTime.now().day && date.month == DateTime.now().month && date.year == DateTime.now().year)
                ? Border.all(color: const Color(0xFF00897B), width: 1)
                : null,
            ),
            child: Text(
              day.toString(),
              style: TextStyle(
                color: isSelected ? Colors.white : (isInRange ? const Color(0xFF00897B) : Colors.black),
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal,
              ),
            ),
          ),
        );
    });
  }
}

class _FullDetailsModal extends StatefulWidget {
  final Map<String, int> frequencyData; 
  final Map<String, int> complaintData;
  final bool isMobile;
  const _FullDetailsModal({required this.frequencyData, required this.complaintData, this.isMobile = false});
  @override State<_FullDetailsModal> createState() => _FullDetailsModalState();
}

class _FullDetailsModalState extends State<_FullDetailsModal> {
  String? _geminiSummaryLocal; bool _isLoadingLocal = true;
  @override
  void initState() {
    super.initState();
    _generateGeminiSummary();
  }
  Future<void> _generateGeminiSummary() async {
    const apiKey = "PASTE_YOUR_GEMINI_API_KEY_HERE";
    final model = GenerativeModel(model: 'gemini-1.5-flash-latest', apiKey: apiKey);

    StringBuffer data = StringBuffer("Purok Coverage Data:\n");
    widget.frequencyData.forEach((k, v) => data.writeln("- $k: $v% coverage"));
    data.writeln("\nComplaints per Purok:\n");
    widget.complaintData.forEach((k, v) => data.writeln("- $k: $v issues"));

    try {
      // Add a minimum 800ms artificial delay to match the smooth loading feel of the other modals
      await Future.delayed(const Duration(milliseconds: 800));
      
      final content = [Content.text("You are the Balintawak Garbage System AI. Summarize this operational data for the manager and provide a quick conclusion: $data")];
      final response = await model.generateContent(content);
      if (mounted) {
        setState(() {
          _geminiSummaryLocal = response.text;
          _isLoadingLocal = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLocal = false;
          _geminiSummaryLocal = "AI insights temporarily unavailable.";
        });
      }
    }
  }
  @override Widget build(BuildContext context) {
    bool isModalLoading = _geminiSummaryLocal == null && _isLoadingLocal;

    return Container(
      padding: EdgeInsets.fromLTRB(28, widget.isMobile ? 12 : 24, 28, 24), 
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: widget.isMobile ? const BorderRadius.vertical(top: Radius.circular(32)) : BorderRadius.circular(32)
      ), 
      constraints: BoxConstraints(
        // Dynamic size constraints: Shorter container height (250) on loading, grows up to maximum on success
        maxHeight: isModalLoading 
            ? 250.0 
            : (widget.isMobile ? MediaQuery.of(context).size.height * 0.75 : 550.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isMobile) 
            Center(
              child: Container(
                width: 40, 
                height: 4, 
                margin: const EdgeInsets.only(bottom: 20), 
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))
              )
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: widget.isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Operational Insights", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                    SizedBox(height: 4),
                    Text("AI-generated breakdown of system data.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              // Show the X close button ONLY on web/desktop view, hide on mobile view
              if (!widget.isMobile)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.black54, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 20),
          if (isModalLoading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.tealText),
                    const SizedBox(height: 16),
                    const Text(
                      "Analyzing operational data...",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEEF2F6)),
                  ),
                  child: Text(
                    _geminiSummaryLocal ?? "AI insights temporarily unavailable.", 
                    style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF2C3E50), fontWeight: FontWeight.w500)
                  ),
                ),
              ),
            ),
        ]
      )
    );
  }
}
