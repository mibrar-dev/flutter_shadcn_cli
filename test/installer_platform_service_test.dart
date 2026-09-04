import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_platform_service.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InstallerPlatformService', () {
    late Directory tempDir;
    late InstallerPlatformService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('platform_service_test_');
      service = InstallerPlatformService(
        targetDir: tempDir.path,
        logger: CliLogger(),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('writes marked platform sections once using configured targets',
        () async {
      final component = Component.fromJson({
        'id': 'camera',
        'name': 'Camera',
        'files': [],
        'platform': {
          'android': {
            'permissions': ['android.permission.CAMERA'],
            'gradle': ['implementation "androidx.camera:camera-core:1.3.0"'],
          },
          'ios': {
            'infoPlist': {
              'NSCameraUsageDescription': 'Camera access is required',
            },
          },
        },
      });
      final config = const ShadcnConfig(
        platformTargets: {
          'android': {
            'permissions': 'android/custom/AndroidManifest.xml',
          },
        },
      );

      await service.applyInstructions(component, config: config);
      await service.applyInstructions(component, config: config);

      final manifest = File(
        p.join(tempDir.path, 'android/custom/AndroidManifest.xml'),
      ).readAsStringSync();
      expect(
        RegExp('shadcn_flutter_cli:android:permissions:start')
            .allMatches(manifest),
        hasLength(1),
      );
      expect(manifest, contains('android.permission.CAMERA'));

      final gradle = File(
        p.join(tempDir.path, 'android/app/build.gradle'),
      ).readAsStringSync();
      expect(
        RegExp('shadcn_flutter_cli:android:gradle:start').allMatches(gradle),
        hasLength(1),
      );

      final plist = File(
        p.join(tempDir.path, 'ios/Runner/Info.plist'),
      ).readAsStringSync();
      expect(plist, contains('NSCameraUsageDescription'));
      expect(plist, contains('Camera access is required'));
    });

    test('reports post-install notes through logger without throwing', () {
      final component = Component.fromJson({
        'id': 'camera',
        'name': 'Camera',
        'files': [],
        'postInstall': ['Enable camera permissions in your store profile.'],
      });

      service.reportPostInstall(component);
    });
  });
}
