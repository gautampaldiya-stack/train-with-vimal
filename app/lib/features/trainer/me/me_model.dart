import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';

/// Trainer → My profile (boards `TrainerMe` / `TrainerMeMobile`). One controller for the page: the profile with
/// its stats (`trainers/me/`, the same numbers as the dashboard and the admin Trainers table, D-30), documents and
/// What clients see. My activity and Account load their own lists.
///
/// With [id] it is the admin's Trainer profile (boards `TrainerProfile` / `TrainerProfileMobile`, D-48): the same
/// page for one trainer, read from `trainers/<id>/` (same shape as `trainers/me/`), with the admin tabs.
class MeController extends ChangeNotifier {
  MeController({String? tab, this.id}) {
    if (tab != null && tabList.any((t) => t.$1 == tab)) this.tab = tab;
  }

  /// The trainer's id when the admin looks at a trainer; null on the trainer's own My profile.
  final String? id;
  bool get admin => id != null;

  /// API base: `trainers/me` or `trainers/<id>`.
  String get api => admin ? 'trainers/$id' : 'trainers/me';

  static const adminTabs = [
    ('overview', 'Overview'),
    ('clients', 'Clients'),
    ('access', 'Access and permissions'),
    ('activity', 'Activity'),
    ('documents', 'Documents'),
    ('clients-see', 'What clients see'),
  ];

  /// The owner on their own My profile (admin is a trainer too, D-57): no "My access" tab, they have every right.
  bool get owner => !admin && Services.session.me?.role == Role.admin;

  List<(String, String)> get tabList => admin ? adminTabs : owner ? [for (final t in tabs) if (t.$1 != 'access') t] : tabs;

  /// Words for the admin's texts ("Clients who need him"); "you" on My profile.
  String get he => admin ? switch ('${me['gender'] ?? ''}') { 'female' => 'she', 'male' => 'he', _ => 'they' } : 'you';
  String get him => admin ? switch ('${me['gender'] ?? ''}') { 'female' => 'her', 'male' => 'him', _ => 'them' } : 'you';
  String get his => admin ? switch ('${me['gender'] ?? ''}') { 'female' => 'her', 'male' => 'his', _ => 'their' } : 'your';

  static const tabs = [
    ('overview', 'Overview'),
    ('documents', 'Documents'),
    ('clients-see', 'What clients see'),
    ('access', 'My access'),
    ('activity', 'My activity'),
    ('account', 'Account'),
  ];

  String tab = 'overview';
  Map<String, dynamic> me = {};
  List<Map<String, dynamic>> docs = [];
  Map<String, dynamic> vis = {};
  Map<String, dynamic> preview = {};
  bool loading = true;
  ApiError? error;
  int version = 0;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setTab(String t) {
    if (t == tab) return;
    tab = t;
    _notify();
  }

  Future<void> load() async {
    loading = true;
    _notify();
    try {
      final r = await Future.wait([
        Services.api.get<Map>('$api/'),
        Services.api.get<List>('$api/documents/'),
        Services.api.get<Map>('$api/visibility/'),
      ]);
      me = Map<String, dynamic>.from(r[0] as Map);
      docs = [for (final d in r[1] as List) Map<String, dynamic>.from(d as Map)];
      _setVis(r[2] as Map);
      error = null;
      version++;
    } on ApiError catch (e) {
      error = e;
    }
    loading = false;
    _notify();
  }

  Future<void> refresh() => load();

  Future<void> reloadMe() async {
    try {
      me = Map<String, dynamic>.from(await Services.api.get<Map>('$api/'));
      version++;
      _notify();
    } on ApiError catch (_) {}
  }

  void _setVis(Map v) {
    vis = Map<String, dynamic>.from((v['visibility'] as Map?) ?? const {});
    preview = Map<String, dynamic>.from((v['preview'] as Map?) ?? const {});
  }

  // ─────────────────────────────── Reads

  Map<String, dynamic> get profile => Map<String, dynamic>.from((me['profile'] as Map?) ?? const {});
  Map<String, dynamic> get stats => Map<String, dynamic>.from((me['stats'] as Map?) ?? const {});
  String get name => '${me['full_name'] ?? ''}';
  String get first => name.split(' ').first;
  String get initials => '${me['initials'] ?? ''}';
  String get color => '${me['avatar_color'] ?? 'c1'}';
  String? get avatar => me['avatar'] as String?;
  List<String> get speciality => [for (final s in (me['speciality'] as List?) ?? const []) '$s'];
  List<String> get languages => [for (final s in (profile['languages'] as List?) ?? const []) '$s'];
  int? get since => (profile['experience_since'] as num?)?.toInt();
  int? get years => since == null ? null : (DateTime.now().year - since!).clamp(0, 80);
  String get yearsText => years == null ? '' : '$years ${years == 1 ? 'year' : 'years'}';
  String get mode => switch ('${profile['mode'] ?? ''}') { 'gym' => 'Gym', 'online' => 'Online', _ => 'Gym and online' };
  String get gender => switch ('${me['gender'] ?? ''}') { 'male' => 'Male', 'female' => 'Female', 'other' => 'Other', _ => '' };
  String get accessLevel => switch ('${me['access_mode'] ?? ''}') { 'all' => 'All clients', 'custom' => 'Custom', _ => 'Assigned clients' };
  Map<String, dynamic>? get lastLogin => (me['last_login'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic>? get asked => (me['asked'] as Map?)?.cast<String, dynamic>();
  bool get seesAll => (me['permissions'] as Map?)?['clients.view_all'] == true;

  List<Map<String, dynamic>> get groups => [for (final g in (me['access_groups'] as List?) ?? const []) Map<String, dynamic>.from(g as Map)];
  int get permsOn => groups.fold(0, (a, g) => a + ((g['items'] as List).where((i) => (i as Map)['on'] == true).length));
  int get permsTotal => groups.fold(0, (a, g) => a + (g['items'] as List).length);

  /// "+91 98100 00002".
  String get phone => mePhone('${me['phone'] ?? ''}');

  /// Social links shown on the card (handle text only).
  List<(String, String)> get social => [
        if ('${profile['instagram'] ?? ''}'.isNotEmpty) ('instagram', '${profile['instagram']}'),
        if ('${profile['youtube'] ?? ''}'.isNotEmpty) ('youtube', meBareUrl('${profile['youtube']}')),
        if ('${profile['page_link'] ?? ''}'.isNotEmpty) ('facebook', meBareUrl('${profile['page_link']}')),
        if ('${profile['website'] ?? ''}'.isNotEmpty) ('web', meBareUrl('${profile['website']}')),
      ];

  // ─────────────────────────────── Documents

  List<Map<String, dynamic>> get certs => docs.where((d) => d['kind'] == 'certificate').toList();
  List<Map<String, dynamic>> get otherDocs => docs.where((d) => d['kind'] != 'certificate').toList();

  /// "6 files · 3 verified · 1 expiring soon · 1 not checked".
  String get docSummary {
    final n = docs.length;
    final v = docs.where((d) => d['status'] == 'verified' || d['status'] == 'signed').length;
    final soon = docs.where((d) => d['status'] == 'expires_soon').length;
    final exp = docs.where((d) => d['status'] == 'expired').length;
    final nc = docs.where((d) => d['status'] == 'not_checked').length;
    return [
      '$n ${n == 1 ? 'file' : 'files'}',
      '$v verified',
      if (soon > 0) '$soon expiring soon',
      if (exp > 0) '$exp expired',
      if (nc > 0) '$nc not checked',
    ].join(' · ');
  }

  /// Certificates card line: "3 of 4 verified · one expires soon".
  String get certSummary {
    final c = certs;
    if (c.isEmpty) return 'None added yet';
    final v = c.where((d) => d['status'] == 'verified').length;
    final soon = c.where((d) => d['status'] == 'expires_soon').length;
    final exp = c.where((d) => d['status'] == 'expired').length;
    return [
      '$v of ${c.length} verified',
      if (soon == 1) 'one expires soon' else if (soon > 1) '$soon expire soon',
      if (exp == 1) 'one has expired' else if (exp > 1) '$exp have expired',
    ].join(' · ');
  }

  void putDoc(Map<String, dynamic> d) {
    final i = docs.indexWhere((x) => x['id'] == d['id']);
    if (i >= 0) {
      docs[i] = d;
    } else {
      docs = [...docs, d]..sort(_docOrder);
    }
    _notify();
  }

  static int _docOrder(Map a, Map b) {
    final k = '${a['kind']}'.compareTo('${b['kind']}');
    return k != 0 ? k : '${a['name']}'.compareTo('${b['name']}');
  }

  void dropDoc(String id) {
    docs = docs.where((d) => d['id'] != id).toList();
    _notify();
  }

  // ─────────────────────────────── Writes

  Future<void> setVisible(String key, bool on) async {
    final old = Map<String, dynamic>.from(vis);
    vis = {...vis, key: on};
    _notify();
    try {
      _setVis(await Services.api.put<Map>('$api/visibility/', {key: on}));
      _notify();
    } on ApiError {
      vis = old;
      _notify();
      rethrow;
    }
  }

  Future<void> saveDetails(Map<String, dynamic> data) async {
    if (admin) {
      // trainers/<id>/ PATCH answers without the page extras: read the full page again.
      await Services.api.patch<Map>('$api/', data);
      me = Map<String, dynamic>.from(await Services.api.get<Map>('$api/'));
    } else {
      me = Map<String, dynamic>.from(await Services.api.patch<Map>('trainers/me/', data));
    }
    version++;
    _notify();
    // The preview card shows the new name, speciality and bio.
    try {
      _setVis(await Services.api.get<Map>('$api/visibility/'));
      _notify();
    } on ApiError catch (_) {}
  }

  Future<void> askAccess(List<String> perms, String reason) async {
    await Services.api.post('access-requests/', {'permissions': perms, 'reason': reason});
    await reloadMe();
  }
}

// ─────────────────────────────── Formatting

DateTime? meParse(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

String meDmy(Object? v) => meParse(v) == null ? '—' : DateFormat('d MMM yyyy').format(meParse(v)!);

/// Documents keep month precision: "Jun 2021".
String meMy(Object? v) => meParse(v) == null ? '' : DateFormat('MMM yyyy').format(meParse(v)!);

String meTime(Object? v) => meParse(v) == null ? '' : DateFormat('h:mm a').format(meParse(v)!).toLowerCase();

/// "+91 98201 55432" from "+919820155432".
String mePhone(String p) {
  var d = p.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length != 10) return p;
  return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
}

/// 10 digits for the Mobile field.
String meDigits(String p) {
  var d = p.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  return d;
}

/// "https://www.amanlifts.in/" → "amanlifts.in".
String meBareUrl(String u) => u.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '').replaceFirst(RegExp(r'/$'), '');

/// Day header in My activity: "Today", "Yesterday", "Mon, 5 Oct".
String meDayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(d.year == now.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy').format(d);
}

/// Document status → board badge text.
String meDocBadge(Map d) {
  switch ('${d['status']}') {
    case 'signed':
      return 'Signed';
    case 'verified':
      return 'Verified';
    case 'expired':
      return 'Expired';
    case 'expires_soon':
      final e = meParse(d['expires_on']);
      if (e == null) return 'Expires soon';
      final now = DateTime.now();
      final days = DateTime(e.year, e.month, e.day).difference(DateTime(now.year, now.month, now.day)).inDays;
      return days <= 0 ? 'Expires today' : 'Expires in $days ${days == 1 ? 'day' : 'days'}';
    default:
      return 'Not checked';
  }
}

const meDocKinds = [('certificate', 'Certificate'), ('id_proof', 'ID proof'), ('contract', 'Contract')];
String meDocKind(Object? k) => meDocKinds.firstWhere((x) => x.$1 == '$k', orElse: () => meDocKinds.first).$2;
