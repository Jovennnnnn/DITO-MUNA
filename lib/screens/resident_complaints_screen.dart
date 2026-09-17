import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../api/api_service.dart';
import '../utils/app_theme.dart';
import '../utils/session_manager.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';
import '../utils/responsive.dart';
import '../widgets/custom_snackbar.dart';
import '../utils/custom_notification.dart';

class ResidentComplaintsScreen extends StatefulWidget {
  final bool isEmbedded;
  final String? targetComplaintId;
  final VoidCallback? onBack;
  final VoidCallback? onDataChanged;
  const ResidentComplaintsScreen(
      {super.key,
      this.isEmbedded = false,
      this.targetComplaintId,
      this.onBack,
      this.onDataChanged});

  @override
  State<ResidentComplaintsScreen> createState() => _ResidentComplaintsScreenState();
}

class _ResidentComplaintsScreenState extends State<ResidentComplaintsScreen> with TickerProviderStateMixin {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  
  List<dynamic> _complaints = [];
  List<dynamic> _allComplaints = [];
  bool _isLoading = true;
  String? _localHighlightId;
  bool _showHeaderShadow = true;

  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;

  // Filter State
  String _selectedType = "All Types";
  String _selectedStatus = "All Status";
  DateTime _selectedDate = DateTime.now();
  bool _isDateFilterActive = false;

  final List<String> _categories = ["All Types", 'Uncollected Garbage', 'Spilled Waste', 'Driver Behavior', 'Schedule Issue', 'Other'];
  final List<String> _statuses = ["All Status", "Pending", "In Progress", "Resolved"];

  // View Mode State
  String _viewMode = "Active"; // "Active" or "Archived"

  @override
  void initState() {
    super.initState();
    _localHighlightId = widget.targetComplaintId;
    _fetchComplaints();

    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _scrollController.addListener(() {
      if (_scrollController.offset <= 0 && !_showHeaderShadow) {
        setState(() => _showHeaderShadow = true);
      } else if (_scrollController.offset > 0 && _showHeaderShadow) {
        setState(() => _showHeaderShadow = false);
      }
    });

    if (_localHighlightId != null) {
      _startHighlightTimer();
    }
  }

  void _startHighlightTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _localHighlightId = null;
        });
      }
    });
  }

  @override
  void didUpdateWidget(ResidentComplaintsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetComplaintId != null && widget.targetComplaintId != oldWidget.targetComplaintId) {
      setState(() {
        _localHighlightId = widget.targetComplaintId;
      });
      _scrollToTarget();
      _startHighlightTimer();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshRotationController.dispose();
    super.dispose();
  }

  Future<void> _refreshAllStats({bool manual = false}) async {
    if (_isRefreshing) return;
    
    if (manual && mounted) {
      setState(() {
        _isRefreshing = true;
        _showRefreshSpinner = true;
        _manualPullDepth = 80.0;
      });
    }
    _refreshRotationController.repeat();

    await Future.wait([
      _fetchComplaints(isManualRefresh: true),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);

    if (manual) {
      await Future.delayed(const Duration(seconds: 1));
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
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 15,
                          offset: const Offset(0, 5))
                    ],
                  ),
                  child: const Material(
                    color: Colors.transparent,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                        SizedBox(width: 12),
                        Text("Complaints updated",
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Color(0xFF1A1A1A))),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }
      }
      _refreshRotationController.stop();
    }
  }

  Future<void> _fetchComplaints({bool isManualRefresh = false}) async {
    if (!isManualRefresh) setState(() => _isLoading = true);
    final user = await SessionManager.getUser();
    try {
      final response = await _apiService.getComplaints();
      if (response.data['success'] == true) {
        final List all = response.data['data'];
        final List filtered = all
            .where((c) =>
                (c['user_id'] ?? c['resident_id']).toString() == user?.userId.toString())
            .toList();
        setState(() {
          _allComplaints = filtered;
          _applyFilters();
          _isLoading = false;
        });

        if (_localHighlightId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToTarget();
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    // 1. Start with full data source
    List<dynamic> results = List.from(_allComplaints);

    // 2. Filter by Age (Archive Logic: 30 days)
    final DateTime now = DateTime.now();
    results = results.where((c) {
      DateTime? dt = DateTime.tryParse(c['created_at'] ?? '');
      if (dt == null) return _viewMode == "Active";
      bool isOld = now.difference(dt).inDays >= 30;
      return _viewMode == "Active" ? !isOld : isOld;
    }).toList();

    // 3. Filter by Type (Category)
    if (_selectedType != "All Types") {
      results = results.where((c) => (c['category'] ?? '').toString() == _selectedType).toList();
    }

    // 4. Filter by Status
    if (_selectedStatus != "All Status") {
      results = results.where((c) =>
        _normalizeStatus(c['status']).toLowerCase() == _selectedStatus.toLowerCase()
      ).toList();
    }

    // 5. Filter by Date (only if active)
    if (_isDateFilterActive) {
      results = results.where((c) {
        DateTime? dt = DateTime.tryParse(c['created_at'] ?? '');
        if (dt == null) return false;
        return dt.year == _selectedDate.year &&
               dt.month == _selectedDate.month &&
               dt.day == _selectedDate.day;
      }).toList();
    }

    // 6. Update UI list
    setState(() {
      _complaints = results;
    });
  }

  String _normalizeStatus(dynamic s) {
    if (s == null) return 'Pending';
    String str = s.toString().toUpperCase().trim().replaceAll('_', ' ');
    if (str == 'PENDING' || str == 'SUBMITTED' || str == '0') return 'Pending';
    if (str == 'IN PROGRESS' || str == 'UNDER REVIEW' || str.contains('PROGRESS') || str == '1') return 'In Progress';
    if (str == 'RESOLVED' || str == 'COMPLETED' || str == '2') return 'Resolved';
    return 'Pending';
  }

  void _scrollToTarget() async {
    if (_localHighlightId == null) return;

    // Increased delay to ensure AnimatedList has finished its initial build/frames
    await Future.delayed(const Duration(milliseconds: 600));

    // Retry a few times if context is not yet available
    for (int i = 0; i < 5; i++) {
      final targetKey = _itemKeys[_localHighlightId];
      if (targetKey?.currentContext != null) {
        Scrollable.ensureVisible(
          targetKey!.currentContext!,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOutQuart,
          alignment: 0.5, // Centers the item
        );
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Fallback: If still not found, try scrolling based on index if possible
    int idx = _complaints.indexWhere((c) => (c['complaint_id'] ?? c['id']).toString() == _localHighlightId);
    if (idx != -1 && _scrollController.hasClients) {
       // Rough estimation if target is far down
       double targetOffset = (idx * 200.0).clamp(0.0, _scrollController.position.maxScrollExtent);
       _scrollController.animateTo(
         targetOffset,
         duration: const Duration(milliseconds: 800),
         curve: Curves.easeOut,
       );
    }
  }

  Future<void> _deleteFromFirebase(int id) async {
    try {
      final snapshot = await _database.ref('complaints').get();
      if (snapshot.exists) {
        final Map data = snapshot.value as Map;
        data.forEach((key, value) {
          if (value is Map && (value['complaint_id']?.toString() == id.toString() || value['id']?.toString() == id.toString())) {
            _database.ref('complaints/$key').remove();
          }
        });
      }
      final notifRef = _database.ref('notifications');
      final notifSnapshot = await notifRef.get();
      if (notifSnapshot.exists) {
        final Map notifData = notifSnapshot.value as Map;
        notifData.forEach((key, value) {
          if (value is Map) {
            if (value['type'] == 'COMPLAINT_RESOLVED' &&
                value['relatedId']?.toString() == id.toString()) {
              notifRef.child(key).remove();
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Firebase cleanup error: $e");
    }
  }

  Widget _buildArchiveToggle() {
    final bool isDesktop = Responsive.isDesktop(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 20, vertical: 8),
      child: Row(
        mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max, // Full width sa mobile para sa alignment
        mainAxisAlignment: MainAxisAlignment.start, // Naka-anchor sa kaliwa
        children: [
          _buildTextTabItem("Active", _viewMode == "Active"),
          const SizedBox(width: 28),
          _buildTextTabItem("Archived", _viewMode == "Archived"),
        ],
      ),
    );
  }

  Widget _buildTextTabItem(String label, bool isActive) {
    return _HoverZoomLink(
      onTap: () {
        if (!isActive) {
          setState(() {
            _viewMode = label;
            _applyFilters();
          });
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: isActive ? const Color(0xFF00796B) : Colors.grey.shade400,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 3,
            width: isActive ? 20 : 0,
            decoration: BoxDecoration(
              color: const Color(0xFF00796B),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog({required String title, required String message}) async {
    return await showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, height: 1.5)),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: HoverActionButton(
                          text: "CONFIRM",
                          isDestructive: true,
                          onTap: () => Navigator.pop(context, true),
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ) ??
        false;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    CustomSnackBar.show(context, message: message, isError: isError, isModal: true);
  }

  @override
  Widget build(BuildContext context) {
    return Responsive.isDesktop(context) ? _buildDesktopLayout() : _buildMobileLayout();
  }

  Widget _buildDesktopLayout() {
    // Summary counts are calculated based on the FULL data, unless filtered by DATE
    List<dynamic> statsSource = _allComplaints;
    if (_isDateFilterActive) {
      statsSource = statsSource.where((c) {
        DateTime? dt = DateTime.tryParse(c['created_at'] ?? '');
        if (dt == null) return false;
        return dt.year == _selectedDate.year && dt.month == _selectedDate.month && dt.day == _selectedDate.day;
      }).toList();
    }

    int pending = statsSource.where((c) => _normalizeStatus(c['status']).toLowerCase() == 'pending').length;
    int inProgress = statsSource.where((c) => _normalizeStatus(c['status']).toLowerCase() == 'in progress').length;
    int resolved = statsSource.where((c) => _normalizeStatus(c['status']).toLowerCase() == 'resolved').length;

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: _buildFloatingAddButton(),
      body: Stack(
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
                _buildWebHeader(),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: (_manualPullDepth > 0 || _isRefreshing) 
                          ? const NeverScrollableScrollPhysics() 
                          : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      child: AnimatedBuilder(
                        animation: _scrollController,
                        builder: (context, child) {
                          final double offset = _scrollController.hasClients ? _scrollController.offset : 0;
                          return Transform.translate(
                            offset: Offset(0, offset < 0 ? offset : 0),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 1100),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _buildDesktopSummaryCard("Pending Reports", pending.toString(), const Color(0xFFFFF8E1), Colors.amber.shade900, Icons.hourglass_empty_rounded),
                                          const SizedBox(width: 20),
                                          _buildDesktopSummaryCard("Under Review", inProgress.toString(), const Color(0xFFE3F2FD), Colors.blue.shade800, Icons.bolt_rounded),
                                          const SizedBox(width: 20),
                                          _buildDesktopSummaryCard("Resolved Issues", resolved.toString(), const Color(0xFFE8F5E9), const Color(0xFF2E7D32), Icons.verified_rounded),
                                        ],
                                      ),
                                      const SizedBox(height: 32),
                                      _buildArchiveToggle(),
                                      const SizedBox(height: 12),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
                                        child: Row(
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text("Submission History",
                                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                                                Text(_viewMode == "Active" 
                                                    ? "Manage and track your reported concerns"
                                                    : "Records older than 30 days are archived here",
                                                    style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
                                              ],
                                            ),
                                            const Spacer(),
                                            const SizedBox(width: 200),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 32),
                                      _isLoading
                                          ? const Center(child: Padding(padding: EdgeInsets.all(100), child: CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3)))
                                          : _complaints.isEmpty
                                              ? Center(child: _buildEmptyState())
                                              : AnimatedList(
                                                  key: _listKey,
                                                  shrinkWrap: true,
                                                  initialItemCount: _complaints.length,
                                                  physics: const NeverScrollableScrollPhysics(),
                                                  itemBuilder: (context, index, animation) => _buildDismissibleItem(_complaints[index], index, animation),
                                                ),
                                      const SizedBox(height: 48),
                                    ],
                                  ),
                                ),
                              ),
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
          _buildRefreshSpinner(),
        ],
      ),
    );
  }

  Widget _buildRefreshSpinner() {
    return AnimatedBuilder(
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
    );
  }

  Widget _buildDesktopSummaryCard(String label, String count, Color bgColor, Color textColor, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: AppTheme.balancedPulidongShadow, border: Border.all(color: Colors.white, width: 1)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: textColor, size: 30),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(count, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -1.5)),
                  Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebHeader() {
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
            child: const Icon(Icons.history_edu_rounded, color: Color(0xFF00897B), size: 28),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Complaint Management",
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: -0.5)),
                Text("Monitor and track your reported concerns in real-time.",
                    style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          _buildFilterBar(),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    // Summary counts are calculated based on the FULL data, unless filtered by DATE
    List<dynamic> statsSource = _allComplaints;
    if (_isDateFilterActive) {
      statsSource = statsSource.where((c) {
        DateTime? dt = DateTime.tryParse(c['created_at'] ?? '');
        if (dt == null) return false;
        return dt.year == _selectedDate.year && dt.month == _selectedDate.month && dt.day == _selectedDate.day;
      }).toList();
    }

    int pending = statsSource.where((c) => _normalizeStatus(c['status']).toLowerCase() == 'pending').length;
    int inProgress = statsSource.where((c) => _normalizeStatus(c['status']).toLowerCase() == 'in progress').length;
    int resolved = statsSource.where((c) => _normalizeStatus(c['status']).toLowerCase() == 'resolved').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      floatingActionButton: _buildFloatingAddButton(),
      body: Stack(
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
            child: FadeSlideEntrance(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 15,
                          offset: const Offset(0, 4)
                        )
                      ]
                    ),
                    child: Row(
                      children: [
                        if (!widget.isEmbedded || widget.onBack != null) _buildCircularBackButton(),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("My Complaints", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -0.5)),
                              Text("Track your submitted reports", style: TextStyle(fontSize: 11, color: Color(0xFF757575), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.history_edu_rounded, color: Color(0xFF00897B), size: 24)
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    color: const Color(0xFFF8F9FA),
                    child: _buildFilterBar(),
                  ),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                      child: SafeArea(
                        top: false,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          physics: (_manualPullDepth > 0 || _isRefreshing) 
                              ? const NeverScrollableScrollPhysics() 
                              : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          child: AnimatedBuilder(
                            animation: _scrollController,
                            builder: (context, child) {
                              final double offset = _scrollController.hasClients ? _scrollController.offset : 0;
                              return Transform.translate(
                                offset: Offset(0, offset < 0 ? offset : 0),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                      child: Row(
                                        children: [
                                          _buildSummaryCard("Pending", pending.toString(), const Color(0xFFFFF8E1), Colors.amber.shade900, Icons.hourglass_empty_rounded),
                                          const SizedBox(width: 12),
                                          _buildSummaryCard("Active", inProgress.toString(), const Color(0xFFE3F2FD), Colors.blue.shade800, Icons.bolt_rounded),
                                          const SizedBox(width: 12),
                                          _buildSummaryCard("Solved", resolved.toString(), const Color(0xFFE8F5E9), const Color(0xFF2E7D32), Icons.verified_rounded),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildArchiveToggle(),
                                    const SizedBox(height: 8),

                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              "Submission History",
                                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _viewMode == "Active"
                                                  ? "Manage and track your reported concerns"
                                                  : "Records older than 30 days are archived here",
                                              style: TextStyle(
                                                  fontSize: 12, 
                                                  color: Colors.grey.shade600, 
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    if (_isLoading)
                                      const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3))
                                    else if (_complaints.isEmpty)
                                      _buildEmptyState()
                                    else
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 800),
                                          child: AnimatedList(
                                            key: _listKey,
                                            shrinkWrap: true,
                                            padding: EdgeInsets.zero,
                                            initialItemCount: _complaints.length,
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemBuilder: (context, index, animation) => _buildDismissibleItem(_complaints[index], index, animation),
                                          ),
                                        ),
                                      ),
                                    SizedBox(height: (MediaQuery.of(context).size.width * 0.25).clamp(80.0, 120.0)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildRefreshSpinner(),
        ],
      ),
    );
  }

  void _showAddComplaintModal(BuildContext context) {
    bool isModalLoading = true;
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            if (isModalLoading) {
              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) setModalState(() => isModalLoading = false);
              });
            }
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                ),
                constraints: BoxConstraints(
                  maxWidth: 550,
                  maxHeight: isModalLoading ? 280 : MediaQuery.of(context).size.height * 0.85,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(child: Text("New Complaint", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                            ],
                          ),
                          const Text("Report an issue or concern to the garbage collection service.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                    if (isModalLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppColors.tealText),
                              SizedBox(height: 16),
                              Text("Preparing your complaint form...",
                                  style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: AddComplaintModal(
                          showHeader: false,
                          onSuccess: () {
                            _fetchComplaints();
                            if (widget.onDataChanged != null) widget.onDataChanged!();
                          }
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            if (isModalLoading) {
              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) setModalState(() => isModalLoading = false);
              });
            }
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                constraints: BoxConstraints(
                  maxHeight: isModalLoading ? 280 : MediaQuery.of(context).size.height * 0.85,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(child: Text("New Complaint", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                            ],
                          ),
                          const Text("Report an issue or concern to the garbage collection service.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                    if (isModalLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppColors.tealText),
                              SizedBox(height: 16),
                              Text("Preparing your complaint form...",
                                  style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: AddComplaintModal(
                          showHeader: false,
                          onSuccess: () {
                            _fetchComplaints();
                            if (widget.onDataChanged != null) widget.onDataChanged!();
                          }
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
        ),
      );
    }
  }

  Widget _buildFloatingAddButton() {
    final bool isDesktop = Responsive.isDesktop(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isDesktop ? 20 : 80),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _showAddComplaintModal(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.loginButtonStart, AppColors.loginButtonEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: AppColors.loginButtonStart.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 24),
                SizedBox(width: 12),
                Text(
                  "New Complaint",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, String count, Color bgColor, Color textColor, IconData icon) {
    final double screenWidth = MediaQuery.of(context).size.width;
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 110),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.balancedPulidongShadow,
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: textColor, size: (screenWidth * 0.05).clamp(18.0, 20.0)),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(count, style: TextStyle(fontSize: (screenWidth * 0.065).clamp(20.0, 26.0), fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A), letterSpacing: -1.0)),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: TextStyle(fontSize: (screenWidth * 0.025).clamp(9.0, 10.0), fontWeight: FontWeight.w800, color: Colors.grey.shade600, letterSpacing: 0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularBackButton() {
    return GestureDetector(
      onTap: () {
        if (widget.onBack != null) { widget.onBack!(); } else { Navigator.pop(context); }
      },
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A1A), size: 18),
      ),
    );
  }

  Widget _buildDismissibleItem(dynamic complaint, int index, Animation<double> animation, {bool isRemoving = false}) {
    final String cid = (complaint['complaint_id'] ?? complaint['id']).toString();

    // Register or retrieve GlobalKey for this item
    if (!_itemKeys.containsKey(cid)) {
      _itemKeys[cid] = GlobalKey();
    }

    final Widget card = ComplaintItemCard(
      key: _itemKeys[cid], // Pass the key here
      complaint: complaint,
      isHighlighted: _localHighlightId != null && cid == _localHighlightId,
      onDelete: () {
        int curIdx = _complaints.indexWhere((c) => (c['complaint_id'] ?? c['id']).toString() == cid);
        if (curIdx != -1) {
          // You can still allow single delete if you want, but user said remove "selection delete"
          // I'll keep it as it is for single swipe, but the button/selection is gone.
        }
      },
    );

    if (isRemoving) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.5, 0.0), // Swipe right
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInCubic)),
        child: FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            child: card,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: Key("dismiss_$cid"),
        direction: DismissDirection.horizontal,
        confirmDismiss: (dir) async => await _showConfirmDialog(
          title: "Delete this record?",
          message: "This entry will be permanently removed from your history.",
        ),
        onDismissed: (dir) async {
          int curIndex = _complaints.indexWhere((c) => (c['complaint_id'] ?? c['id']).toString() == cid);
          if (curIndex != -1) {
            final removedItem = _complaints.removeAt(curIndex);
            _allComplaints.removeWhere((c) => (c['complaint_id'] ?? c['id']).toString() == cid);
            _listKey.currentState?.removeItem(
              curIndex,
              (context, animation) => const SizedBox.shrink(),
              duration: Duration.zero,
            );

            final int id = int.tryParse((removedItem['complaint_id'] ?? removedItem['id']).toString()) ?? 0;
            if (id != 0) {
              try {
                final response = await _apiService.deleteComplaint(id);
                if (response.data['success'] == true) {
                  await _deleteFromFirebase(id);
                  _showSnackBar("Complaint permanently removed.");
                  if (widget.onDataChanged != null) widget.onDataChanged!();
                } else {
                  _showSnackBar("Failed to delete from server.", isError: true);
                }
              } catch (e) {
                _showSnackBar("Error deleting record.", isError: true);
              }
            }
          }
        },
        background: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24)),
          alignment: Alignment.centerLeft,
          child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
        ),
        secondaryBackground: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24)),
          alignment: Alignment.centerRight,
          child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
        ),
        child: card,
      ),
    );
  }

  Widget _buildFilterBar() {
    bool isDesktop = Responsive.isDesktop(context);
    String dateLabel = _isDateFilterActive
        ? DateFormat('MMM dd, yyyy').format(_selectedDate)
        : "All Dates";

    if (!isDesktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: _buildTypeDropdown()),
          const SizedBox(width: 8),
          Expanded(child: _buildStatusDropdown()),
          const SizedBox(width: 8),
          Expanded(child: _filterChip(Icons.calendar_today_rounded, dateLabel, onTap: () => _showSingleDatePicker(context), isActive: _isDateFilterActive)),
        ],
      );
    }

    return Wrap(
      spacing: 20,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildTypeDropdown(),
        _buildStatusDropdown(),
        _filterChip(Icons.calendar_today_rounded, dateLabel, onTap: () => _showSingleDatePicker(context), isActive: _isDateFilterActive),
      ],
    );
  }

  Widget _buildTypeDropdown() {
    return PopupMenuButton<String>(
      onSelected: (type) {
        setState(() => _selectedType = type);
        _applyFilters();
      },
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      color: Colors.white,
      itemBuilder: (context) => _categories.map((type) {
        bool isSelected = type == _selectedType;
        return PopupMenuItem<String>(
          value: type,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: isSelected ? const Color(0xFF00897B) : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              Text(
                type,
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
        mainAxisAlignment: MainAxisAlignment.center, // I-center ang content sa mobile view
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.category_rounded, size: 16, color: const Color(0xFF00897B)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _selectedType,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF1A1A1A)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return PopupMenuButton<String>(
      onSelected: (status) {
        setState(() => _selectedStatus = status);
        _applyFilters();
      },
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      color: Colors.white,
      itemBuilder: (context) => _statuses.map((status) {
        bool isSelected = status == _selectedStatus;
        return PopupMenuItem<String>(
          value: status,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: isSelected ? const Color(0xFF00897B) : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              Text(
                status,
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
        mainAxisAlignment: MainAxisAlignment.center, // I-center ang content sa mobile view
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: const Color(0xFF00897B)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _selectedStatus,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF1A1A1A)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Colors.grey),
        ],
      ),
    );
  }

  Future<void> _showSingleDatePicker(BuildContext context) async {
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _CuteSingleDatePicker(initialDate: _selectedDate),
        ),
      ),
    );

    if (picked != null) {
      setState(() { _selectedDate = picked; _isDateFilterActive = true; });
    } else {
      // Logic for clearing: if null is returned, clear the filter directly
      setState(() { _isDateFilterActive = false; });
    }
    _applyFilters();
  }

  Widget _filterChip(IconData icon, String label, {VoidCallback? onTap, bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center, // I-center ang content sa mobile view
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isActive ? const Color(0xFF00897B) : Colors.grey),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: isActive ? const Color(0xFF1A1A1A) : Colors.grey.shade600
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Color(0xFFF5F5F5), shape: BoxShape.circle), child: const Icon(Icons.assignment_turned_in_rounded, size: 56, color: Colors.black12)),
            const SizedBox(height: 24),
            const Text("No History Found", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 8),
            const Text("All your system complaints will appear here once submitted.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF757575), fontSize: 13, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class ComplaintItemCard extends StatefulWidget {
  final dynamic complaint;
  final bool isHighlighted;
  final VoidCallback onDelete;

  const ComplaintItemCard({
    super.key,
    required this.complaint,
    required this.isHighlighted,
    required this.onDelete,
  });

  @override
  State<ComplaintItemCard> createState() => _ComplaintItemCardState();
}

class _ComplaintItemCardState extends State<ComplaintItemCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    String status = (widget.complaint['status'] ?? 'PENDING').toString().toUpperCase();
    Color statusColor = status == 'PENDING' ? Colors.orange : (status == 'RESOLVED' ? Colors.green : Colors.blue);
    String adminResponse = (widget.complaint['admin_response'] ?? '').toString().trim();
    final bool isDesktop = Responsive.isDesktop(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_isHovered ? 1.01 : 1.0),
          padding: EdgeInsets.all(isDesktop ? 28 : 20),
          decoration: BoxDecoration(
            color: widget.isHighlighted ? const Color(0xFFF1F8E9) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: widget.isHighlighted
                        ? const Color(0xFF00897B).withOpacity(0.5)
                        : (_isHovered ? const Color(0xFF00897B).withOpacity(0.2) : Colors.transparent),
                width: 2),
            boxShadow: widget.isHighlighted || _isHovered
                ? [
                    BoxShadow(
                        color: (widget.isHighlighted ? const Color(0xFF00897B) : Colors.black).withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10))
                  ]
                : AppTheme.pulidongShadow,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(widget.complaint['category'] ?? "General",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: isDesktop ? 19 : 16,
                                  color: const Color(0xFF1A1A1A))),
                      ),
                      Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration:
                                BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: Text(status,
                                style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(widget.complaint['description'] ?? "",
                      style: TextStyle(
                          color: const Color(0xFF424242),
                          fontSize: isDesktop ? 15 : 13,
                          height: 1.6,
                          fontWeight: FontWeight.w500)),
                  if (adminResponse.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9).withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.forum_rounded, size: 16, color: Colors.green.shade800),
                              const SizedBox(width: 10),
                              Text("OFFICIAL RESPONSE",
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.green.shade800,
                                      letterSpacing: 0.8)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(adminResponse,
                              style: TextStyle(
                                  color: Colors.green.shade900,
                                  fontSize: isDesktop ? 15 : 13,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.access_time_filled_rounded, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Text(widget.complaint['created_at']?.toString().split('T')[0] ?? "Recently",
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (!isDesktop)
                        const Text("Swipe to delete",
                            style: TextStyle(color: Colors.black12, fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverZoomLink extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _HoverZoomLink({required this.child, required this.onTap});
  @override
  State<_HoverZoomLink> createState() => _HoverZoomLinkState();
}
class _HoverZoomLinkState extends State<_HoverZoomLink> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _active = true),
        onTapUp: (_) => setState(() => _active = false),
        onTapCancel: () => setState(() => _active = false),
        child: AnimatedScale(scale: _active ? 1.05 : 1.0, duration: const Duration(milliseconds: 200), child: widget.child)
      )
    );
  }
}

class AddComplaintModal extends StatefulWidget {
  final VoidCallback onSuccess;
  final bool showHeader;
  const AddComplaintModal({super.key, required this.onSuccess, this.showHeader = true});
  @override
  State<AddComplaintModal> createState() => AddComplaintModalState();
}

class AddComplaintModalState extends State<AddComplaintModal> {
  final ApiService _apiService = ApiService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedCategory = 'Uncollected Garbage';
  bool _isLoading = false;
  final List<String> _categories = ['Uncollected Garbage', 'Spilled Waste', 'Driver Behavior', 'Schedule Issue', 'Other'];

  void _showCategoryPicker() {
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Select Category", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 24),
                  ..._categories.map((c) {
                    bool isSelected = _selectedCategory == c;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                      title: Text(c, style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, color: isSelected ? AppColors.tealText : const Color(0xFF1A1A1A))),
                      trailing: isSelected ? Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: AppColors.tealText, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size: 14)) : null,
                      onTap: () { setState(() => _selectedCategory = c); Navigator.pop(context); },
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select Category", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 16),
              Flexible(child: ListView.builder(shrinkWrap: true, itemCount: _categories.length, itemBuilder: (context, index) {
                final c = _categories[index];
                bool isSelected = _selectedCategory == c;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                  title: Text(c, style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, color: isSelected ? const Color(0xFF00897B) : const Color(0xFF1A1A1A))),
                  trailing: isSelected ? Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Color(0xFF00897B), shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size: 14)) : null,
                  onTap: () { setState(() => _selectedCategory = c); Navigator.pop(context); },
                );
              })),
            ],
          ),
        ),
      );
    }
  }

  void _submit() async {
    final desc = _descriptionController.text.trim();
    if (desc.isEmpty) { _showSnackBar("Please provide issue details", isError: true); return; }
    bool confirm = await showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("File Complaint?", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    const Text("Proceed with this report?", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: HoverActionButton(text: "CONFIRM", onTap: () => Navigator.pop(context, true)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ?? false;
    if (!confirm) return;
    setState(() => _isLoading = true);
    final user = await SessionManager.getUser();
    try {
      final response = await _apiService.fileComplaint(user?.userId.toString() ?? "0", _selectedCategory, desc);
      if (response.data['success'] == true) {
        await _database.ref('notifications').push().set({'type': 'RESIDENT_COMPLAINT', 'title': 'New Resident Complaint', 'message': '${user?.name ?? 'A resident'} filed a complaint: $_selectedCategory', 'resident_id': user?.userId, 'timestamp': ServerValue.timestamp, 'isRead': false});
        if (!mounted) return;
        Navigator.pop(context);
        widget.onSuccess();
        _showSnackBar("Complaint submitted successfully");
      }
    } catch (e) {
      if (mounted) _showSnackBar("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    CustomSnackBar.show(context, message: message, isError: isError, isModal: true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(0, 12, 0, Responsive.isDesktop(context) ? 32 : (MediaQuery.of(context).viewInsets.bottom + 32)),
      decoration: BoxDecoration(color: Colors.white, borderRadius: Responsive.isDesktop(context) ? BorderRadius.circular(32) : const BorderRadius.vertical(top: Radius.circular(32))),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showHeader) ...[
              if (!Responsive.isDesktop(context)) ...[
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 24),
              ],
              if (Responsive.isDesktop(context)) const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(child: Text("New Complaint", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                  ],
                ),
              ),
              const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text("Report an issue or concern to the garbage collection service.", textAlign: TextAlign.left, style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Divider(height: 32)),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select Category", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey)),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _showCategoryPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_selectedCategory, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A1A))), const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey)]),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text("Describe the issue", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(16)),
                    child: TextField(controller: _descriptionController, maxLines: 4, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), decoration: const InputDecoration(hintText: "Tell us more...", border: InputBorder.none, contentPadding: EdgeInsets.all(16))),
                  ),
                  const SizedBox(height: 32),
                  HoverActionButton(text: "Submit Complaint", loadingText: "Submitting...", isLoading: _isLoading, onTap: _submit),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CuteSingleDatePicker extends StatefulWidget {
  final DateTime initialDate;
  const _CuteSingleDatePicker({required this.initialDate});
  @override State<_CuteSingleDatePicker> createState() => _CuteSingleDatePickerState();
}

class _CuteSingleDatePickerState extends State<_CuteSingleDatePicker> {
  late DateTime _currentMonth;
  late DateTime _selectedDate;
  bool _isYearPickerVisible = false;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _selectedDate = widget.initialDate;
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
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Select Date", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                  SizedBox(height: 4),
                  Text("Pick a date to filter records.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
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
                  onPressed: () {
                    // Logic to clear: return a specific value or handle state here
                    // Since it's a dialog returning value, we can use a special date or null
                    Navigator.pop(context, null);
                  },
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
                  onPressed: () => Navigator.pop(context, _selectedDate),
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

        bool isSelected = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;

        return InkWell(
          onTap: () {
            setState(() {
              _selectedDate = date;
            });
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF00897B) : null,
              shape: BoxShape.circle,
              border: (date.day == DateTime.now().day && date.month == DateTime.now().month && date.year == DateTime.now().year)
                ? Border.all(color: const Color(0xFF00897B), width: 1)
                : null,
            ),
            child: Text(
              day.toString(),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal,
              ),
            ),
          ),
        );
    });
  }
}
