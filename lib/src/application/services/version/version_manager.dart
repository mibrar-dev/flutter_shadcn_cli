import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:path/path.dart' as p;

class VersionManagerException implements Exception {
  final String message;
  final int exitCode;

  const VersionManagerException(this.message, {required this.exitCode});

  @override
  String toString() => message;
}

/// Manages CLI version checking and upgrades
class VersionManager {
  static const String currentVersion = '0.2.1';
  static const String packageName = 'flutter_shadcn_cli';
  static const String pubDevApiUrl =
      'https://pub.dev/api/packages/$packageName';
  static const Duration checkInterval = Duration(hours: 24);

  final CliLogger logger;

  VersionManager({required this.logger});

  /// Displays the current CLI version
  void showVersion() {
    logger.info('flutter_shadcn_cli version $currentVersion');
  }

  /// Automatically checks for updates in the background (rate-limited to once per day)
  /// Shows a subtle notification if newer version is available
  Future<void> autoCheckForUpdates() async {
    try {
      final cacheFile = _versionCacheFile();
      final now = DateTime.now();

      // Check if we've checked recently
      if (await cacheFile.exists()) {
        final cacheContent = await cacheFile.readAsString();
        final cacheData = json.decode(cacheContent) as Map<String, dynamic>;
        final lastCheck = DateTime.parse(cacheData['lastCheck'] as String);

        // If we checked within the last 24 hours, skip
        if (now.difference(lastCheck) < checkInterval) {
          // Show cached notification if there was an update available
          if (cacheData['hasUpdate'] == true) {
            final latestVersion = cacheData['latestVersion'] as String;
            _showUpdateNotification(latestVersion);
          }
          return;
        }
      }

      // Fetch latest version
      final latestVersion = await _fetchLatestVersion();

      if (latestVersion == null) {
        // Unable to check - save timestamp anyway to avoid hammering the API
        await _saveCacheData(now, false, currentVersion);
        return;
      }

      // Check if there's an update
      final hasUpdate = _isNewerVersion(latestVersion, currentVersion);

      // Save to cache
      await _saveCacheData(now, hasUpdate, latestVersion);

      // Show notification if update available
      if (hasUpdate) {
        _showUpdateNotification(latestVersion);
      }
    } catch (e) {
      // Silently fail - don't interrupt user workflow
      logger.detail('Auto-check for updates failed: $e');
    }
  }

  /// Checks for updates and displays available version
  Future<void> checkForUpdates() async {
    try {
      logger.info('Checking for updates...');
      final latestVersion = await _fetchLatestVersion();

      if (latestVersion == null) {
        logger.warn(
            'Unable to check for updates. Please check your internet connection.');
        return;
      }

      if (_isNewerVersion(latestVersion, currentVersion)) {
        logger.warn('');
        logger
            .warn('┌────────────────────────────────────────────────────────┐');
        logger
            .warn('│  A new version of flutter_shadcn_cli is available!    │');
        logger
            .warn('│                                                        │');
        logger.warn(
            '│  Current: $currentVersion                                    │');
        logger.warn(
            '│  Latest:  $latestVersion                                    │');
        logger
            .warn('│                                                        │');
        logger
            .warn('│  Run: flutter_shadcn upgrade                           │');
        logger
            .warn('└────────────────────────────────────────────────────────┘');
        logger.warn('');
      } else {
        logger.success('You are using the latest version ($currentVersion)');
      }
    } catch (e) {
      logger.error('Error checking for updates: $e');
    }
  }

  /// Upgrades the CLI to the latest version
  Future<void> upgrade({bool force = false}) async {
    try {
      logger.info('Checking for updates...');
      final latestVersion = await _fetchLatestVersion();

      if (latestVersion == null) {
        logger.error(
            'Unable to fetch latest version. Please check your internet connection.');
        throw const VersionManagerException(
          'Unable to fetch latest version.',
          exitCode: ExitCodes.networkError,
        );
      }

      if (!force && !_isNewerVersion(latestVersion, currentVersion)) {
        logger.success('Already on the latest version ($currentVersion)');
        return;
      }

      logger.info('');
      logger.info('Upgrading from $currentVersion to $latestVersion...');
      logger.info('');

      // Run dart pub global activate to upgrade
      final result = await Process.run(
        'dart',
        ['pub', 'global', 'activate', packageName],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        logger.success('');
        logger.success('✓ Successfully upgraded to $latestVersion!');
        logger.success('');
        logger.info('Run "flutter_shadcn version" to verify the upgrade.');
      } else {
        logger.error('');
        logger.error('Failed to upgrade:');
        logger.error(result.stderr.toString());
        logger.error('');
        logger.info('Try manually upgrading with:');
        logger.info('  dart pub global activate $packageName');
        throw const VersionManagerException(
          'Failed to upgrade.',
          exitCode: ExitCodes.ioError,
        );
      }
    } catch (e) {
      if (e is VersionManagerException) {
        rethrow;
      }
      logger.error('Error during upgrade: $e');
      logger.info('');
      logger.info('Try manually upgrading with:');
      logger.info('  dart pub global activate $packageName');
      throw VersionManagerException(
        'Error during upgrade: $e',
        exitCode: ExitCodes.ioError,
      );
    }
  }

  /// Fetches the latest version from pub.dev
  Future<String?> _fetchLatestVersion() async {
    try {
      final response = await http.get(Uri.parse(pubDevApiUrl)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['latest']['version'] as String?;
      }
      return null;
    } catch (e) {
      logger.detail('Error fetching latest version: $e');
      return null;
    }
  }

  /// Compares two semantic versions
  bool _isNewerVersion(String latest, String current) {
    final latestParts = latest.split('.').map(int.parse).toList();
    final currentParts = current.split('.').map(int.parse).toList();

    for (var i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  /// Shows a subtle update notification
  void _showUpdateNotification(String latestVersion) {
    stderr.writeln('');
    stderr
        .writeln('┌─────────────────────────────────────────────────────────┐');
    stderr
        .writeln('│ A new version of flutter_shadcn_cli is available!      │');
    stderr.writeln(
        '│ Current: $currentVersion → Latest: $latestVersion                       │');
    stderr
        .writeln('│ Run: flutter_shadcn upgrade                             │');
    stderr
        .writeln('└─────────────────────────────────────────────────────────┘');
    stderr.writeln('');
  }

  /// Gets the version cache file path
  File _versionCacheFile() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) {
      throw Exception('Unable to determine home directory');
    }
    final cacheDir = Directory(p.join(home, '.flutter_shadcn', 'cache'));
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return File(p.join(cacheDir.path, 'version_check.json'));
  }

  /// Saves version check data to cache
  Future<void> _saveCacheData(
      DateTime timestamp, bool hasUpdate, String latestVersion) async {
    final cacheFile = _versionCacheFile();
    final data = {
      'lastCheck': timestamp.toIso8601String(),
      'hasUpdate': hasUpdate,
      'latestVersion': latestVersion,
      'currentVersion': currentVersion,
    };
    await cacheFile.writeAsString(json.encode(data));
  }
}
