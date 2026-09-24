import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import 'login_screen.dart';
import 'teacher_batches_screen.dart';
import 'admin/students_tab.dart';
import 'admin/batches_tab.dart';
import 'admin/admin_attendance_tab.dart';
import '../utils/automation_launcher.dart';
import '../utils/error_state_view.dart';
import '../utils/dashboard_section_header.dart';

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
  List<Map<String, dynamic>> _batchStrengths = [];
  bool _isLoadingStats = true;
  String? _statsError;

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

  void _closeSubScreen() {
    setState(() => activeSubScreen = null);
  }

  void _selectSidebarItem(int index) {
    setState(() {
      _selectedIndex = index;
      activeSubScreen = null;
    });
  }

  Future<void> _fetchDashboardStats() async {
    final supabase = Supabase.instance.client;

    try {
      final students = await supabase.from('students').select('id');
      final batches = await supabase.from('batches').select('id, name');
      final studentsWithBatches = await supabase
          .from('students')
          .select('batch_id');

      final strengthByBatch = <String, int>{};
      for (final student in studentsWithBatches) {
        final batchId = student['batch_id']?.toString();
        if (batchId != null) {
          strengthByBatch[batchId] = (strengthByBatch[batchId] ?? 0) + 1;
        }
      }

      final batchStrengths = batches.map<Map<String, dynamic>>((batch) {
        final batchId = batch['id'].toString();
        return {
          'name': batch['name']?.toString() ?? 'Batch',
          'strength': strengthByBatch[batchId] ?? 0,
        };
      }).toList();
      batchStrengths.sort(
        (first, second) =>
            first['name'].toString().compareTo(second['name'].toString()),
      );

      if (mounted) {
        setState(() {
          _totalStudents = students.length;
          _totalBatches = batches.length;
          _batchStrengths = batchStrengths;
          _isLoadingStats = false;
          _statsError = null;
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
          _statsError =
              'Unable to load dashboard statistics. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await Hive.box('settings').put('isLoggedIn', false);
      await Hive.box('settings').put('role', '');
    } catch (e) {
      debugPrint('Logout storage error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not log out safely. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Future<void> _startAutomation() async {
    final started = await launchAutomation();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          started
              ? 'Automation Started'
              : 'Automation could not start. Check the backend file and Windows setup.',
        ),
        backgroundColor: started ? Colors.green : Colors.red,
      ),
    );
  }

  void _showChangePasswordMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Change password will be available soon.')),
    );
  }

  Widget _getAdminScreen(bool isDesktop, {Function(Widget)? onNavigate}) {
    switch (_selectedIndex) {
      case 0:
        return _buildAdminView(context, isDesktop);
      case 1:
        return StudentsTab(onNavigate: onNavigate, onBack: _closeSubScreen);
      case 2:
        return const BatchesTab();
      case 3:
        return AdminAttendanceTab(
          onNavigate: onNavigate,
          onBack: _closeSubScreen,
        );
      default:
        return _buildAdminView(context, isDesktop);
    }
  }

  String get _currentSectionTitle {
    if (widget.userRole != 'admin') return 'My Batches';
    switch (_selectedIndex) {
      case 1:
        return 'Students';
      case 2:
        return 'Batches';
      case 3:
        return 'Attendance';
      default:
        return 'Dashboard';
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
                  title: Text(_currentSectionTitle),
                  actions: [
                    if (widget.userRole == 'admin' && _selectedIndex == 0)
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          setState(() => _isLoadingStats = true);
                          _fetchDashboardStats();
                        },
                      ),
                  ],
                ),
          drawer: !isDesktop
              ? Drawer(
                  child: SafeArea(
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              DrawerHeader(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.fgNavyBlue,
                                      Color(0xFF174A86),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Image.asset(
                                      'assets/images/app_logo_bg.png',
                                      width: 58,
                                      height: 58,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'FG Academy Portal',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.userRole == 'admin') ...[
                                _buildDrawerItem(
                                  Icons.dashboard,
                                  'Dashboard',
                                  0,
                                ),
                                _buildDrawerItem(Icons.people, 'Students', 1),
                                _buildDrawerItem(Icons.class_, 'Batches', 2),
                                _buildDrawerItem(
                                  Icons.fact_check,
                                  'Attendance',
                                  3,
                                ),
                              ] else
                                _buildDrawerItem(
                                  Icons.folder_open,
                                  'My Batches',
                                  0,
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _showChangePasswordMessage,
                                icon: const Icon(Icons.lock_reset),
                                label: const Text('Change Password'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _logout(context),
                                icon: const Icon(Icons.logout),
                                label: const Text('Logout'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
            child: isDesktop
                ? Row(
                    children: [
                      _buildSidebar(
                        context,
                        teacherOnly: widget.userRole != 'admin',
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: widget.userRole == 'admin'
                              ? activeSubScreen ??
                                    _getAdminScreen(
                                      true,
                                      onNavigate: _navigateToSubScreen,
                                    )
                              : const TeacherBatchesScreen(),
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

  Widget _buildSidebar(BuildContext context, {bool teacherOnly = false}) {
    final entries = teacherOnly
        ? [
            {'title': 'My Batches', 'icon': Icons.folder_open, 'index': 0},
          ]
        : [
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
          Center(
            child: Image.asset(
              'assets/images/app_logo_bg.png',
              width: 88,
              height: 88,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'FG Academy Portal',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
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
          OutlinedButton.icon(
            onPressed: _showChangePasswordMessage,
            icon: const Icon(Icons.lock_reset, color: Colors.white),
            label: const Text('Change Password'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 8),
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
    if (_statsError != null) {
      return ErrorStateView(
        message: _statsError!,
        onRetry: () {
          setState(() => _isLoadingStats = true);
          _fetchDashboardStats();
        },
      );
    }

    final cardTextSize = isDesktop ? 18.0 : 16.0;
    final cardValueSize = isDesktop ? 38.0 : 32.0;
    final batchCards = _batchStrengths.asMap().entries.map((entry) {
      final colors = [
        const [Color(0xFFE0F2FE), Color(0xFF0284C7)],
        const [Color(0xFFFEF3C7), Color(0xFFD97706)],
        const [Color(0xFFDCFCE7), Color(0xFF16A34A)],
        const [Color(0xFFFCE7F3), Color(0xFFDB2777)],
      ][entry.key % 4];
      final batch = entry.value;
      return _buildStatCard(
        '${batch['name']} Students',
        batch['strength'].toString(),
        colors,
        1,
        cardTextSize,
        cardValueSize,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionHeader(
          title: 'Dashboard',
          subtitle: 'Academy overview and today\'s attendance',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDesktop)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Tooltip(
                    message: 'Send WhatsApp Reports',
                    child: Material(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _startAutomation,
                        borderRadius: BorderRadius.circular(10),
                        child: const SizedBox(
                          width: 56,
                          height: 56,
                          child: Center(
                            child: FaIcon(
                              FontAwesomeIcons.whatsapp,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Refresh dashboard statistics',
                color: Colors.white,
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() => _isLoadingStats = true);
                  _fetchDashboardStats();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
              ...batchCards,
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
