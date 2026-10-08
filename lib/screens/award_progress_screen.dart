import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/portal_user.dart';
import '../services/award_progress_service.dart';
import '../utils/award_progress_image_generator.dart';

class AwardProgressScreen extends StatefulWidget {
  final SupabaseClient supabase;
  final PortalUser? user;

  final Map<String, dynamic> batch;

  final String subjectCode;

  final List<Map<String, dynamic>> tests;

  const AwardProgressScreen({
    super.key,
    required this.supabase,
    required this.user,
    required this.batch,
    required this.subjectCode,
    required this.tests,
  });

  @override
  State<AwardProgressScreen> createState() => _AwardProgressScreenState();
}

class _AwardProgressScreenState extends State<AwardProgressScreen> {
  final AwardProgressService _service = AwardProgressService();

  AwardProgressBundle? _bundle;

  Uint8List? _pngBytes;

  bool _loading = true;
  bool _sharing = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bundle = await _service.load(
        supabase: widget.supabase,
        user: widget.user,
        batch: widget.batch,
        subjectCode: widget.subjectCode,
        tests: widget.tests,
      );

      final png = await AwardProgressImageGenerator.generate(bundle);

      if (!mounted) return;

      setState(() {
        _bundle = bundle;
        _pngBytes = png;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Award progress error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Could not generate the progress sheet.';
      });
    }
  }

  Future<void> _share() async {
    final bytes = _pngBytes;

    final bundle = _bundle;

    if (bytes == null || bundle == null) {
      return;
    }

    setState(() {
      _sharing = true;
    });

    try {
      final directory = await getTemporaryDirectory();

      final batchName = bundle.batchName.replaceAll(
        RegExp(r'[^a-zA-Z0-9]+'),
        '_',
      );

      final file = File(
        '${directory.path}/'
        'FG_Progress_'
        '${batchName}_'
        '${bundle.subjectCode}.png',
      );

      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text:
              '${bundle.batchName} • '
              '${bundle.subjectName} '
              'Progress Sheet',
          subject:
              '${bundle.batchName} '
              'Progress Sheet',
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share progress PNG.\n$e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F4),
      appBar: AppBar(
        title: const Text('All Tests Progress'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 15),
                    ElevatedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_bundle != null)
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      '${_bundle!.batchName} • '
                      '${_bundle!.subjectName} • '
                      '${_bundle!.tests.length} tests',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.fgNavyBlue,
                      ),
                    ),
                  ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDE1E5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InteractiveViewer(
                        minScale: 0.25,
                        maxScale: 5,
                        boundaryMargin: const EdgeInsets.all(200),
                        child: Center(
                          child: Image.memory(
                            _pngBytes!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: AppTheme.border)),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _sharing ? null : _share,
                      icon: _sharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const FaIcon(FontAwesomeIcons.whatsapp, size: 17),
                      label: Text(
                        _sharing ? 'Opening...' : 'Share Progress PNG',
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
