import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Real-time stats variables
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

  Future<void> _fetchDashboardStats() async {
    final supabase = Supabase.instance.client;
    final String today = DateTime.now().toIso8601String().split('T')[0];

    try {
      final students = await supabase.from('students').select('id');
      final batches = await supabase.from('batches').select('id');

      // Aaj ki overall attendance
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

  Widget _getAdminScreen(bool isDesktop) {
    switch (_selectedIndex) {
      case 0:
        return _buildAdminView(context, isDesktop);
      case 1:
        return const StudentsTab();
      case 2:
        return const BatchesTab();
      case 3:
        return const AdminAttendanceTab();
      default:
        return _buildAdminView(context, isDesktop);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 600;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('FG Academy Portal'),
            actions: [
              // Refresh button stats update karne k liye
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
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: Text(
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
          body: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/school_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.25,
              ),
            ),
            child: Row(
              children: [
                if (isDesktop && widget.userRole == 'admin')
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (int index) =>
                        setState(() => _selectedIndex = index),
                    extended: constraints.maxWidth > 800,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard),
                        label: Text('Dashboard'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.people),
                        label: Text('Students'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.class_),
                        label: Text('Batches'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.fact_check),
                        label: Text('Attendance'),
                      ),
                    ],
                  ),
                if (isDesktop && widget.userRole == 'admin')
                  const VerticalDivider(thickness: 1, width: 1),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: widget.userRole == 'admin'
                        ? _getAdminScreen(isDesktop)
                        : const TeacherBatchesScreen(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ListTile _buildDrawerItem(IconData icon, String title, int index) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: _selectedIndex == index,
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.pop(context); // Mobile par drawer close karne k liye
      },
    );
  }

  Widget _buildAdminView(BuildContext context, bool isDesktop) {
    if (_isLoadingStats) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Admin Overview',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
              // Cards ko direct respective screen par index map kar diya
              _buildStatCard(
                'Total Students',
                _totalStudents.toString(),
                Colors.blue,
                1,
              ),
              _buildStatCard(
                'Active Batches',
                _totalBatches.toString(),
                Colors.orange,
                2,
              ),
              _buildStatCard(
                'Today Present',
                _todayPresent.toString(),
                Colors.green,
                3,
              ),
              _buildStatCard('Absents', _todayAbsent.toString(), Colors.red, 3),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    int targetIndex,
  ) {
    return InkWell(
      onTap: () => setState(() => _selectedIndex = targetIndex),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
