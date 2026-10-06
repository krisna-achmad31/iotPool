import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/logic.dart';
import '../domain/models.dart';
import 'repository.dart';

/// Implementasi Firestore + RTDB. Path & bentuk data mengikuti docs/data-model.md.
/// Selama project masih Spark (tanpa Cloud Functions), app sendiri yang mem-publish
/// `down/config` dan `acl` ke RTDB setelah mengubah otomasi / anggota.
class FirebaseRepository implements SysnergiRepository {
  FirebaseRepository({FirebaseAuth? auth, FirebaseFirestore? db, FirebaseDatabase? rtdb})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _rtdb = rtdb ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseDatabase _rtdb;
  ConfirmationResult? _webConfirmation;

  @override
  bool get isDemo => false;

  // ───────────────────────── auth ─────────────────────────

  @override
  Stream<String?> authUid() => _auth.authStateChanges().map((u) => u?.uid);

  @override
  String? get currentUid => _auth.currentUser?.uid;

  @override
  Future<String> sendOtp(String phoneE164) async {
    if (kIsWeb) {
      _webConfirmation = await _auth.signInWithPhoneNumber(phoneE164);
      return 'web';
    }
    final c = Completer<String>();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (cred) async {
        // Android bisa membaca SMS otomatis.
        await _auth.signInWithCredential(cred);
        await _ensureUserDoc();
      },
      verificationFailed: (e) {
        if (!c.isCompleted) c.completeError(RepositoryException(_authMessage(e)));
      },
      codeSent: (id, _) {
        if (!c.isCompleted) c.complete(id);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return c.future;
  }

  @override
  Future<void> verifyOtp(String verificationId, String code) async {
    try {
      if (kIsWeb) {
        await _webConfirmation!.confirm(code);
      } else {
        await _auth.signInWithCredential(PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code));
      }
      await _ensureUserDoc();
    } on FirebaseAuthException catch (e) {
      throw RepositoryException(_authMessage(e));
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        await _auth.signInWithPopup(GoogleAuthProvider());
      } else {
        await _auth.signInWithProvider(GoogleAuthProvider());
      }
      await _ensureUserDoc();
    } on FirebaseAuthException catch (e) {
      throw RepositoryException(_authMessage(e));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  Future<void> _ensureUserDoc() async {
    final u = _auth.currentUser!;
    final ref = _db.doc('users/${u.uid}');
    if ((await ref.get()).exists) return;
    // Rules: create tanpa plan/usage, ownedHubIds harus kosong.
    await ref.set({
      'displayName': u.displayName,
      'phone': u.phoneNumber,
      'ownedHubIds': <String>[],
      'prefs': {'largeText': false, 'alarmSound': true, 'locale': 'id'},
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _authMessage(FirebaseAuthException e) => switch (e.code) {
        'invalid-verification-code' => 'Kode salah. Periksa lagi 6 angkanya.',
        'invalid-phone-number' => 'Nomor HP tidak valid.',
        'too-many-requests' => 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.',
        'session-expired' => 'Kode sudah kedaluwarsa. Minta kode baru.',
        _ => e.message ?? 'Gagal masuk (${e.code}).',
      };

  // ───────────────────────── user ─────────────────────────

  @override
  Stream<UserProfile?> profile(String uid) => _db.doc('users/$uid').snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        final prefs = (d['prefs'] as Map?) ?? const {};
        final plan = (d['plan'] as Map?) ?? const {};
        final usage = (d['usage'] as Map?) ?? const {};
        return UserProfile(
          uid: uid,
          displayName: d['displayName'] as String?,
          phone: d['phone'] as String?,
          largeText: prefs['largeText'] == true,
          alarmSound: prefs['alarmSound'] != false,
          ownedHubIds: List<String>.from(d['ownedHubIds'] ?? const []),
          planTier: plan['tier'] as String? ?? 'free',
          hubLimit: (plan['hubLimit'] as num?)?.toInt() ?? 1,
          aiMonthlyLimit: (plan['aiMonthlyLimit'] as num?)?.toInt() ?? 0,
          aiCount: (usage['aiCount'] as num?)?.toInt() ?? 0,
          planValidUntil: (plan['validUntil'] as Timestamp?)?.toDate(),
        );
      });

  @override
  Future<void> updatePrefs({bool? largeText, bool? alarmSound, String? displayName}) => _db.doc('users/$currentUid').update({
        'prefs.largeText': ?largeText,
        'prefs.alarmSound': ?alarmSound,
        'displayName': ?displayName,
      });

  // ───────────────────────── site/zona/hub ─────────────────────────

  Site _site(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data()!;
    return Site(
      id: s.id,
      name: d['name'] as String? ?? '',
      kind: d['kind'] as String? ?? 'other',
      ownerUid: d['ownerUid'] as String,
      roles: {
        for (final e in ((d['roles'] as Map?) ?? const {}).entries)
          e.key as String: Role.values.byName(e.value as String),
      },
      hubIds: List<String>.from(d['hubIds'] ?? const []),
      timezone: d['timezone'] as String? ?? 'Asia/Jakarta',
    );
  }

  @override
  Stream<List<Site>> sites(String uid) => _db
      .collection('sites')
      .where('memberUids', arrayContains: uid)
      .snapshots()
      .map((q) => q.docs.map(_site).toList());

  @override
  Future<String> createSite({required String name, required String kind}) async {
    final uid = currentUid!;
    final ref = _db.collection('sites').doc();
    await ref.set({
      'name': name,
      'kind': kind,
      'ownerUid': uid,
      'roles': {uid: 'owner'},
      'memberUids': [uid],
      'hubIds': <String>[],
      'timezone': 'Asia/Jakarta',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final (zoneName, zoneKind) = switch (kind) {
      'aquaculture' => ('Kolam 1', 'pond'),
      'horticulture' => ('Kebun 1', 'greenhouse'),
      'livestock' => ('Kandang 1', 'barn'),
      _ => ('Area 1', 'other'),
    };
    await ref.collection('zones').add({'name': zoneName, 'kind': zoneKind, 'order': 1, 'meta': {}});
    return ref.id;
  }

  @override
  Stream<List<Zone>> zones(String siteId) =>
      _db.collection('sites/$siteId/zones').orderBy('order').snapshots().map((q) => q.docs.map((s) {
            final d = s.data();
            return Zone(
              id: s.id,
              name: d['name'] as String? ?? '',
              kind: d['kind'] as String? ?? 'other',
              order: (d['order'] as num?)?.toInt() ?? 0,
              meta: Map<String, dynamic>.from(d['meta'] ?? const {}),
              thresholds: {
                for (final e in ((d['thresholds'] as Map?) ?? const {}).entries)
                  e.key as String: ?Threshold.fromMap(e.value),
              },
            );
          }).toList());

  @override
  Stream<Hub?> hub(String hubId) => _db.doc('hubs/$hubId').snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        final ports = <String, PortAssignment>{};
        ((d['ports'] as Map?) ?? const {}).forEach((k, v) {
          if (v is Map) {
            ports[k as String] = PortAssignment(
              metric: v['metric'] as String,
              zoneId: v['zoneId'] as String? ?? '',
              label: v['label'] as String?,
              calibratedAt: (v['calibratedAt'] as Timestamp?)?.toDate(),
              sensorModel: v['sensorModel'] as String?,
            );
          }
        });
        final relays = <String, RelayAssignment>{};
        ((d['relays'] as Map?) ?? const {}).forEach((k, v) {
          if (v is Map) {
            relays[k as String] = RelayAssignment(
              kind: v['kind'] as String? ?? 'generic',
              label: v['label'] as String? ?? actuatorDef(v['kind'] as String? ?? 'generic').label,
              zoneId: v['zoneId'] as String? ?? '',
              levels: (v['levels'] as num?)?.toInt(),
            );
          }
        });
        return Hub(
          id: s.id,
          name: d['name'] as String?,
          siteId: d['siteId'] as String?,
          ownerUid: d['ownerUid'] as String?,
          ports: ports,
          relays: relays,
          detected: {
            for (final e in ((d['detected'] as Map?) ?? const {}).entries)
              if (e.value is String) e.key as String: e.value as String,
          },
          fwVersion: (d['fw'] as Map?)?['version'] as String?,
          connectivity: d['connectivity'] as String? ?? 'wifi',
          configVersion: (d['configVersion'] as num?)?.toInt() ?? 0,
          model: d['model'] as String? ?? 'sysnergi-hub',
        );
      }).handleError((Object _) {}, test: (e) => e is FirebaseException && e.code == 'permission-denied');

  @override
  Stream<LiveState?> live(String hubId) => _rtdb.ref('hubs/$hubId/live').onValue.map((e) {
        final v = e.snapshot.value;
        if (v is! Map) return null;
        final ch = <String, ChannelValue>{};
        ((v['ch'] as Map?) ?? const {}).forEach((k, c) {
          if (c is Map && c['v'] is num) ch[k as String] = ChannelValue((c['v'] as num).toDouble(), err: c['err'] as String?);
        });
        final relays = <String, RelayState>{};
        ((v['relays'] as Map?) ?? const {}).forEach((k, r) {
          if (r is Map) {
            relays[k as String] = RelayState(
              on: r['on'] == true,
              mode: r['mode'] as String? ?? 'auto',
              level: (r['level'] as num?)?.toInt(),
              since: r['since'] is num ? DateTime.fromMillisecondsSinceEpoch((r['since'] as num).toInt()) : null,
              ruleId: r['ruleId'] as String?,
            );
          }
        });
        return LiveState(
          ts: DateTime.fromMillisecondsSinceEpoch((v['ts'] as num?)?.toInt() ?? 0),
          rssi: (v['rssi'] as num?)?.toInt(),
          power: v['power'] as String?,
          uptime: v['uptimeS'] is num ? Duration(seconds: (v['uptimeS'] as num).toInt()) : null,
          fw: v['fw'] as String?,
          ch: ch,
          relays: relays,
          pendingEvents: (v['pendingEvents'] as num?)?.toInt() ?? 0,
        );
      });

  @override
  Future<List<TelemetryPoint>> history(String hubId, String port, Duration range) async {
    final now = DateTime.now();
    final from = now.subtract(range);
    final out = <TelemetryPoint>[];
    String two(int n) => n.toString().padLeft(2, '0');

    if (range.inDays <= 7) {
      // days/{yyyymmdd}.s.tHHMM = rata-rata 5 menit (waktu lokal hub)
      for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(now); d = d.add(const Duration(days: 1))) {
        final snap = await _db.doc('hubs/$hubId/days/${d.year}${two(d.month)}${two(d.day)}').get();
        final slots = (snap.data()?['s'] as Map?) ?? const {};
        slots.forEach((k, v) {
          final key = k as String;
          final val = (v as Map?)?[port];
          if (val is! num || key.length != 5) return;
          final t = DateTime(d.year, d.month, d.day, int.parse(key.substring(1, 3)), int.parse(key.substring(3, 5)));
          if (t.isAfter(from)) out.add(TelemetryPoint(t, val.toDouble()));
        });
      }
    } else {
      // months/{yyyymm}.h.dDDhHH = [min, avg, max] per jam
      for (var m = DateTime(from.year, from.month); !m.isAfter(now); m = DateTime(m.year, m.month + 1)) {
        final snap = await _db.doc('hubs/$hubId/months/${m.year}${two(m.month)}').get();
        final hours = (snap.data()?['h'] as Map?) ?? const {};
        hours.forEach((k, v) {
          final key = k as String;
          final triple = (v as Map?)?[port];
          if (triple is! List || triple.length != 3) return;
          final t = DateTime(m.year, m.month, int.parse(key.substring(1, 3)), int.parse(key.substring(4, 6)));
          if (t.isAfter(from)) out.add(TelemetryPoint(t, (triple[1] as num).toDouble()));
        });
      }
    }
    out.sort((a, b) => a.t.compareTo(b.t));
    return out;
  }

  @override
  Future<Map<String, String>> memberNames(Site site) async {
    final me = currentUid;
    final myName = me == null ? null : (await _db.doc('users/$me').get()).data()?['displayName'] as String?;
    return {
      for (final uid in site.roles.keys) uid: uid == me ? (myName ?? 'Anda') : 'Anggota ${uid.substring(0, 4).toUpperCase()}',
    };
  }

  @override
  Future<void> setMemberRole(String siteId, String uid, Role? role) async {
    final ref = _db.doc('sites/$siteId');
    final site = _site(await ref.get());
    final roles = {for (final e in site.roles.entries) e.key: e.value.name};
    if (role == null) {
      roles.remove(uid);
    } else {
      roles[uid] = role.name;
    }
    await ref.update({'roles': roles, 'memberUids': roles.keys.toList(), 'updatedAt': FieldValue.serverTimestamp()});
    // Mode Spark: cerminkan ke RTDB acl tiap hub (Cloud Function syncSiteAcl melakukan hal yang sama).
    final updates = <String, Object?>{};
    for (final h in site.hubIds) {
      updates['hubs/$h/acl/$uid'] = role?.name;
    }
    if (updates.isNotEmpty) await _rtdb.ref().update(updates);
  }

  // ───────────────────────── otomasi ─────────────────────────

  ThresholdCond _condFrom(Map m) =>
      ThresholdCond(ch: m['ch'] as String, op: m['op'] as String, value: (m['value'] as num).toDouble());

  Automation _ruleFrom(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data()!;
    final t = d['trigger'] as Map;
    final a = d['action'] as Map;
    final until = a['until'] as Map?;
    final safety = (d['safety'] as Map?) ?? const {};
    return Automation(
      id: s.id,
      name: d['name'] as String? ?? '',
      enabled: d['enabled'] == true,
      hubId: d['hubId'] as String,
      trigger: t['type'] == 'schedule'
          ? ScheduleTrigger(start: t['start'] as String, end: t['end'] as String?, days: (t['days'] as List?)?.cast<int>())
          : ThresholdTrigger(_condFrom(t), holdSec: (t['holdSec'] as num?)?.toInt()),
      action: a['type'] == 'notify'
          ? NotifyAction(Severity.values.byName(a['severity'] as String))
          : RelayAction(
              relay: a['relay'] as String,
              on: a['on'] == true,
              level: (a['level'] as num?)?.toInt(),
              untilThreshold: until?['type'] == 'threshold' ? _condFrom(until!) : null,
              untilDurationSec: until?['type'] == 'duration' ? (until!['sec'] as num).toInt() : null,
            ),
      maxRunSec: (safety['maxRunSec'] as num?)?.toInt(),
      cooldownSec: (safety['cooldownSec'] as num?)?.toInt(),
      source: d['source'] as String? ?? 'manual',
      prompt: d['prompt'] as String?,
    );
  }

  @override
  Stream<List<Automation>> automations(String siteId) =>
      _db.collection('sites/$siteId/automations').snapshots().map((q) => q.docs.map(_ruleFrom).toList());

  @override
  Future<void> setAutomationEnabled(String siteId, Automation rule, bool enabled) async {
    await _db.doc('sites/$siteId/automations/${rule.id}').update({'enabled': enabled, 'updatedAt': FieldValue.serverTimestamp()});
    await _publishConfig(siteId, rule.hubId);
  }

  @override
  Future<void> saveAutomation(String siteId, Automation rule) async {
    final ref = _db.doc('sites/$siteId/automations/${rule.id}');
    final exists = (await ref.get()).exists;
    await ref.set({
      'name': rule.name,
      'enabled': rule.enabled,
      'hubId': rule.hubId,
      'source': rule.source,
      if (rule.prompt != null) 'prompt': rule.prompt,
      ...encodeRule(rule),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!exists) 'createdBy': currentUid,
      if (!exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _publishConfig(siteId, rule.hubId);
  }

  /// Kompilasi ulang config hub lalu tulis ke RTDB `down/config` (pengganti Cloud Function di Spark).
  Future<void> _publishConfig(String siteId, String hubId) async {
    final siteSnap = await _db.doc('sites/$siteId').get();
    final hubRef = _db.doc('hubs/$hubId');
    final hub = await this.hub(hubId).first;
    if (hub == null) return;
    final zoneList = await zones(siteId).first;
    final rules = await automations(siteId).first;
    final nextVersion = hub.configVersion + 1;
    await hubRef.update({'configVersion': nextVersion});
    final cfg = buildHubConfig(
      hub: Hub(id: hub.id, siteId: hub.siteId, ports: hub.ports, relays: hub.relays, configVersion: nextVersion),
      timezone: siteSnap.data()?['timezone'] as String? ?? 'Asia/Jakarta',
      zones: {for (final z in zoneList) z.id: z},
      automations: rules,
      encodeRule: encodeRule,
    );
    await _rtdb.ref('hubs/$hubId/down/config').set(cfg);
  }

  // ───────────────────────── event ─────────────────────────

  @override
  Stream<List<AppEvent>> events(String siteId, {int limit = 50}) => _db
      .collection('sites/$siteId/events')
      .orderBy('ts', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map((s) {
            final d = s.data();
            return AppEvent(
              id: s.id,
              ts: (d['ts'] as Timestamp?)?.toDate() ?? DateTime.now(),
              type: d['type'] as String? ?? 'system',
              severity: Severity.values.byName(d['severity'] as String? ?? 'info'),
              hubId: d['hubId'] as String?,
              zoneId: d['zoneId'] as String?,
              ch: d['ch'] as String?,
              metric: d['metric'] as String?,
              value: (d['value'] as num?)?.toDouble(),
              relay: d['relay'] as String?,
              ruleId: d['ruleId'] as String?,
              title: d['title'] as String?,
              body: d['body'] as String?,
            );
          }).toList());

  @override
  Future<void> markEventsRead(String siteId) =>
      _db.doc('users/$currentUid').update({'readAt.$siteId': FieldValue.serverTimestamp()});

  // ───────────────────────── perintah ─────────────────────────

  @override
  Future<CommandResult> sendCommand(String hubId, String type, [Map<String, dynamic> args = const {}]) async {
    final cmdRef = _rtdb.ref('hubs/$hubId/down/cmd').push();
    final ackRef = _rtdb.ref('hubs/$hubId/ack/${cmdRef.key}');
    await cmdRef.set({'type': type, 'args': args, 'by': currentUid, 'ts': ServerValue.timestamp, 'expSec': 60});
    try {
      final e = await ackRef.onValue.firstWhere((e) => e.snapshot.value is Map).timeout(const Duration(seconds: 15));
      final ack = e.snapshot.value as Map;
      await ackRef.remove();
      return CommandResult(ack['ok'] == true, ack['code'] as String?);
    } on TimeoutException {
      // Hub tidak menjawab: batalkan perintah supaya tidak dieksekusi terlambat.
      await cmdRef.remove();
      return const CommandResult(false, 'timeout');
    }
  }

  // ───────────────────────── klaim hub ─────────────────────────

  @override
  Future<void> claimHub({required String hubId, required String nonce, required String siteId, String? name}) async {
    final uid = currentUid!;
    final batch = _db.batch()
      ..update(_db.doc('hubs/$hubId'), {
        'ownerUid': uid,
        'siteId': siteId,
        'claimNonce': nonce,
        'claim': null,
        'name': ?name,
      })
      ..update(_db.doc('sites/$siteId'), {
        'hubIds': FieldValue.arrayUnion([hubId]),
        'updatedAt': FieldValue.serverTimestamp(),
      })
      ..update(_db.doc('users/$uid'), {
        'ownedHubIds': FieldValue.arrayUnion([hubId]),
      });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw RepositoryException('Hub tidak bisa didaftarkan. Mungkin sudah milik akun lain, kode pairing kedaluwarsa, '
            'atau kuota hub paket Anda penuh.');
      }
      rethrow;
    }
    await _rtdb.ref().update({
      'hubs/$hubId/meta/ownerUid': uid,
      'hubs/$hubId/meta/claimNonce': nonce,
      'hubs/$hubId/meta/siteId': siteId,
      'hubs/$hubId/acl/$uid': 'owner',
    });
  }
}
