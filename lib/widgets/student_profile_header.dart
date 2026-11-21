import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app_theme.dart';
import '../services/student_profile_service.dart';
import 'student_stream_badge.dart';

class StudentProfileHeader extends StatelessWidget {
  final StudentProfileData data;
  final bool desktop;
  final VoidCallback? onEdit, onCall, onWhatsApp, onInvite, onCopy;
  const StudentProfileHeader({
    super.key,
    required this.data,
    this.desktop = false,
    this.onEdit,
    this.onCall,
    this.onWhatsApp,
    this.onInvite,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final name = data.student['name']?.toString().trim() ?? '';
    final phone = data.student['contact_number']?.toString().trim() ?? '';
    final archived = data.student['is_archived'] == true;
    final classLevel = (data.batch['class_level'] as num?)?.toInt() ?? 0;
    final subjects = ((data.student['stream'] as List?) ?? const []).map(
      (item) => item.toString(),
    );
    final avatar = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.fgGold, width: 2),
      ),
      child: CircleAvatar(
        radius: desktop ? 48 : 34,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.fgNavyBlue,
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: TextStyle(
            fontSize: desktop ? 38 : 30,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    final identity = Column(
      crossAxisAlignment: desktop
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? 'Student' : name,
          textAlign: desktop ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          data.batch['name']?.toString() ?? 'Academy student',
          textAlign: desktop ? TextAlign.center : TextAlign.start,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 10),
        StudentStreamBadge(
          classLevel: classLevel,
          subjects: subjects,
          onDark: true,
        ),
        if (archived) ...[
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.archive_outlined, size: 14, color: AppTheme.fgGold),
                SizedBox(width: 5),
                Text(
                  'Archived',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('student-profile-identity'),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppTheme.fgNavyBlue.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.school_outlined,
                    color: AppTheme.fgGold,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'STUDENT PROFILE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onEdit != null)
                    IconButton(
                      onPressed: onEdit,
                      tooltip: 'Edit profile',
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (desktop) ...[
                Center(child: avatar),
                const SizedBox(height: 16),
                identity,
              ] else
                Row(
                  children: [
                    avatar,
                    const SizedBox(width: 16),
                    Expanded(child: identity),
                  ],
                ),
              if (onEdit != null) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                  label: const Text('Edit profile'),
                ),
              ],
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.contact_phone_outlined,
                        size: 20,
                        color: AppTheme.info,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Parent / guardian',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        phone.isEmpty ? 'No contact number' : phone,
                        style: TextStyle(
                          fontSize: phone.isEmpty ? 15 : 21,
                          fontWeight: FontWeight.w700,
                          color: phone.isEmpty
                              ? AppTheme.textSecondary
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (phone.isNotEmpty)
                      IconButton(
                        onPressed: onCopy,
                        tooltip: 'Copy contact number',
                        icon: const Icon(Icons.copy_outlined, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: phone.isEmpty ? null : onCall,
                        icon: const Icon(Icons.call_outlined, size: 18),
                        label: const Text('Call'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: phone.isEmpty ? null : onWhatsApp,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF147A4F),
                        ),
                        icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 17),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: phone.isEmpty ? null : onInvite,
                  icon: const Icon(Icons.group_add_outlined, size: 19),
                  label: const Text('Send group invite'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
