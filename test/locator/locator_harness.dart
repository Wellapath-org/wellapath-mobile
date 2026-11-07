/// Shared harness for pumping the real [LocatorScreen] in widget tests.
///
/// The screen has three outside dependencies, each replaced at its real
/// boundary rather than by changing the screen:
///
///  * Hive — the decoded facility cache and the cached `/config` live in
///    temporary on-disk boxes, opened before the test body so the screen only
///    ever does synchronous reads inside the fake-async zone;
///  * geolocator — its platform method channel is answered by [FakeLocation];
///  * url_launcher — its platform method channel records launched URLs, so
///    a test can assert exactly what a tap would open without opening it.
///
/// All facility records used with this harness are synthetic.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wellapath_mobile/core/network/staged_artifact_loader.dart';
import 'package:wellapath_mobile/features/locator/locator_screen.dart';

const String _configBox = 'config_cache';
const String _configKey = 'last_known_config';
const String _version = '9.9';
const String _hash =
    'sha256:0000000000000000000000000000000000000000000000000000000000000000';

const MethodChannel _geolocatorChannel = MethodChannel(
  'flutter.baseflow.com/geolocator',
);
const MethodChannel _urlLauncherChannel = MethodChannel(
  'plugins.flutter.io/url_launcher',
);

/// Geolocator `LocationPermission` indices as the platform channel sends them.
enum FakePermission { denied, deniedForever, whileInUse }

class FakeLocation {
  FakeLocation({
    this.serviceEnabled = true,
    this.permission = FakePermission.whileInUse,
    this.latitude,
    this.longitude,
    this.throwOnPosition = false,
  });

  final bool serviceEnabled;
  final FakePermission permission;
  final double? latitude;
  final double? longitude;
  final bool throwOnPosition;
}

Map<String, dynamic> syntheticFacility({
  required String id,
  required String name,
  required String state,
  required double lat,
  required double lon,
  String type = 'hospital',
  String cityArea = 'Central',
  bool emergencyCapable = false,
}) => <String, dynamic>{
  'facility_id': id,
  'name': name,
  'type': type,
  'state': state,
  'city_area': cityArea,
  'latitude': lat,
  'longitude': lon,
  'phone': null,
  'opening_hours': null,
  'emergency_capable': emergencyCapable,
};

class LocatorHarness {
  late Directory _dir;
  late StagedArtifactLoader _previousLoader;

  /// Every URL handed to url_launcher during the test, in order.
  final List<String> launchedUrls = <String>[];

  Future<void> setUp() async {
    launchedUrls.clear();
    _dir = Directory.systemTemp.createTempSync('locator_harness_');
    Hive.init(_dir.path);
    await Hive.openBox(_configBox);
    await Hive.openBox(ArtifactCacheKeys.facilityBox);
    _previousLoader = StagedArtifactLoader.instance;
    StagedArtifactLoader.instance = StagedArtifactLoader();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, (MethodCall call) async {
          if (call.method == 'launch') {
            launchedUrls.add((call.arguments as Map)['url'] as String);
          }
          return true;
        });
  }

  Future<void> tearDown() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_geolocatorChannel, null);
    messenger.setMockMethodCallHandler(_urlLauncherChannel, null);
    StagedArtifactLoader.instance = _previousLoader;
    await Hive.deleteFromDisk();
    if (_dir.existsSync()) _dir.deleteSync(recursive: true);
  }

  /// Seeds a cached `/config` and a decoded facility cache that matches it,
  /// which is the state after a successful facilities download.
  Future<void> seedFacilities(List<Map<String, dynamic>> facilities) async {
    await seedConfig();
    final Box<dynamic> box = Hive.box(ArtifactCacheKeys.facilityBox);
    await box.put(ArtifactCacheKeys.facilityData, facilities);
    await box.put(ArtifactCacheKeys.facilityStamp, '$_version|$_hash');
  }

  /// Seeds only the cached `/config` (no decoded facilities on the device).
  Future<void> seedConfig() async {
    await Hive.box(_configBox).put(_configKey, <String, dynamic>{
      'version': '1.0',
      'artifacts': <String, dynamic>{
        'facilities': <String, dynamic>{
          'version': _version,
          'url': 'https://example.invalid/facilities.json',
          'hash': _hash,
        },
      },
    });
  }

  /// Marks the shared loader's facilities download as failed, which is what
  /// a network failure or an offline device produces.
  void markFacilitiesDownloadFailed() {
    StagedArtifactLoader.instance.facilitiesFailed.value = true;
  }

  void setLocation(FakeLocation location) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocatorChannel, (MethodCall call) async {
          switch (call.method) {
            case 'isLocationServiceEnabled':
              return location.serviceEnabled;
            case 'checkPermission':
            case 'requestPermission':
              return location.permission.index;
            case 'getCurrentPosition':
              if (location.throwOnPosition) {
                throw PlatformException(code: 'POSITION_UNAVAILABLE');
              }
              return <String, dynamic>{
                'latitude': location.latitude,
                'longitude': location.longitude,
                'timestamp': 0,
                'accuracy': 10.0,
                'altitude': 0.0,
                'heading': 0.0,
                'speed': 0.0,
                'speed_accuracy': 0.0,
              };
          }
          return null;
        });
  }

  Future<void> pumpLocator(
    WidgetTester tester, {
    String urgency = 'non_urgent',
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LocatorScreen(urgency: urgency)));
    // Lets the cache read, the location calls and the resulting setState
    // settle. Bounded pumps rather than pumpAndSettle: the download view
    // animates indefinitely by design.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}
