import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../api/api_service.dart';
import '../api/api_client.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/custom_notification.dart';
import '../widgets/custom_snackbar.dart';

class DataManagementScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const DataManagementScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> with TickerProviderStateMixin {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  bool _showHeaderShadow = true;
  
  List<dynamic> _backupHistory = [];
  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isExporting = false;
  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;
  DateTime? _dateFilter;

  @override
  void initState() {
    super.initState();
    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _fetchBackupHistory();
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
    super.dispose();
  }

  Future<void> _refreshAllStats({bool manual = false}) async {
    if (_isRefreshing) return;
    
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _showRefreshSpinner = manual;
        _manualPullDepth = manual ? 80.0 : 0.0;
      });
    }
    _refreshRotationController.repeat();

    await Future.wait([
      _fetchBackupHistory(silent: true),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);

    if (manual) {
      await Future.delayed(const Duration(seconds: 2));
    }

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
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
                        "Data records synchronized",
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

  bool _isOperationSuccessful(dynamic data) {
    if (data == null) return false;
    if (data is! Map) return false;
    final val = data['success'];
    return (val == true || val == 1 || val.toString().toLowerCase() == "true" || val.toString() == "1");
  }

  Future<void> _fetchBackupHistory({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isLoading = true);
    try {
      final response = await _apiService.getBackupHistory();
      if (_isOperationSuccessful(response.data)) {
        setState(() {
          _backupHistory = response.data['backups'] ?? [];
          _isLoading = false;
        });
      } else {
        throw response.data['message'] ?? "Failed to load history";
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint("History Fetch Error: $e");
      }
    }
  }

  Future<void> _triggerBackup() async {
    bool confirmed = await _showConfirmDialog(
      title: "Trigger System Backup?",
      message: "This will create a complete snapshot of the system database. This process may take a few moments.",
      confirmLabel: "YES, BACK UP",
    );
    if (!confirmed) return;

    setState(() => _isBackingUp = true);
    try {
      final response = await _apiService.triggerBackup();
      if (_isOperationSuccessful(response.data)) {
        CustomNotification.showTopNotification(context, "Full system snapshot created successfully.", false);
        _fetchBackupHistory();
      } else {
        throw response.data['message'] ?? "Backup generation failed";
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.showTopNotification(context, "Backup Error: $e", true);
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _downloadFile(String? url) async {
    if (url == null || url.isEmpty) return;
    
    // Logic: If URL is relative (doesn't start with http), prepend the base URL
    String fullUrl = url;
    if (!url.startsWith('http')) {
      fullUrl = "${ApiClient.baseUrl}$url";
    }

    final Uri uri = Uri.parse(fullUrl);
    debugPrint("[DOWNLOAD] Triggering download for: $fullUrl");

    try {
      // Use LaunchMode.externalApplication for direct file downloads to trigger browser/download manager
      // We skip canLaunchUrl check because it can be unreliable on some mobile OS versions for direct file links
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      
      if (mounted) {
        CustomNotification.showTopNotification(context, "Download request sent to system.", false);
      }
    } catch (e) {
      debugPrint("[DOWNLOAD] Error: $e");
      if (mounted) {
        CustomNotification.showTopNotification(context, "Download Error: $e", true);
      }
    }
  }

  Future<void> _exportFullSystem() async {
    bool confirmed = await _showConfirmDialog(
      title: "Export System Data?",
      message: "This will bundle all current database records into an export file. Continue?",
    );
    if (!confirmed) return;

    setState(() => _isExporting = true);
    try {
      final response = await _apiService.exportData();
      final dynamic data = response.data;
      
      if (_isOperationSuccessful(data)) {
        final String? url = data['url'];
        if (url != null) {
          await _downloadFile(url);
          CustomNotification.showTopNotification(context, data['message'] ?? "Snapshots bundled and downloaded successfully.", false);
        }
      } else {
        throw data['message'] ?? "Export failed on server";
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.showTopNotification(context, "Export Error: $e", true);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<bool> _showConfirmDialog({required String title, required String message, String confirmLabel = "YES, PROCEED"}) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00796B), // Changed from blue to system deep teal green
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Filter history based on selected date
    final List<dynamic> filteredHistory = _backupHistory.where((backup) {
      if (_dateFilter == null) return true;
      final String? dateStr = backup['date']?.toString();
      if (dateStr != null && dateStr.length >= 10) {
        try {
          final DateTime backupDate = DateTime.parse(dateStr.substring(0, 10));
          return backupDate.year == _dateFilter!.year && 
                 backupDate.month == _dateFilter!.month && 
                 backupDate.day == _dateFilter!.day;
        } catch (_) {}
      }
      return false;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 900;
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA), // Matches Admin Home Dashboard
          body: SafeArea(
            child: Stack(
              children: [
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerMove: (event) {
                    bool atTop = _scrollController.hasClients && _scrollController.offset <= 0;
                    if (!_isRefreshing && (atTop || _manualPullDepth > 0)) {
                      if (event.delta.dy > 0 || _manualPullDepth > 0) {
                        setState(() {
                          _manualPullDepth += event.delta.dy * 0.5;
                          if (_manualPullDepth < 0) _manualPullDepth = 0;
                          if (_manualPullDepth > 120) _manualPullDepth = 120;
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
                      
                      // FIXED TOP SECTION
                      Padding(
                        padding: EdgeInsets.fromLTRB(isMobile ? 16 : 48, isMobile ? 16 : 24, isMobile ? 16 : 48, 0),
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 1000),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildTopActionsSection(isMobile),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Icon(Icons.history_rounded, color: Color(0xFF00796B), size: 24),
                                    const SizedBox(width: 12),
                                    const Text("Backup History", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                                    const Spacer(),
                                    Text("${filteredHistory.length} Snapshots", style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.grey, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // UNIFIED TABLE CONTAINER (Header + List)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(isMobile ? 16 : 48, 0, isMobile ? 16 : 48, isMobile ? 2 : 40),
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _scrollController,
                              builder: (context, child) {
                                final double offset = _scrollController.hasClients ? _scrollController.offset : 0;
                                return Transform.translate(
                                  offset: Offset(0, offset < 0 ? offset : 0),
                                  child: LayoutBuilder(
                                    builder: (context, boxConstraints) {
                                      return Container(
                                        constraints: const BoxConstraints(maxWidth: 1000),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(24),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.12),
                                              blurRadius: 25,
                                              offset: const Offset(0, 12),
                                              spreadRadius: 2,
                                            )
                                          ],
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          physics: const BouncingScrollPhysics(),
                                          child: SizedBox(
                                            width: isMobile ? 800 : 1000, 
                                            height: boxConstraints.maxHeight, // FIX: Provide explicit height from LayoutBuilder
                                            child: Column(
                                              children: [
                                                _buildTableHeader(), 
                                                Expanded(
                                                  child: _isLoading 
                                                    ? Center(
                                                        child: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const CircularProgressIndicator(color: Color(0xFF00796B)),
                                                            const SizedBox(height: 16),
                                                            Text(
                                                              "Loading database snapshots...",
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                color: Colors.grey.shade600,
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                    : (filteredHistory.isEmpty 
                                                      ? _buildEmptyState()
                                                      : ListView.builder(
                                                          controller: _scrollController,
                                                          physics: (_manualPullDepth > 0 || _isRefreshing) 
                                                              ? const NeverScrollableScrollPhysics() 
                                                              : const ClampingScrollPhysics(),
                                                          padding: EdgeInsets.zero,
                                                          itemCount: filteredHistory.length,
                                                          itemBuilder: (context, index) {
                                                            return _buildBackupItem(filteredHistory[index]);
                                                          },
                                                        )),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
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
                    bool shouldShow = _showRefreshSpinner || _manualPullDepth > 0;
                    if (!shouldShow) return const SizedBox.shrink();

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
                                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3)),
                              ],
                            ),
                            child: Transform.rotate(
                              angle: (_isRefreshing && _showRefreshSpinner)
                                  ? 0
                                  : (_manualPullDepth / 80) * 2 * math.pi,
                              child: RotationTransition(
                                turns: _refreshRotationController,
                                child: const Icon(Icons.refresh_rounded, color: Color(0xFF00796B), size: 24),
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
          ),
        );
      }
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

  Widget _buildHeader(bool isMobile) {
    final double screenWidth = MediaQuery.of(context).size.width;
    if (!isMobile) {
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
              child: const Icon(Icons.storage_rounded, color: Color(0xFF00796B), size: 28),
            ),
            const SizedBox(width: 20),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Database Center",
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: -0.5)),
                Text("Secure system snapshots and maintenance tools",
                    style: TextStyle(
                        color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
            const Spacer(),
            _buildAutoBackupToggle(),
          ],
        ),
      );
    }

    final double titleFontSize = (screenWidth * 0.055).clamp(18.0, 22.0);
    final double subtitleFontSize = (screenWidth * 0.03).clamp(10.0, 12.0);
    final double iconContainerSize = (screenWidth * 0.12).clamp(40.0, 48.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
      child: Row(
        children: [
          _buildCircularBackButton(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Database Center", 
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A), letterSpacing: -0.5)),
                Text("Manage system backups", 
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF757575), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          _buildAutoBackupToggle(compact: true),
        ],
      ),
    );
  }

  Widget _buildAutoBackupToggle({bool compact = false}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 130 : 250),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text("AUTO SAVE BACKUP", style: TextStyle(fontSize: compact ? 8 : 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0)),
            ),
            StreamBuilder(
              stream: _database.ref('admin_settings/auto_backup').onValue,
              builder: (context, snapshot) {
                bool autoBackup = false;
                if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                  autoBackup = snapshot.data!.snapshot.value == true;
                }
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: autoBackup ? const Color(0xFFE0F2F1).withOpacity(0.5) : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: autoBackup ? const Color(0xFF00897B).withOpacity(0.3) : Colors.grey.shade200, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_mode_rounded, size: compact ? 14 : 18, color: autoBackup ? const Color(0xFF00897B) : Colors.grey),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!compact)
                            const Text("STATUS", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                          Text(autoBackup ? "ENABLED" : "DISABLED", style: TextStyle(fontSize: compact ? 10 : 12, fontWeight: FontWeight.w900, color: autoBackup ? const Color(0xFF00897B) : const Color(0xFF2C3E50))),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Transform.scale(
                        scale: compact ? 0.65 : 0.8,
                        child: Switch(
                          value: autoBackup, 
                          activeColor: const Color(0xFF00897B), 
                          onChanged: (v) {
                            _database.ref('admin_settings/auto_backup').set(v);
                            CustomNotification.showTopNotification(context, v ? "Automatic backup enabled" : "Automatic backup disabled", false);
                          }
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionsSection(bool isMobile) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionButton(
            _isBackingUp ? "BACKING UP..." : "BACKUP NOW", 
            Icons.backup_rounded, 
            Colors.blue.shade700, 
            _isBackingUp ? null : _triggerBackup, 
            isLoading: _isBackingUp
          ),
          const SizedBox(width: 16), // Increased spacing between buttons from 12 to 16
          _buildActionButton(
            _isExporting ? "EXPORTING..." : "EXPORT SYSTEM", 
            Icons.ios_share_rounded, 
            const Color(0xFF00796B), 
            _isExporting ? null : _exportFullSystem,
            isLoading: _isExporting,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback? onTap, {bool isLoading = false}) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final Color buttonColor = isLoading ? Colors.grey.shade500 : color;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: buttonColor.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: isLoading 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
            : Icon(icon, size: isMobile ? 16 : 18, color: Colors.white),
        label: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isMobile ? 11 : 13, letterSpacing: 0.5)),
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor, 
          disabledBackgroundColor: Colors.grey.shade500,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 16 : 20), 
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final double fontSize = isMobile ? 10 : 11;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text("SNAPSHOT NAME", style: TextStyle(fontWeight: FontWeight.w900, fontSize: fontSize, color: Colors.grey, letterSpacing: 1.2))),
          Expanded(
            flex: 4, 
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showDateFilterPicker(),
                child: Row(
                  children: [
                    Text(_dateFilter == null ? "DATE CREATED" : DateFormat('MMM dd, yyyy').format(_dateFilter!).toUpperCase(), 
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: fontSize, color: _dateFilter == null ? Colors.grey : const Color(0xFF00796B), letterSpacing: 1.2)),
                    const SizedBox(width: 4),
                    Icon(Icons.filter_list_rounded, size: isMobile ? 12 : 14, color: _dateFilter == null ? Colors.grey : const Color(0xFF00796B)),
                  ],
                ),
              ),
            )
          ),
          Expanded(flex: 3, child: Text("FILE SIZE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: fontSize, color: Colors.grey, letterSpacing: 1.2))),
          Expanded(flex: 3, child: Text("ACTION", style: TextStyle(fontWeight: FontWeight.w900, fontSize: fontSize, color: Colors.grey, letterSpacing: 1.2))),
        ],
      ),
    );
  }

  Future<void> _showDateFilterPicker() async {
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: _CuteDateFilterPicker(initialDate: _dateFilter ?? DateTime.now()),
        ),
      ),
    );

    if (picked != null) {
      setState(() => _dateFilter = picked);
    } else if (picked == null && _dateFilter != null) {
      // User dismissed or cleared? We need a way to clear. 
      // I'll add a Clear button in the picker.
    }
  }

  Widget _buildBackupItem(Map<String, dynamic> backup) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final String filename = backup['filename'] ?? "snapshot_db.sql";
    final String date = backup['date'] ?? "N/A";
    final String size = backup['size'] ?? "0 MB";
    final String? url = backup['url'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFF1F4F8), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.description_rounded, color: const Color(0xFF455A64), size: isMobile ? 16 : 18),
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(filename, style: TextStyle(fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A), fontSize: isMobile ? 12 : 14), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            Expanded(flex: 4, child: Text(date, style: TextStyle(fontWeight: FontWeight.w600, color: const Color(0xFF455A64), fontSize: isMobile ? 11 : 13))),
            Expanded(
              flex: 3, 
              child: Row(
                children: [
                  Icon(Icons.storage_rounded, size: isMobile ? 12 : 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(size, style: TextStyle(fontWeight: FontWeight.w700, color: const Color(0xFF455A64), fontSize: isMobile ? 11 : 13)),
                ],
              )
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      if (url != null) {
                        bool confirmed = await _showConfirmDialog(
                          title: "Download Snapshot?",
                          message: "Are you sure you want to download $filename to your device?",
                        );
                        if (confirmed) {
                          _downloadFile(url);
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF00897B),
                      backgroundColor: const Color(0xFFE0F2F1).withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      overlayColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text("DOWNLOAD", style: TextStyle(fontWeight: FontWeight.w900, fontSize: isMobile ? 9 : 10, letterSpacing: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoPill(String text, IconData icon, {bool isSize = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSize ? const Color(0xFFFFF3E0) : const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: isSize ? Colors.orange.shade800 : Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: isSize ? Colors.orange.shade900 : const Color(0xFF455A64), fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text("No snapshots found", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showSuccessModal(String message) {
    // Modal removed in favor of top snackbars
  }
}

class _CuteDateFilterPicker extends StatefulWidget {
  final DateTime initialDate;
  const _CuteDateFilterPicker({required this.initialDate});

  @override
  State<_CuteDateFilterPicker> createState() => _CuteDateFilterPickerState();
}

class _CuteDateFilterPickerState extends State<_CuteDateFilterPicker> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Filter by Date", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00897B))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          const Align(alignment: Alignment.centerLeft, child: Text("Pick a date to filter backup snapshots.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500))),
          const Divider(height: 32),
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF00897B),
                onPrimary: Colors.white,
                onSurface: Color(0xFF1A1A1A),
              ),
            ),
            child: CalendarDatePicker(
              initialDate: _selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              onDateChanged: (date) => setState(() => _selectedDate = date),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text("CLEAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedDate),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("APPLY FILTER", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
