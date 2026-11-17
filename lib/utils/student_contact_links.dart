String? studentWhatsAppNumber(String raw) {
  var number = raw.trim().replaceAll(RegExp(r'[\s()\-]'), '');
  if (number.startsWith('00')) number = '+${number.substring(2)}';
  if (number.startsWith('0')) number = '+92${number.substring(1)}';
  if (RegExp(r'^3[0-9]{9}$').hasMatch(number)) number = '+92$number';
  if (!RegExp(r'^\+?[1-9][0-9]{9,14}$').hasMatch(number)) return null;
  return number.replaceFirst(RegExp(r'^\+'), '');
}

Uri? studentCallLink(String raw) {
  final phone = raw.trim().replaceAll(RegExp(r'[\s()\-]'), '');
  return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)
      ? Uri(scheme: 'tel', path: phone)
      : null;
}

Uri? studentWhatsAppLink(String raw, {String? message}) {
  final phone = studentWhatsAppNumber(raw);
  return phone == null
      ? null
      : Uri.https(
          'wa.me',
          '/$phone',
          message == null ? null : {'text': message},
        );
}

String? studentGroupInviteLink(String raw) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'chat.whatsapp.com' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      uri.pathSegments.length == 1 &&
      RegExp(r'^[A-Za-z0-9_-]{20,64}$').hasMatch(uri.pathSegments.single)) {
    return Uri.https(
      'chat.whatsapp.com',
      '/${uri.pathSegments.single}',
    ).toString();
  }
  // The existing automation stores an invite code in whatsapp_group_id.
  // Numeric IDs and @g.us group identifiers are not invitation codes.
  if (RegExp(r'^[A-Za-z0-9_-]{20,64}$').hasMatch(value) &&
      RegExp(r'[A-Za-z]').hasMatch(value)) {
    return Uri.https('chat.whatsapp.com', '/$value').toString();
  }
  return null;
}
