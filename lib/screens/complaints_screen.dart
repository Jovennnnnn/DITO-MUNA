import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../api/api_service.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/hover_action_button.dart';
import '../utils/custom_notification.dart';
import '../widgets/custom_snackbar.dart';

class ComplaintsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const ComplaintsScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  bool _showHeaderShadow = true;
  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;
  List<dynamic> _residentComplaints = [];
  List<dynamic> _driverIssues = [];
  bool _isLoadingResident = true;
  bool _isLoadingDriver = true;
  StreamSubscription? _driverIssuesSubscription;

  // Filtering State
  final TextEditingController _residentSearchController = TextEditingController();
  final TextEditingController _driverSearchController = TextEditingController();
  String _residentStatusFilter = "All Status";
  String _residentCategoryFilter = "All Categories";
  DateTime? _residentDateFilter;
  String _driverStatusFilter = "All Status";
  String _driverCategoryFilter = "All Categories";
  DateTime? _driverDateFilter;

  final List<String> _residentCategories = ["All Categories", "Uncollected Garbage", "Spilled Waste", "Driver Behavior", "Schedule Issue", "Other"];
  final List<String> _driverCategories = ["All Categories", "Engine", "Tires", "Brakes", "GPS", "Electrical", "Fuel", "Transmission", "Hydraulic System", "Body Damage", "Other"];
  final List<String> _statusOptions = ["All Status", "Pending", "In Progress", "Resolved"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _fetchResidentComplaints();
    _listenToDriverIssues();
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
    _driverIssuesSubscription?.cancel();
    _refreshRotationController.dispose();
    _tabController.dispose();
    _scrollController.dispose();
    _residentSearchController.dispose();
    _driverSearchController.dispose();
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
      _fetchResidentComplaints(silent: true),
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
                        "Incident reports synchronized",
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

  Future<void> _fetchResidentComplaints({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingResident = true);
    try {
      final response = await _apiService.getComplaints();
      if (response.data['success'] == true) {
        setState(() { 
          _residentComplaints = response.data['data']; 
          _isLoadingResident = false; 
        });
      }
    } catch (e) { 
      if (mounted) setState(() => _isLoadingResident = false); 
    }
  }

  void _listenToDriverIssues() {
    _driverIssuesSubscription?.cancel();
    _driverIssuesSubscription = _database.ref('truck_issues').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List list = [];
        data.forEach((key, value) {
          list.add({...Map<String, dynamic>.from(value as Map), 'id': key});
        });
        // Sort newest first
        list.sort((a, b) => (b['createdAt'] ?? 0).compareTo(a['createdAt'] ?? 0));
        if (mounted) {
          setState(() {
            _driverIssues = list;
            _isLoadingDriver = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _driverIssues = [];
            _isLoadingDriver = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 900;
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA), // Subtle gray background to make white cards pop
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
                      const SizedBox(height: 16),
                      _buildTabBar(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _isLoadingResident ? const Center(child: CircularProgressIndicator(color: Color(0xFF00897B))) : _buildList(true),
                            _isLoadingDriver ? const Center(child: CircularProgressIndicator(color: Color(0xFF00897B))) : _buildList(false)
                          ],
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
              child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF00796B), size: 28),
            ),
            const SizedBox(width: 20),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Resolve Radar",
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: -0.5)),
                Text("Comprehensive incident and complaint management",
                    style: TextStyle(
                        color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
            const Spacer(),
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
                Text("Resolve Radar", style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A), letterSpacing: -0.5)),
                Text("Manage system complaints", style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF757575), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Container(
            width: iconContainerSize,
            height: iconContainerSize,
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF00796B), size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      color: Colors.transparent, 
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F4F8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100, width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00897B).withOpacity(0.15),
                blurRadius: 15,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: TabBar(
            controller: _tabController,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF00897B),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00897B).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              Tab(text: "RESIDENTS (${_residentComplaints.length})"),
              Tab(text: "DRIVERS (${_driverIssues.length})")
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(bool isResident) {
    List<dynamic> rawList = isResident ? _residentComplaints : _driverIssues;
    
    // Apply Filters
    List<dynamic> filteredList = rawList.where((item) {
      if (isResident) {
        final String name = (item['full_name'] ?? "").toString().toLowerCase();
        final String category = (item['category'] ?? "").toString();
        final String status = _normalizeStatus((item['status'] ?? "").toString());
        final String search = _residentSearchController.text.toLowerCase();
        
        bool matchName = name.contains(search);
        bool matchCategory = _residentCategoryFilter == "All Categories" || category == _residentCategoryFilter;
        bool matchStatus = _residentStatusFilter == "All Status" || status.toLowerCase() == _residentStatusFilter.toLowerCase();
        bool matchDate = true;
        if (_residentDateFilter != null) {
          final String itemDateStr = (item['created_at'] ?? "").toString();
          if (itemDateStr.length >= 10) {
            final DateTime? itemDate = DateTime.tryParse(itemDateStr.substring(0, 10));
            matchDate = itemDate != null && 
                itemDate.year == _residentDateFilter!.year && 
                itemDate.month == _residentDateFilter!.month && 
                itemDate.day == _residentDateFilter!.day;
          }
        }
        return matchName && matchCategory && matchStatus && matchDate;
      } else {
        final String truckId = (item['truckId'] ?? "").toString().toLowerCase();
        final String driverName = (item['driverName'] ?? "").toString().toLowerCase();
        final String status = _normalizeStatus((item['status'] ?? "").toString());
        final String issueType = (item['issueType'] ?? "").toString();
        final String search = _driverSearchController.text.toLowerCase();
        
        bool matchSearch = truckId.contains(search) || driverName.contains(search);
        bool matchStatus = _driverStatusFilter == "All Status" || status.toLowerCase() == _driverStatusFilter.toLowerCase();
        bool matchCategory = _driverCategoryFilter == "All Categories" || issueType == _driverCategoryFilter;
        bool matchDate = true;
        if (_driverDateFilter != null) {
          final dynamic rawTs = item['createdAt'];
          if (rawTs != null) {
            final DateTime itemDate = DateTime.fromMillisecondsSinceEpoch(rawTs is int ? rawTs : int.parse(rawTs.toString()));
            matchDate = itemDate.year == _driverDateFilter!.year && 
                itemDate.month == _driverDateFilter!.month && 
                itemDate.day == _driverDateFilter!.day;
          }
        }
        return matchSearch && matchStatus && matchDate && matchCategory;
      }
    }).toList();

    return Column(
      children: [
        _buildSearchAndFilterBar(isResident),
        const SizedBox(height: 4),
        Expanded(
          child: AnimatedBuilder(
            animation: _scrollController,
            builder: (context, child) {
              final double offset = _scrollController.hasClients ? _scrollController.offset : 0;
              return Transform.translate(
                offset: Offset(0, offset < 0 ? offset : 0),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                  child: filteredList.isEmpty 
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text("No reports match your filters", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, boxConstraints) {
                          final bool isWeb = boxConstraints.maxWidth > 900;
                          return GridView.builder(
                            controller: _scrollController,
                            physics: (_manualPullDepth > 0 || _isRefreshing) 
                                ? const NeverScrollableScrollPhysics() 
                                : const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 100),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: isWeb ? 2 : 1,
                              crossAxisSpacing: 24,
                              mainAxisSpacing: 20,
                              mainAxisExtent: isWeb ? 290 : 265, // Increased height for web/desktop grid layout to avoid clipping/cutting bottom curves
                            ),
                            itemCount: filteredList.length,
                            itemBuilder: (context, i) {
                              return _buildCard(filteredList[i], isResident);
                            },
                          );
                        }
                      ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _normalizeStatus(String s) {
    String str = s.toUpperCase().trim().replaceAll('_', ' ');
    if (str == 'PENDING' || str == 'SUBMITTED') return 'Pending';
    if (str == 'IN PROGRESS' || str == 'UNDER REVIEW' || str.contains('PROGRESS')) return 'In Progress';
    if (str == 'RESOLVED' || str == 'COMPLETED') return 'Resolved';
    return 'Pending';
  }

  Widget _buildSearchAndFilterBar(bool isResident) {
    final bool isDesktop = Responsive.isDesktop(context);
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 0, 24, isDesktop ? 20 : 8),
      color: Colors.transparent, 
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          padding: isDesktop ? const EdgeInsets.all(16) : EdgeInsets.zero,
          decoration: isDesktop ? BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28), // Matches cards
            boxShadow: AppTheme.balancedPulidongShadow,
            border: Border.all(color: Colors.grey.shade50, width: 1.5),
          ) : null,
          child: isDesktop 
            ? Row(
                children: [
                  Expanded(flex: 3, child: _buildSearchBar(isResident)),
                  const SizedBox(width: 16),
                  _buildFilters(isResident),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(isResident),
                  const SizedBox(height: 12),
                  _buildFilters(isResident),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isResident) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
      ),
      child: TextField(
        controller: isResident ? _residentSearchController : _driverSearchController,
        onChanged: (_) => setState(() {}),
        cursorColor: Colors.black54,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        decoration: InputDecoration(
          hintText: isResident ? "Search resident name..." : "Search driver or truck...",
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00897B), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilters(bool isResident) {
    final bool isDesktop = Responsive.isDesktop(context);
    final double spacing = isDesktop ? 16.0 : 12.0;

    List<Widget> children = [];
    if (isResident) {
      children = [
        _buildDropdownFilter(
            Icons.category_rounded, 
            _residentCategoryFilter, 
            _residentCategories, 
            (val) => setState(() => _residentCategoryFilter = val)
          ),
          SizedBox(width: spacing),
          _filterChip(Icons.calendar_today_rounded, _residentDateFilter == null ? "All Dates" : DateFormat('MMM dd, yyyy').format(_residentDateFilter!), onTap: () => _showDatePicker(true)),
          SizedBox(width: spacing),
          _buildDropdownFilter(
            Icons.info_outline_rounded, 
            _residentStatusFilter, 
            _statusOptions, 
            (val) => setState(() => _residentStatusFilter = val)
          ),
      ];
    } else {
      children = [
        _buildDropdownFilter(
            Icons.category_rounded, 
            _driverCategoryFilter, 
            _driverCategories, 
            (val) => setState(() => _driverCategoryFilter = val)
          ),
          SizedBox(width: spacing),
          _filterChip(Icons.calendar_today_rounded, _driverDateFilter == null ? "All Dates" : DateFormat('MMM dd, yyyy').format(_driverDateFilter!), onTap: () => _showDatePicker(false)),
          SizedBox(width: spacing),
          _buildDropdownFilter(
            Icons.info_outline_rounded, 
            _driverStatusFilter, 
            _statusOptions, 
            (val) => setState(() => _driverStatusFilter = val)
          ),
      ];
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildDropdownFilter(IconData icon, String currentVal, List<String> options, Function(String) onSelect) {
    final bool isDesktop = Responsive.isDesktop(context);
    final double fontSize = isDesktop ? 13 : 11.5;
    final double iconSize = isDesktop ? 18 : 16;

    return PopupMenuButton<String>(
      onSelected: onSelect,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      color: Colors.white,
      itemBuilder: (context) => options.map((opt) {
        bool isSelected = opt == currentVal;
        return PopupMenuItem<String>(
          value: opt,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: isSelected ? const Color(0xFF00897B) : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              Text(
                opt,
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
          Icon(icon, size: iconSize, color: const Color(0xFF00796B)),
          const SizedBox(width: 8),
          Text(currentVal, style: TextStyle(fontWeight: FontWeight.w800, fontSize: fontSize, color: const Color(0xFF1A1A1A))),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down_rounded, size: iconSize + 2, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _filterChip(IconData icon, String label, {VoidCallback? onTap}) {
    final bool isDesktop = Responsive.isDesktop(context);
    final double fontSize = isDesktop ? 13 : 11.5;
    final double iconSize = isDesktop ? 18 : 16;

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: const Color(0xFF00796B)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: fontSize, color: const Color(0xFF1A1A1A))),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down_rounded, size: iconSize + 2, color: Colors.grey),
        ],
      ),
    );
  }


  Future<void> _showDatePicker(bool isResident) async {
    final DateTime? current = isResident ? _residentDateFilter : _driverDateFilter;
    
    DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: _CuteDatePicker(initialDate: current ?? DateTime.now(), isMobile: false),
        ),
      ),
    );

    setState(() {
      if (isResident) {
        _residentDateFilter = picked;
      } else {
        _driverDateFilter = picked;
      }
    });
  }


  Widget _buildCard(dynamic c, bool isResident) {
    String status = (c['status'] ?? 'PENDING').toString().toUpperCase().replaceAll('_', ' ');
    Color statusColor = Colors.orange;
    if (status == 'RESOLVED') statusColor = Colors.green;
    if (status == 'IN PROGRESS' || status == 'UNDER REVIEW') statusColor = Colors.blue;

    String title = isResident ? (c['category'] ?? "General") : (c['issueType'] ?? "Truck Issue");
    String reporter = isResident ? (c['full_name'] ?? 'Resident') : (c['driverName'] ?? 'Driver');
    String description = (c['description'] ?? "").toString();
    String truckInfo = !isResident ? "${c['truckId'] ?? 'N/A'}" : "";
    String date = isResident 
        ? (c['created_at'] ?? '') 
        : DateFormat('MMM dd, yyyy • h:mm a').format(DateTime.fromMillisecondsSinceEpoch(c['createdAt'] ?? 0));

    IconData issueIcon = isResident ? Icons.report_problem_rounded : Icons.engineering_rounded;
    if (title.toLowerCase().contains('garbage')) issueIcon = Icons.delete_sweep_rounded;
    if (title.toLowerCase().contains('spill')) issueIcon = Icons.water_drop_rounded;
    if (title.toLowerCase().contains('behavior')) issueIcon = Icons.person_off_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.grey.shade50, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Info Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isResident ? const Color(0xFFE0F2F1) : const Color(0xFFE3F2FD)),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(issueIcon, color: isResident ? const Color(0xFF00796B) : const Color(0xFF1976D2), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, 
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A), letterSpacing: -0.2)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _reporterPill(reporter, Icons.person_rounded),
                        if (!isResident)
                          _reporterPill(truckInfo, Icons.local_shipping_rounded, isTruck: true),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildStatusBadge(status, statusColor),
                  if (!isResident) ...[
                    const SizedBox(height: 8),
                    _buildUrgencyBadge(c['urgency'] ?? 'Medium'),
                  ],
                ],
              ),
            ],
          ),
          
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 12),
            child: Divider(height: 1, color: Color(0xFFF1F4F8)),
          ),

          const Text("REPORT DESCRIPTION", 
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Text(description, 
              maxLines: 2, 
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF424242), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 12),

          const Spacer(),

          // Bottom Metadata & Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700)),
                ],
              ),
              TextButton(
                onPressed: () => _showDetailsModal(c, isResident),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00897B),
                  backgroundColor: const Color(0xFFE0F2F1).withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: Colors.transparent,
                ),
                child: const Text("VIEW DETAILS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reporterPill(String text, IconData icon, {bool isTruck = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isTruck ? const Color(0xFFF3E5F5) : const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: isTruck ? Colors.purple.shade700 : Colors.grey.shade600),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text, 
              style: TextStyle(color: isTruck ? Colors.purple.shade900 : const Color(0xFF455A64), fontSize: 11, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgencyBadge(dynamic urgency) {
    String u = urgency.toString().toUpperCase();
    Color color = _getUrgencyColor(urgency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(10), 
        border: Border.all(color: color.withOpacity(0.3), width: 1)
      ),
      child: Text(u, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(10), 
        border: Border.all(color: color.withOpacity(0.3), width: 1)
      ),
      child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }

  void _showDetailsModal(dynamic item, bool isResident) {
    final String status = (item['status'] ?? 'PENDING').toString().toUpperCase();
    final TextEditingController responseController = TextEditingController(text: item['adminResponse'] ?? item['admin_response'] ?? "");
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    bool isModalLoading = true;

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

          Widget contentBody(ScrollController scrollController) => Container(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24), // Increased bottom padding to 24 for better spacing
            decoration: BoxDecoration(
              color: Colors.white,
              // Responsive radius: Full curve for Dialog (Web/Tablet), Top-only curve for BottomSheet (Mobile)
              borderRadius: isMobile 
                  ? const BorderRadius.vertical(top: Radius.circular(32)) 
                  : BorderRadius.circular(32),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile) Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isResident ? "Resident Complaint" : "Driver Report", 
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                        const SizedBox(height: 4),
                        Text(isResident ? "Review and respond to resident feedback." : "Assess and update vehicle technical issues.", 
                          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
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
                const Divider(height: 40),
                Flexible(
                  child: ListView(
                    controller: scrollController,
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      if (isModalLoading)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                const CircularProgressIndicator(color: Color(0xFF00897B), strokeWidth: 3),
                                const SizedBox(height: 16),
                                Text("Fetching full report details...", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 13)),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        _buildInfoSection("DESCRIPTION", isResident ? (item['description'] ?? '') : (item['description'] ?? '')),
                        const SizedBox(height: 12),
                        _buildInfoSection("REPORTER", isResident ? (item['full_name'] ?? 'Unknown') : (item['driverName'] ?? 'Unknown')),
                        if (!isResident) _buildInfoSection("TRUCK ID", item['truckId'] ?? 'N/A'),
                        _buildInfoSection("CATEGORY / ISSUE", isResident ? (item['category'] ?? 'General') : (item['issueType'] ?? 'N/A')),
                        if (!isResident) _buildInfoSection("URGENCY", (item['urgency'] ?? 'Medium').toString().toUpperCase(), color: _getUrgencyColor(item['urgency'])),
                        _buildInfoSection("SUBMITTED", isResident ? (item['created_at'] ?? '') : DateFormat('MMM dd, yyyy • h:mm a').format(DateTime.fromMillisecondsSinceEpoch(item['createdAt'] ?? 0))),
                        const Divider(height: 40),
                        const Text("ADMIN ACTION", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: Colors.grey)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: responseController,
                          maxLines: 3,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: "Enter response to the ${isResident ? 'resident' : 'driver'}...",
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            filled: true,
                            fillColor: const Color(0xFFF7F8FA),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.all(20),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            if (status != 'IN_PROGRESS' && status != 'RESOLVED')
                              Expanded(child: _buildActionButton("MARK IN PROGRESS", Colors.blue, () async {
                                bool confirmed = await _showConfirmDialog(
                                  title: "Mark as In Progress?",
                                  message: "Are you sure you want to update this report's status to In Progress?",
                                );
                                if (confirmed) {
                                  _updateStatus(item, 'IN_PROGRESS', responseController.text, isResident);
                                }
                              })),
                            if (status != 'IN_PROGRESS' && status != 'RESOLVED') const SizedBox(width: 16),
                            if (status != 'RESOLVED')
                              Expanded(child: _buildActionButton("RESOLVE INCIDENT", const Color(0xFF00897B), () async {
                                bool confirmed = await _showConfirmDialog(
                                  title: "Resolve Incident?",
                                  message: "Are you sure you want to mark this incident as resolved?",
                                );
                                if (confirmed) {
                                  _updateStatus(item, 'RESOLVED', responseController.text, isResident);
                                }
                              })),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Container(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: contentBody(ScrollController()),
            );
          } else {
            return Center(
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600, maxHeight: 750),
                  child: contentBody(ScrollController()),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildInfoSection(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color ?? Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
    );
  }

  Color _getUrgencyColor(dynamic urgency) {
    String u = urgency.toString().toLowerCase();
    if (u == 'critical') return Colors.red;
    if (u == 'high') return Colors.orange.shade900;
    if (u == 'medium') return Colors.orange;
    return Colors.blue;
  }

  Future<void> _updateStatus(dynamic item, String newStatus, String adminResponse, bool isResident) async {
    try {
      if (isResident) {
        await _apiService.updateComplaint(int.parse(item['id'].toString()), newStatus.toLowerCase(), adminResponse);
        
        // Notify Resident if resolved
        if (newStatus == 'RESOLVED') {
          await _database.ref('notifications').push().set({
            'type': 'COMPLAINT_RESOLVED',
            'title': 'Complaint Resolved',
            'message': 'Your complaint regarding ${item['category']} has been resolved.',
            'resident_id': item['user_id']?.toString(),
            'relatedId': item['id'],
            'timestamp': ServerValue.timestamp,
            'isRead': false,
          });
        }

        await _fetchResidentComplaints();
      } else {
        final updates = {
          'status': newStatus,
          'adminResponse': adminResponse,
          'updatedAt': ServerValue.timestamp,
        };
        if (newStatus == 'RESOLVED') {
          updates['resolvedAt'] = ServerValue.timestamp;
        }
        await _database.ref('truck_issues/${item['id']}').update(updates);
        
        // Notify Driver
        await _database.ref('notifications').push().set({
          'type': 'ISSUE_UPDATE',
          'title': 'Truck Issue ${newStatus.replaceAll('_', ' ')}',
          'message': 'Your report regarding ${item['issueType']} has been updated to ${newStatus.replaceAll('_', ' ')}.',
          'truck_id': item['truckId'],
          'targetUserId': item['driverId']?.toString(), // ADDED targeting current driver
          'targetRole': 'driver',
          'relatedId': item['id'],
          'timestamp': ServerValue.timestamp,
          'isRead': false,
        });
      }
      
      if (mounted) {
        Navigator.pop(context);
        String msg = newStatus == 'RESOLVED' ? "Report successfully resolved!" : "Report marked as in progress.";
        CustomNotification.showTopNotification(context, msg, false);
      }
    } catch (e) {
      if (mounted) CustomNotification.showTopNotification(context, "Error: $e", true);
    }
  }

  Future<bool> _showConfirmDialog({required String title, required String message}) async {
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
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5)),
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
                        child: const Text("NO", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text("YES, PROCEED", style: TextStyle(fontWeight: FontWeight.w900)),
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
}

class _CuteDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final bool isMobile;
  const _CuteDatePicker({super.key, required this.initialDate, required this.isMobile});

  @override
  State<_CuteDatePicker> createState() => _CuteDatePickerState();
}

class _CuteDatePickerState extends State<_CuteDatePicker> {
  late DateTime _selectedDate;
  late DateTime _viewMonth;
  bool _isYearPickerVisible = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _viewMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.isMobile ? const BorderRadius.vertical(top: Radius.circular(32)) : BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isMobile) Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)))),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select Date", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                  const SizedBox(height: 4),
                  Text(widget.isMobile ? "Pick a date to filter." : "Choose a specific date to filter reports.", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ],
          ),
          const Divider(height: 48),
          
          if (!_isYearPickerVisible) ...[
            // MONTH & NAVIGATION
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isYearPickerVisible = true),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      children: [
                        Text(DateFormat('MMMM yyyy').format(_viewMonth), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF455A64), fontSize: 16)),
                        const Icon(Icons.arrow_drop_down_rounded, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1))),
                    IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // CALENDAR GRID
            Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(primary: Color(0xFF00897B), onPrimary: Colors.white, onSurface: Color(0xFF1A1A1A)),
              ),
              child: SizedBox(
                height: 300,
                child: CalendarDatePicker(
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  onDateChanged: (date) => setState(() => _selectedDate = date),
                ),
              ),
            ),
          ] else ...[
            // YEAR GRID
            GestureDetector(
              onTap: () => setState(() => _isYearPickerVisible = false),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Text(DateFormat('MMMM yyyy').format(_viewMonth), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF455A64), fontSize: 16)),
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
                child: TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey, padding: const EdgeInsets.symmetric(vertical: 16)),
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

  Widget _buildYearGrid() {
    final List<int> years = List.generate(12, (index) => 2020 + index); 
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, mainAxisSpacing: 20, crossAxisSpacing: 20, childAspectRatio: 2.2,
      ),
      itemCount: years.length,
      itemBuilder: (context, index) {
        final int year = years[index];
        final bool isSelected = year == _viewMonth.year;
        return InkWell(
          onTap: () {
            setState(() {
              _viewMonth = DateTime(year, _viewMonth.month);
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
}
