import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import 'login_screen.dart';
import 'teacher_batches_screen.dart';
import 'admin/students_tab.dart';
import 'admin/batches_tab.dart';
import 'admin/admin_attendance_tab.dart';

class DashboardScreen extends StatefulWidget {
  final String userRole;
  const DashboardScreen({super.key, required this.userRole});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  Widget? activeSubScreen;

  int _totalStudents = 0;
  int _totalBatches = 0;
  int _todayPresent = 0;
  int _todayAbsent = 0;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    if (widget.userRole == 'admin') {
      _fetchDashboardStats();
    }
  }

  void _navigateToSubScreen(Widget screen) {
    setState(() {
      activeSubScreen = screen;
    });
  }

  void _selectSidebarItem(int index) {
    setState(() {
      _selectedIndex = index;
      activeSubScreen = null;
    });
  }

  Future<void> _fetchDashboardStats() async {
    final supabase = Supabase.instance.client;
    final String today = DateTime.now().toIso8601String().split('T')[0];

    try {
      final students = await supabase.from('students').select('id');
      final batches = await supabase.from('batches').select('id');

      final todayAttendance = await supabase
          .from('attendance')
          .select('status')
          .eq('date', today);

      int presentCount = 0;
      int absentCount = 0;
      for (var record in todayAttendance) {
        if (record['status'] == 'present') presentCount++;
        if (record['status'] == 'absent') absentCount++;
      }

      if (mounted) {
        setState(() {
          _totalStudents = students.length;
          _totalBatches = batches.length;
          _todayPresent = presentCount;
          _todayAbsent = absentCount;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  void _logout(BuildContext context) {
    Hive.box('settings').put('isLoggedIn', false);
    Hive.box('settings').put('role', '');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Widget _getAdminScreen(bool isDesktop, {Function(Widget)? onNavigate}) {
    switch (_selectedIndex) {
      case 0:
        return _buildAdminView(context, isDesktop);
      case 1:
        return StudentsTab(onNavigate: onNavigate);
      case 2:
        return const BatchesTab();
      case 3:
        return AdminAttendanceTab(onNavigate: onNavigate);
      default:
        return _buildAdminView(context, isDesktop);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 800;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: isDesktop
              ? null
              : AppBar(
                  title: const Text('FG Academy Portal'),
                  actions: [
                    if (widget.userRole == 'admin' && _selectedIndex == 0)
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          setState(() => _isLoadingStats = true);
                          _fetchDashboardStats();
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () => _logout(context),
                    ),
                  ],
                ),
          drawer: (!isDesktop && widget.userRole == 'admin')
              ? Drawer(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      DrawerHeader(
                        decoration: const BoxDecoration(
                          color: AppTheme.fgNavyBlue,
                        ),
                        child: const Text(
                          'Admin Menu',
                          style: TextStyle(color: Colors.white, fontSize: 24),
                        ),
                      ),
                      _buildDrawerItem(Icons.dashboard, 'Dashboard', 0),
                      _buildDrawerItem(Icons.people, 'Students', 1),
                      _buildDrawerItem(Icons.class_, 'Batches', 2),
                      _buildDrawerItem(Icons.fact_check, 'Attendance', 3),
                    ],
                  ),
                )
              : null,
          bottomNavigationBar: !isDesktop && widget.userRole == 'admin'
              ? NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) =>
                      _selectSidebarItem(index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Dashboard',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: 'Students',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.class_outlined),
                      selectedIcon: Icon(Icons.class_),
                      label: 'Batches',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.fact_check_outlined),
                      selectedIcon: Icon(Icons.fact_check),
                      label: 'Attendance',
                    ),
                  ],
                )
              : null,
          body: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/school_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.18,
              ),
            ),
            child: isDesktop && widget.userRole == 'admin'
                ? Row(
                    children: [
                      _buildSidebar(context),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child:
                              activeSubScreen ??
                              _getAdminScreen(
                                true,
                                onNavigate: _navigateToSubScreen,
                              ),
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: widget.userRole == 'admin'
                        ? _getAdminScreen(false)
                        : const TeacherBatchesScreen(),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final entries = [
      {'title': 'Dashboard', 'icon': Icons.dashboard, 'index': 0},
      {'title': 'Students', 'icon': Icons.people, 'index': 1},
      {'title': 'Batches', 'icon': Icons.class_, 'index': 2},
      {'title': 'Attendance', 'icon': Icons.fact_check, 'index': 3},
    ];

    return Container(
      width: 250,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTheme.fgNavyBlue,
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.16),
            blurRadius: 14,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text(
            'FG Academy',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Portal',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          ...entries.map((entry) {
            final index = entry['index'] as int;
            final selected = _selectedIndex == index;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  entry['icon'] as IconData,
                  color: selected ? Colors.white : Colors.white70,
                ),
                title: Text(
                  entry['title'] as String,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
                selected: selected,
                selectedTileColor: Colors.white24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => _selectSidebarItem(index),
              ),
            );
          }),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout, color: AppTheme.fgNavyBlue),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.fgNavyBlue,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ListTile _buildDrawerItem(IconData icon, String title, int index) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: _selectedIndex == index,
      onTap: () {
        _selectSidebarItem(index);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildAdminView(BuildContext context, bool isDesktop) {
    if (_isLoadingStats) {
      return const Center(child: CircularProgressIndicator());
    }

    final cardTextSize = isDesktop ? 18.0 : 16.0;
    final cardValueSize = isDesktop ? 38.0 : 32.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Admin Overview',
          style: TextStyle(
            fontSize: isDesktop ? 30 : 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.fgNavyBlue,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.count(
            crossAxisCount: isDesktop ? 4 : 2,
            shrinkWrap: true,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: isDesktop ? 1.5 : 1.2,
            children: [
              _buildStatCard(
                'Total Students',
                _totalStudents.toString(),
                const [Color(0xFFDBF4FF), Color(0xFF1F7AE0)],
                1,
                cardTextSize,
                cardValueSize,
              ),
              _buildStatCard(
                'Active Batches',
                _totalBatches.toString(),
                const [Color(0xFFFFE2C6), Color(0xFFEF8A2C)],
                2,
                cardTextSize,
                cardValueSize,
              ),
              _buildStatCard(
                'Today Present',
                _todayPresent.toString(),
                const [Color(0xFFDCFCE7), Color(0xFF22C55E)],
                3,
                cardTextSize,
                cardValueSize,
              ),
              _buildStatCard(
                'Absents',
                _todayAbsent.toString(),
                const [Color(0xFFFEE2E2), Color(0xFFEF4444)],
                3,
                cardTextSize,
                cardValueSize,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    List<Color> gradientColors,
    int targetIndex,
    double titleSize,
    double valueSize,
  ) {
    return InkWell(
      onTap: () => _selectSidebarItem(targetIndex),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: titleSize,
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: valueSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
