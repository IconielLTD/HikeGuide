import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hike_guide/services/cache_repository.dart';

/// Exercises the real CacheRepository against a desktop (ffi) SQLite engine, so
/// we can prove the "Stop & Save → Journal" persistence path end to end —
/// both on a fresh install and, crucially, on a phone upgraded from an earlier
/// phase whose database predates the trips table.
void main() {
  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    dbPath = '${await sqflite.getDatabasesPath()}/hikeguide.db';
  });

  setUp(() async {
    await CacheRepository.instance.resetForTest();
    final file = File(dbPath);
    if (await file.exists()) await file.delete();
  });

  tearDown(() async {
    await CacheRepository.instance.resetForTest();
  });

  test('fresh install: a finished trip is saved and listed', () async {
    final repo = CacheRepository.instance;
    final start = DateTime(2026, 6, 8, 10, 0);
    final id = await repo.insertTrip(name: 'Peak walk', startedAt: start);
    await repo.insertRoutePoint(
        id, 53.20, -1.07, start.add(const Duration(minutes: 1)));
    await repo.finishTrip(id,
        endedAt: start.add(const Duration(hours: 1)), distanceMetres: 1234);

    final trips = await repo.listTrips();
    expect(trips.length, 1);
    expect(trips.first.title, 'Peak walk');
    expect(trips.first.distanceMetres, 1234);
    expect(trips.first.endedAt, isNotNull);
  });

  test('upgraded install (no trips table yet) can still save and list',
      () async {
    // Simulate an old phone: a v1 database with only the guide cache — the
    // trips / route_points tables did not exist yet.
    final old = await sqflite.openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, v) async {
        await db.execute(
            'CREATE TABLE guide_cache (id INTEGER PRIMARY KEY, x TEXT)');
      },
    );
    await old.close();

    // The real repository opens it at the current version → onUpgrade must add
    // the missing tables, or insertTrip throws "no such table: trips".
    final repo = CacheRepository.instance;
    final id = await repo.insertTrip(
        name: 'After upgrade', startedAt: DateTime(2026, 6, 8, 9));
    await repo.finishTrip(id,
        endedAt: DateTime(2026, 6, 8, 10), distanceMetres: 500);

    final trips = await repo.listTrips();
    expect(trips.length, 1);
    expect(trips.first.title, 'After upgrade');
  });

  test('one-time notice flag is false until marked, then persists', () async {
    final repo = CacheRepository.instance;
    expect(await repo.hasShownNotice('scotland_access'), isFalse);
    await repo.markNoticeShown('scotland_access');
    expect(await repo.hasShownNotice('scotland_access'), isTrue);

    // Survives the handle being reopened (i.e. a relaunch reads the same flag).
    await repo.resetForTest();
    expect(await repo.hasShownNotice('scotland_access'), isTrue);
    // An unrelated notice id is independent.
    expect(await repo.hasShownNotice('something_else'), isFalse);
  });
}
