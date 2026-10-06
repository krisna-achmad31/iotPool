import '../domain/models.dart';

/// Semua akses data app lewat antarmuka ini. Ada dua implementasi:
/// - [DemoRepository]: data contoh di memori ("Lihat contoh dulu tanpa alat").
/// - [FirebaseRepository]: Firestore + RTDB sesuai docs/data-model.md.
abstract class SysnergiRepository {
  bool get isDemo;

  // ── Auth ──
  Stream<String?> authUid();
  String? get currentUid;

  /// Kirim kode OTP. Return id verifikasi (dipakai [verifyOtp]).
  Future<String> sendOtp(String phoneE164);
  Future<void> verifyOtp(String verificationId, String code);
  Future<void> signInWithGoogle();
  Future<void> signOut();

  // ── User ──
  Stream<UserProfile?> profile(String uid);
  Future<void> updatePrefs({bool? largeText, bool? alarmSound, String? displayName});

  // ── Site, zona, hub ──
  Stream<List<Site>> sites(String uid);
  Future<String> createSite({required String name, required String kind});
  Stream<List<Zone>> zones(String siteId);
  Stream<Hub?> hub(String hubId);
  Stream<LiveState?> live(String hubId);
  Future<List<TelemetryPoint>> history(String hubId, String port, Duration range);

  /// Nama tampilan anggota site. Firestore `users/{uid}` hanya bisa dibaca pemiliknya,
  /// jadi di mode Firebase nama diambil dari site (bila tersedia) atau dipendekkan dari uid.
  Future<Map<String, String>> memberNames(Site site);
  Future<void> setMemberRole(String siteId, String uid, Role? role);

  // ── Otomasi & event ──
  Stream<List<Automation>> automations(String siteId);
  Future<void> setAutomationEnabled(String siteId, Automation rule, bool enabled);
  Future<void> saveAutomation(String siteId, Automation rule);
  Stream<List<AppEvent>> events(String siteId, {int limit = 50});
  Future<void> markEventsRead(String siteId);

  // ── Perintah ke hub (RTDB down/cmd → ack) ──
  Future<CommandResult> sendCommand(String hubId, String type, [Map<String, dynamic> args = const {}]);

  // ── Klaim hub setelah pairing BLE ──
  Future<void> claimHub({required String hubId, required String nonce, required String siteId, String? name});
}

class CommandResult {
  const CommandResult(this.ok, [this.code]);
  final bool ok;
  final String? code;
}

class RepositoryException implements Exception {
  RepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}
