import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/fee_models.dart';
import '../models/portal_user.dart';
import '../services/award_share_service.dart';

class AwardListPreviewScreen extends StatefulWidget {
  final SupabaseClient supabase;

  final PortalUser? user;

  final Map<String, dynamic> batch;

  final Map<String, dynamic> test;

  final String subjectCode;

  const AwardListPreviewScreen({
    super.key,
    required this.supabase,
    required this.user,
    required this.batch,
    required this.test,
    required this.subjectCode,
  });

  @override
  State<AwardListPreviewScreen> createState() => _AwardListPreviewScreenState();
}

class _AwardListPreviewScreenState extends State<AwardListPreviewScreen> {
  final AwardShareService _shareService = AwardShareService();

  PreparedAwardShare? _prepared;

  bool _loading = true;
  bool _sharing = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _loadPreview();
  }

  Future<void> _loadPreview() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await _shareService.prepareAwardList(
        supabase: widget.supabase,
        user: widget.user,
        batch: widget.batch,
        test: widget.test,
        subjectCode: widget.subjectCode,
      );

      if (!mounted) return;

      setState(() {
        _prepared = result;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Award preview error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;

        _error =
            'Could not generate '
            'award-list preview.';
      });
    }
  }

  Future<void> _share() async {
    final prepared = _prepared;

    if (prepared == null) {
      return;
    }

    setState(() {
      _sharing = true;
    });

    try {
      await _shareService.sharePreparedAwardList(prepared);
    } catch (e) {
      debugPrint('Award sharing error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not share '
            'award-list PNG.\n$e',
          ),
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

  String get _testLabel {
    final number = (widget.test['test_no'] as num?)?.toInt() ?? 0;

    return 'T$number';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F5),

      appBar: AppBar(
        title: const Text('Award List Preview'),

        actions: [
          IconButton(
            tooltip: 'Regenerate Preview',
            onPressed: _loading ? null : _loadPreview,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),

      body: Column(
        children: [
          _buildInfoBar(),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildError()
                : _buildPreview(),
          ),

          if (!_loading && _error == null && _prepared != null)
            _buildShareBar(),
        ],
      ),
    );
  }

  Widget _buildInfoBar() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          _PreviewInfoChip(
            icon: Icons.class_outlined,
            label: widget.batch['name']?.toString() ?? 'Batch',
          ),

          _PreviewInfoChip(
            icon: Icons.menu_book_outlined,
            label: feeSubjectLabel(widget.subjectCode),
          ),

          _PreviewInfoChip(icon: Icons.assignment_outlined, label: _testLabel),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final prepared = _prepared!;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFDCE0E4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          minScale: 0.4,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(140),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Image.memory(
                prepared.pngBytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_not_supported_outlined,
              size: 54,
              color: AppTheme.danger,
            ),

            const SizedBox(height: 12),

            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _loadPreview,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareBar() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Pinch to zoom. '
                'This exact PNG '
                'will be shared.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(width: 10),

            ElevatedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const FaIcon(FontAwesomeIcons.whatsapp, size: 17),
              label: Text(_sharing ? 'Opening...' : 'Share PNG'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PreviewInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.fgNavyBlue),

          const SizedBox(width: 6),

          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
