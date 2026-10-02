import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'award_lists_screen.dart';
import '../app_theme.dart';
import '../services/auth_service.dart';
import '../utils/automation_launcher.dart';
import '../utils/dashboard_section_header.dart';
import '../utils/error_state_view.dart';
import '../utils/list_sorting.dart';
import '../widgets/academy_background.dart';
import 'admin/admin_attendance_tab.dart';
import 'admin/batches_tab.dart';
import 'admin/fees/fees_tab.dart';
import 'admin/students_tab.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'teacher_batches_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String userRole;

  const DashboardScreen({super.key, required this.userRole});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex = 0;

  Widget? _activeSubScreen;

  int _totalStudents = 0;
  int _totalBatches = 0;

  List<Map<String, dynamic>> _batchStrengths = [];

  bool _isLoadingStats = true;

  String? _statsError;

  bool get _isAdmin => widget.userRole == 'admin';

  List<_NavigationItem> get _items {
    if (_isAdmin) {
      return const [
        _NavigationItem(
          index: 0,
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
        ),
        _NavigationItem(
          index: 1,
          label: 'Students',
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
        ),
        _NavigationItem(
          index: 2,
          label: 'Batches',
          icon: Icons.class_outlined,
          selectedIcon: Icons.class_rounded,
        ),
        _NavigationItem(
          index: 3,
          label: 'Attendance',
          icon: Icons.fact_check_outlined,
          selectedIcon: Icons.fact_check_rounded,
        ),
        _NavigationItem(
          index: 4,
          label: 'Fees',
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments_rounded,
        ),
        _NavigationItem(
          index: 5,
          label: 'Award Lists',
          icon: Icons.emoji_events_outlined,
          selectedIcon: Icons.emoji_events_rounded,
        ),
      ];
    }

    return const [
      _NavigationItem(
        index: 0,
        label: 'My Batches',
        icon: Icons.folder_open_outlined,
        selectedIcon: Icons.folder_rounded,
      ),
      _NavigationItem(
        index: 1,
        label: 'Award Lists',
        icon: Icons.emoji_events_outlined,
        selectedIcon: Icons.emoji_events_rounded,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();

    if (_isAdmin) {
      _fetchDashboardStats();
    }
  }

  void _selectSection(int index) {
    setState(() {
      _selectedIndex = index;
      _activeSubScreen = null;
    });

    if (_isAdmin && index == 0) {
      _refreshStats();
    }
  }

  void _navigateToSubScreen(Widget screen) {
    setState(() {
      _activeSubScreen = screen;
    });
  }

  void _closeSubScreen() {
    setState(() {
      _activeSubScreen = null;
    });
  }

  void _openProfile() {
    setState(() {
      _activeSubScreen = null;
      _selectedIndex = _isAdmin ? 6 : 2;
    });
  }

  Future<void> _refreshStats() async {
    if (mounted) {
      setState(() {
        _isLoadingStats = true;
        _statsError = null;
      });
    }

    await _fetchDashboardStats();
  }

  Future<void> _fetchDashboardStats() async {
    final supabase = Supabase.instance.client;

    try {
      final results = await Future.wait([
        supabase.from('students').select('id, batch_id'),
        supabase.from('batches').select('id, name, class_level'),
      ]);

      final students = results[0];

      final batches = results[1];

      final strengths = <String, int>{};

      for (final student in students) {
        final id = student['batch_id']?.toString();

        if (id != null) {
          strengths[id] = (strengths[id] ?? 0) + 1;
        }
      }

      final mapped = batches.map<Map<String, dynamic>>((batch) {
        final id = batch['id'].toString();

        return {
          'id': id,
          'name': batch['name']?.toString() ?? 'Batch',
          'class_level': (batch['class_level'] as num?)?.toInt() ?? 0,
          'strength': strengths[id] ?? 0,
        };
      }).toList();

      final sorted = sortBatches(mapped);

      if (!mounted) return;

      setState(() {
        _totalStudents = students.length;

        _totalBatches = batches.length;

        _batchStrengths = sorted
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

        _isLoadingStats = false;

        _statsError = null;
      });
    } catch (e) {
      debugPrint('Dashboard stats error: $e');

      if (!mounted) return;

      setState(() {
        _isLoadingStats = false;

        _statsError = 'Unable to load academy statistics.';
      });
    }
  }

  Future<void> _logout() async {
    try {
      await AuthService().signOut();

      final box = Hive.box('settings');

      await box.put('isLoggedIn', false);

      await box.put('role', '');

      await box.put('username', '');
    } catch (e) {
      debugPrint('Logout error: $e');

      if (!mounted) return;

      _showMessage('Could not log out.', error: true);

      return;
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _startAutomation() async {
    final started = await launchAutomation();

    if (!mounted) return;

    _showMessage(
      started
          ? 'WhatsApp report automation started.'
          : 'Automation could not start.',
      error: !started,
    );
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  Widget _profile() {
    return ProfileScreen(
      userRole: widget.userRole,
      onChangePassword: () {
        _showMessage('Change Password will be connected later.');
      },
      onLogout: _logout,
    );
  }

  Widget _screen({required bool desktopMode}) {
    if (_isAdmin) {
      if (_activeSubScreen != null) {
        return _activeSubScreen!;
      }

      switch (_selectedIndex) {
        case 0:
          return _adminDashboard();

        case 1:
          return StudentsTab(
            onNavigate: desktopMode ? _navigateToSubScreen : null,
            onBack: desktopMode ? _closeSubScreen : null,
          );

        case 2:
          return const BatchesTab();

        case 3:
          return AdminAttendanceTab(
            onNavigate: desktopMode ? _navigateToSubScreen : null,
            onBack: desktopMode ? _closeSubScreen : null,
          );

        case 4:
          return const FeesTab();

        case 5:
          return AwardListsScreen(userRole: widget.userRole);

        case 6:
          return _profile();

        default:
          return _adminDashboard();
      }
    }

    switch (_selectedIndex) {
      case 0:
        return const TeacherBatchesScreen();

      case 1:
        return AwardListsScreen(userRole: widget.userRole);

      case 2:
        return _profile();

      default:
        return const TeacherBatchesScreen();
    }
  }

  String get _currentTitle {
    if (_isAdmin && _selectedIndex == 6) {
      return 'Profile';
    }

    if (!_isAdmin && _selectedIndex == 2) {
      return 'Profile';
    }

    for (final item in _items) {
      if (item.index == _selectedIndex) {
        return item.label;
      }
    }

    return 'FG Academy';
  }

  int get _mobileAdminIndex {
    switch (_selectedIndex) {
      case 0:
        return 0;

      case 1:
        return 1;

      case 3:
        return 2;

      case 4:
        return 3;

      case 6:
        return 4;

      case 2:
        return 0;

      default:
        return 0;
    }
  }

  void _selectMobileAdmin(int index) {
    switch (index) {
      case 0:
        _selectSection(0);
        break;

      case 1:
        _selectSection(1);
        break;

      case 2:
        _selectSection(3);
        break;

      case 3:
        _selectSection(4);
        break;

      case 4:
        _openProfile();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final desktop = width >= 1180;

        final tablet = width >= 720 && width < 1180;

        final mobile = width < 720;

        final content = AcademyBackground(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 3 : 10,
              mobile ? 3 : 7,
              mobile ? 3 : 10,
              mobile ? 3 : 8,
            ),
            child: _screen(desktopMode: !mobile),
          ),
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppTheme.backgroundLight,
          appBar: mobile
              ? AppBar(
                  toolbarHeight: 50,
                  title: Text(_currentTitle),
                  leading: IconButton(
                    tooltip: 'Menu',
                    onPressed: () {
                      _scaffoldKey.currentState?.openDrawer();
                    },
                    icon: const Icon(Icons.menu_rounded),
                  ),
                  actions: [
                    if (_isAdmin && _selectedIndex == 0)
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _isLoadingStats ? null : _refreshStats,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                  ],
                )
              : null,
          drawer: mobile ? _mobileDrawer() : null,
          bottomNavigationBar: mobile ? _mobileNavigation() : null,
          body: desktop
              ? Row(
                  children: [
                    _desktopSidebar(),
                    Expanded(child: content),
                  ],
                )
              : tablet
              ? Row(
                  children: [
                    _tabletRail(),
                    Expanded(child: content),
                  ],
                )
              : content,
        );
      },
    );
  }

  Widget _desktopSidebar() {
    final username = Hive.box(
      'settings',
    ).get('username', defaultValue: _isAdmin ? 'admin' : 'teacher').toString();

    return Container(
      width: 278,
      decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.fgGold, width: 2),
                    ),
                    child: Image.asset('assets/images/app_logo_bg.png'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'FG ACADEMY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'Evening Coaching Classes',
                    style: TextStyle(
                      color: AppTheme.fgGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 2,
                    width: 120,
                    decoration: const BoxDecoration(
                      gradient: AppTheme.goldGradient,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                children: _items.map((item) {
                  final selected = _selectedIndex == item.index;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Material(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.13)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _selectSection(item.index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected ? item.selectedIcon : item.icon,
                                color: selected
                                    ? AppTheme.fgGold
                                    : Colors.white70,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(13),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _openProfile,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.fgGold,
                                foregroundColor: AppTheme.fgNavyBlue,
                                child: Text(
                                  username.isEmpty
                                      ? '?'
                                      : username[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      _isAdmin ? 'Administrator' : 'Teacher',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white60,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Logout',
                    onPressed: _logout,
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.white70,
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

  Widget _tabletRail() {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      labelType: NavigationRailLabelType.all,
      minWidth: 82,
      groupAlignment: -0.75,
      leading: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 18),
        child: Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.fgGold),
          ),
          child: Image.asset('assets/images/app_logo_bg.png'),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Profile',
                  onPressed: _openProfile,
                  icon: const Icon(
                    Icons.person_outline_rounded,
                    color: Colors.white70,
                  ),
                ),
                IconButton(
                  tooltip: 'Logout',
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
      onDestinationSelected: _selectSection,
      destinations: _items.map((item) {
        return NavigationRailDestination(
          icon: Icon(item.icon),
          selectedIcon: Icon(item.selectedIcon),
          label: Text(
            item.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _mobileDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
              child: Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppTheme.fgGold),
                    ),
                    child: Image.asset('assets/images/app_logo_bg.png'),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FG Academy',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Evening Coaching Classes',
                          style: TextStyle(
                            color: AppTheme.fgGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: _items.map((item) {
                  final selected = item.index == _selectedIndex;

                  return ListTile(
                    selected: selected,
                    selectedTileColor: AppTheme.fgNavyBlue.withValues(
                      alpha: 0.07,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    leading: Icon(
                      selected ? item.selectedIcon : item.icon,
                      color: selected
                          ? AppTheme.fgNavyBlue
                          : AppTheme.textSecondary,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    trailing: item.label == 'Award Lists'
                        ? const Text(
                            'SOON',
                            style: TextStyle(
                              color: AppTheme.fgGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.of(context).pop();

                      _selectSection(item.index);
                    },
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: _mobileAccountCard(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileNavigation() {
    if (!_isAdmin) {
      return NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectSection,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Batches',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded),
            label: 'Awards',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      );
    }

    return NavigationBar(
      selectedIndex: _mobileAdminIndex,
      onDestinationSelected: _selectMobileAdmin,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline_rounded),
          selectedIcon: Icon(Icons.people_rounded),
          label: 'Students',
        ),
        NavigationDestination(
          icon: Icon(Icons.fact_check_outlined),
          selectedIcon: Icon(Icons.fact_check_rounded),
          label: 'Attendance',
        ),
        NavigationDestination(
          icon: Icon(Icons.payments_outlined),
          selectedIcon: Icon(Icons.payments_rounded),
          label: 'Fees',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    );
  }

  Widget _mobileAccountCard() {
    final username = Hive.box(
      'settings',
    ).get('username', defaultValue: _isAdmin ? 'admin' : 'teacher').toString();

    return Material(
      color: AppTheme.fgNavyBlue.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () {
          Navigator.of(context).pop();

          _openProfile();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.fgGold,
                foregroundColor: AppTheme.fgNavyBlue,
                child: Text(
                  username.isEmpty ? '?' : username[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _isAdmin ? 'Administrator' : 'Teacher',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adminDashboard() {
    if (_statsError != null && !_isLoadingStats) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: DashboardSectionHeader(
              title: 'Administration Dashboard',
              subtitle: 'Academy operations overview',
              trailing: IconButton(
                color: Colors.white,
                onPressed: _refreshStats,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
          SliverFillRemaining(
            child: ErrorStateView(
              message: _statsError!,
              onRetry: _refreshStats,
            ),
          ),
        ],
      );
    }

    final average = _totalBatches == 0 ? 0.0 : _totalStudents / _totalBatches;

    return RefreshIndicator(
      onRefresh: _refreshStats,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: DashboardSectionHeader(
              title: 'Administration Dashboard',
              subtitle: DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now()),
              trailing: IconButton(
                color: Colors.white,
                onPressed: _isLoadingStats ? null : _refreshStats,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
          if (_isLoadingStats)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 26),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 920
                          ? 3
                          : constraints.maxWidth >= 560
                          ? 2
                          : 1;

                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: columns == 1 ? 2.55 : 2.15,
                        children: [
                          _MetricCard(
                            title: 'Active Students',
                            value: '$_totalStudents',
                            subtitle: 'Current academy roster',
                            icon: Icons.groups_2_rounded,
                            color: AppTheme.info,
                          ),
                          _MetricCard(
                            title: 'Academy Batches',
                            value: '$_totalBatches',
                            subtitle: 'Classes 9 to 12',
                            icon: Icons.school_rounded,
                            color: AppTheme.fgNavyBlue,
                          ),
                          _MetricCard(
                            title: 'Average Strength',
                            value: average.toStringAsFixed(1),
                            subtitle: 'Students per batch',
                            icon: Icons.analytics_rounded,
                            color: AppTheme.success,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _strengthCard(),
                  if (isWindowsPlatform) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 17,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF25D366,
                            ).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const FaIcon(
                            FontAwesomeIcons.whatsapp,
                            color: Color(0xFF19984B),
                            size: 25,
                          ),
                        ),
                        title: const Text(
                          'WhatsApp Attendance Reports',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: const Text(
                          'Launch the Windows reporting automation.',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _startAutomation,
                      ),
                    ),
                  ],
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _strengthCard() {
    final maximum = _batchStrengths.isEmpty
        ? 1
        : _batchStrengths
              .map((item) => (item['strength'] as num?)?.toInt() ?? 0)
              .fold<int>(
                1,
                (previous, current) => current > previous ? current : previous,
              );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  color: AppTheme.fgNavyBlue,
                  size: 27,
                ),
                SizedBox(width: 9),
                Text(
                  'Batch Strength',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._batchStrengths.map((batch) {
              final strength = (batch['strength'] as num?)?.toInt() ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            batch['name']?.toString() ?? 'Batch',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 52),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppTheme.goldGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$strength',
                            style: const TextStyle(
                              color: AppTheme.fgNavyBlue,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: strength / maximum,
                        minHeight: 9,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _NavigationItem {
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _NavigationItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border(top: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 31),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 36,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
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
}
