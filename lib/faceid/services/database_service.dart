import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/access_log.dart';
import '../models/person.dart';

class StoredEmbedding {
  const StoredEmbedding({required this.personId, required this.vector});

  final int personId;
  final Float32List vector;
}

/// MySQLga yuborilishi kerak bo'lgan lokal skan yozuvi.
class PendingSyncLog {
  const PendingSyncLog({required this.log, required this.externalId});

  final AccessLog log;

  /// Serverdagi xodim (xodimlar.id) — FaceID yozuvini shu xodimga bog'laydi.
  final int externalId;
}

class HomeStats {
  const HomeStats({
    required this.persons,
    required this.faces,
    required this.todayEntries,
    required this.todayExits,
    required this.totalLogs,
    this.lastLog,
  });

  final int persons;
  final int faces;
  final int todayEntries;
  final int todayExits;
  final int totalLogs;
  final AccessLog? lastLog;
}

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();
  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final path = p.join(await getDatabasesPath(), 'faceid_module.db');
    final db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE persons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            external_id INTEGER,
            full_name TEXT NOT NULL,
            employee_code TEXT NOT NULL UNIQUE,
            position TEXT,
            spot_id INTEGER,
            account_name TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_persons_external ON persons(external_id)',
        );
        await db.execute(
          'CREATE INDEX idx_persons_account ON persons(account_name)',
        );
        await db.execute('''
          CREATE TABLE face_embeddings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id INTEGER NOT NULL,
            embedding BLOB NOT NULL,
            image_path TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_face_person ON face_embeddings(person_id)',
        );
        await db.execute('''
          CREATE TABLE access_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id INTEGER,
            person_name TEXT NOT NULL,
            employee_code TEXT NOT NULL,
            action TEXT NOT NULL,
            confidence REAL NOT NULL,
            photo_path TEXT,
            timestamp TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_logs_person_time ON access_logs(person_id, timestamp DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE persons ADD COLUMN external_id INTEGER',
          );
          await db.execute('ALTER TABLE persons ADD COLUMN position TEXT');
          await db.execute('ALTER TABLE persons ADD COLUMN spot_id INTEGER');
          await db.execute(
            'CREATE UNIQUE INDEX idx_persons_external ON persons(external_id)',
          );
        }
        if (oldVersion < 3) {
          // Yangilanishdan oldingi sinov/ofis yozuvlari MySQLga qayta
          // yuborilmasin. Faqat yangi FaceID skanerlari navbatga tushadi.
          await db.execute('UPDATE access_logs SET synced = 1');
        }
        if (oldVersion < 4) {
          // Har bir xodim qaysi accountga tegishli ekanini saqlaymiz.
          // Yuz o'xshashligi faqat shu account ichida tekshiriladi.
          await db.execute(
            'ALTER TABLE persons ADD COLUMN account_name TEXT',
          );
          await db.execute(
            'CREATE INDEX idx_persons_account ON persons(account_name)',
          );
        }
      },
    );
    _db = db;
    return db;
  }

  Future<List<Person>> getPersons() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.*, (
        SELECT COUNT(*) FROM face_embeddings e WHERE e.person_id = p.id
      ) AS face_count
      FROM persons p
      ORDER BY p.full_name COLLATE NOCASE
    ''');
    return rows.map(Person.fromMap).toList();
  }

  Future<Person?> getPerson(int id) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT p.*, (
        SELECT COUNT(*) FROM face_embeddings e WHERE e.person_id = p.id
      ) AS face_count
      FROM persons p WHERE p.id = ? LIMIT 1
    ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return Person.fromMap(rows.first);
  }

  Future<Person?> getPersonByCode(String code) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT p.*, (
        SELECT COUNT(*) FROM face_embeddings e WHERE e.person_id = p.id
      ) AS face_count
      FROM persons p WHERE UPPER(p.employee_code) = UPPER(?) LIMIT 1
    ''',
      [code.trim()],
    );
    if (rows.isEmpty) return null;
    return Person.fromMap(rows.first);
  }

  Future<int> createPerson(String fullName, String employeeCode) async {
    final db = await database;
    return db.insert('persons', {
      'full_name': fullName.trim(),
      'employee_code': employeeCode.trim().toUpperCase(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Attendance tizimidagi xodimni lokal FaceID bazasiga qo'shadi yoki
  /// uning ism/lavozim/filial ma'lumotlarini yangilaydi.
  Future<int> upsertExternalPerson({
    required int externalId,
    required String fullName,
    String? position,
    int? spotId,
    String? accountName,
  }) async {
    final db = await database;
    final rows = await db.query(
      'persons',
      columns: ['id'],
      where: 'external_id = ?',
      whereArgs: [externalId],
      limit: 1,
    );
    final data = <String, Object?>{
      'external_id': externalId,
      'full_name': fullName.trim(),
      'employee_code': 'ATT-$externalId',
      'position': position,
      'spot_id': spotId,
      if (accountName != null && accountName.trim().isNotEmpty)
        'account_name': accountName.trim(),
    };
    if (rows.isNotEmpty) {
      final id = rows.first['id'] as int;
      await db.update('persons', data, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return db.insert('persons', {
      ...data,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Xodim lokal bazada bo'lmasa, faqat minimal ma'lumot bilan yaratadi.
  /// Mavjud yozuvning lavozim/filial ma'lumotlarini o'zgartirmaydi.
  Future<Person> ensureExternalPerson({
    required int externalId,
    required String fullName,
    String? accountName,
  }) async {
    final existing = await getPersonByExternalId(externalId);
    if (existing != null) {
      if (accountName != null &&
          accountName.trim().isNotEmpty &&
          existing.accountName != accountName.trim()) {
        final db = await database;
        await db.update(
          'persons',
          {'account_name': accountName.trim()},
          where: 'id = ?',
          whereArgs: [existing.id],
        );
        return await getPerson(existing.id) ?? existing;
      }
      return existing;
    }
    await upsertExternalPerson(
      externalId: externalId,
      fullName: fullName,
      accountName: accountName,
    );
    final created = await getPersonByExternalId(externalId);
    return created!;
  }

  Future<Person?> getPersonByExternalId(int externalId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT p.*, (
        SELECT COUNT(*) FROM face_embeddings e WHERE e.person_id = p.id
      ) AS face_count
      FROM persons p WHERE p.external_id = ? LIMIT 1
    ''',
      [externalId],
    );
    if (rows.isEmpty) return null;
    return Person.fromMap(rows.first);
  }

  Future<void> addEmbedding(
    int personId,
    Float32List vector, {
    String? imagePath,
  }) async {
    final db = await database;
    await db.insert('face_embeddings', {
      'person_id': personId,
      'embedding': vector.buffer.asUint8List(
        vector.offsetInBytes,
        vector.lengthInBytes,
      ),
      'image_path': imagePath,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<StoredEmbedding>> getAllEmbeddings({String? accountName}) async {
    final db = await database;
    final account = (accountName ?? '').trim();
    final rows = account.isEmpty
        ? await db.query(
            'face_embeddings',
            columns: ['person_id', 'embedding'],
          )
        : await db.rawQuery(
            '''
            SELECT e.person_id, e.embedding
            FROM face_embeddings e
            INNER JOIN persons p ON p.id = e.person_id
            WHERE p.account_name = ?
          ''',
            [account],
          );
    final result = <StoredEmbedding>[];
    for (final row in rows) {
      final blob = row['embedding'] as Uint8List;
      final copy = Uint8List.fromList(blob);
      final vector = copy.buffer.asFloat32List(0, copy.lengthInBytes ~/ 4);
      result.add(
        StoredEmbedding(
          personId: row['person_id'] as int,
          vector: Float32List.fromList(vector),
        ),
      );
    }
    return result;
  }

  Future<int> countEmbeddings() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM face_embeddings',
    );
    return (result.first['n'] as int?) ?? 0;
  }

  Future<AccessLog?> lastAction(int personId) async {
    final db = await database;
    final rows = await db.query(
      'access_logs',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'timestamp DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AccessLog.fromMap(rows.first);
  }

  Future<AccessLog?> lastLog() async {
    final db = await database;
    final rows = await db.query(
      'access_logs',
      orderBy: 'timestamp DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AccessLog.fromMap(rows.first);
  }

  Future<int> insertLog({
    required int personId,
    required String personName,
    required String employeeCode,
    required String action,
    required double confidence,
    required DateTime timestamp,
    String? photoPath,
    bool syncToServer = false,
  }) async {
    final db = await database;
    return db.insert('access_logs', {
      'person_id': personId,
      'person_name': personName,
      'employee_code': employeeCode,
      'action': action,
      'confidence': confidence,
      'photo_path': photoPath,
      'timestamp': timestamp.toIso8601String(),
      // Faqat xodimning o'z FaceID skaneri MySQL navbatiga tushadi.
      // Administratorning umumiy skanerlash yozuvlari lokal qoladi.
      'synced': syncToServer ? 0 : 1,
    });
  }

  Future<List<AccessLog>> getLogs({int limit = 300, String? action}) async {
    final db = await database;
    final rows = await db.query(
      'access_logs',
      where: action == null ? null : 'action = ?',
      whereArgs: action == null ? null : [action],
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
    );
    return rows.map(AccessLog.fromMap).toList();
  }

  Future<List<AccessLog>> getLogsForPerson(
    int personId, {
    int limit = 100,
  }) async {
    final db = await database;
    final rows = await db.query(
      'access_logs',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
    );
    return rows.map(AccessLog.fromMap).toList();
  }

  /// MySQLga hali yuborilmagan skanerlarni vaqt bo'yicha (eng eskisidan)
  /// qaytaradi. [externalId] berilsa faqat shu xodim, [accountName]
  /// berilsa faqat shu account xodimlari olinadi.
  Future<List<PendingSyncLog>> getPendingSyncLogs({
    int? externalId,
    String? accountName,
    int limit = 100,
  }) async {
    final db = await database;
    final where = <String>['l.synced = 0', 'p.external_id IS NOT NULL'];
    final args = <Object?>[];
    if (externalId != null) {
      where.add('p.external_id = ?');
      args.add(externalId);
    }
    final account = (accountName ?? '').trim();
    if (account.isNotEmpty) {
      where.add('(p.account_name = ? OR p.account_name IS NULL)');
      args.add(account);
    }
    args.add(limit);
    final rows = await db.rawQuery(
      '''
      SELECT l.*, p.external_id AS sync_external_id
      FROM access_logs l
      INNER JOIN persons p ON p.id = l.person_id
      WHERE ${where.join(' AND ')}
      ORDER BY l.timestamp ASC, l.id ASC
      LIMIT ?
    ''',
      args,
    );
    return rows
        .map(
          (row) => PendingSyncLog(
            log: AccessLog.fromMap(row),
            externalId: row['sync_external_id'] as int,
          ),
        )
        .toList();
  }

  Future<int> countPendingSync({
    int? externalId,
    String? accountName,
  }) async {
    final db = await database;
    final where = <String>['l.synced = 0', 'p.external_id IS NOT NULL'];
    final args = <Object?>[];
    if (externalId != null) {
      where.add('p.external_id = ?');
      args.add(externalId);
    }
    final account = (accountName ?? '').trim();
    if (account.isNotEmpty) {
      where.add('(p.account_name = ? OR p.account_name IS NULL)');
      args.add(account);
    }
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS n FROM access_logs l
      INNER JOIN persons p ON p.id = l.person_id
      WHERE ${where.join(' AND ')}
    ''',
      args,
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<void> markLogSynced(int logId, {bool synced = true}) async {
    final db = await database;
    await db.update(
      'access_logs',
      {'synced': synced ? 1 : 0},
      where: 'id = ?',
      whereArgs: [logId],
    );
  }

  Future<int> countTodayForPerson(int personId, String action) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM access_logs '
      'WHERE person_id = ? AND action = ? '
      'AND timestamp >= ? AND timestamp < ?',
      [personId, action, start.toIso8601String(), end.toIso8601String()],
    );
    return (result.first['n'] as int?) ?? 0;
  }

  Future<int> countToday(String action) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM access_logs '
      'WHERE action = ? AND timestamp >= ? AND timestamp < ?',
      [action, start.toIso8601String(), end.toIso8601String()],
    );
    return (result.first['n'] as int?) ?? 0;
  }

  Future<int> countLogs() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS n FROM access_logs');
    return (result.first['n'] as int?) ?? 0;
  }

  Future<HomeStats> getHomeStats() async {
    final persons = await getPersons();
    final faces = await countEmbeddings();
    final entries = await countToday('entry');
    final exits = await countToday('exit');
    final total = await countLogs();
    final last = await lastLog();
    return HomeStats(
      persons: persons.length,
      faces: faces,
      todayEntries: entries,
      todayExits: exits,
      totalLogs: total,
      lastLog: last,
    );
  }

  Future<Map<int, String>> getCoverImages() async {
    final db = await database;
    final rows = await db.query(
      'face_embeddings',
      columns: ['person_id', 'image_path'],
      where: 'image_path IS NOT NULL',
      orderBy: 'id ASC',
    );
    final covers = <int, String>{};
    for (final row in rows) {
      covers.putIfAbsent(
        row['person_id'] as int,
        () => row['image_path'] as String,
      );
    }
    return covers;
  }

  /// Attendance xodim IDsi (`external_id`) bo'yicha birinchi yuz rasmi.
  /// Admin ro'yxatida xodimning doirasida ko'rsatish uchun ishlatiladi.
  Future<Map<int, String>> getCoverImagesByExternalId() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.external_id, e.image_path
      FROM persons p
      INNER JOIN face_embeddings e ON e.person_id = p.id
      WHERE p.external_id IS NOT NULL AND e.image_path IS NOT NULL
      ORDER BY e.id ASC
    ''');
    final covers = <int, String>{};
    for (final row in rows) {
      final externalId = row['external_id'] as int?;
      final path = row['image_path'] as String?;
      if (externalId != null && path != null && path.isNotEmpty) {
        covers.putIfAbsent(externalId, () => path);
      }
    }
    return covers;
  }

  Future<List<String>> getPersonImagePaths(int personId) async {
    final db = await database;
    final rows = await db.query(
      'face_embeddings',
      columns: ['image_path'],
      where: 'person_id = ? AND image_path IS NOT NULL',
      whereArgs: [personId],
    );
    return rows
        .map((row) => row['image_path'] as String?)
        .whereType<String>()
        .toList();
  }

  Future<List<String>> deletePerson(int personId) async {
    final db = await database;
    final paths = await getPersonImagePaths(personId);
    await db.transaction((txn) async {
      await txn.delete(
        'face_embeddings',
        where: 'person_id = ?',
        whereArgs: [personId],
      );
      await txn.delete('persons', where: 'id = ?', whereArgs: [personId]);
    });
    return paths;
  }

  /// Xodim yozuvini saqlab, faqat yuz rasmlari va embeddinglarini o'chiradi.
  Future<List<String>> deletePersonFaces(int personId) async {
    final db = await database;
    final paths = await getPersonImagePaths(personId);
    await db.delete(
      'face_embeddings',
      where: 'person_id = ?',
      whereArgs: [personId],
    );
    return paths;
  }

  Future<void> deleteFaceImageRecord(int embeddingId) async {
    final db = await database;
    await db.delete(
      'face_embeddings',
      where: 'id = ?',
      whereArgs: [embeddingId],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> deleteFileQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Faylni o'chirish muvaffaqiyatsiz bo'lsa, jurnal yozuvi qoladi.
    }
  }
}
