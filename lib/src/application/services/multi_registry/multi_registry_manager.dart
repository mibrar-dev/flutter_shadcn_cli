import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/add_resolution_service.dart';
import 'package:flutter_shadcn_cli/src/application/dto/add_request.dart';
import 'package:flutter_shadcn_cli/src/application/dto/qualified_component_ref.dart';
import 'package:flutter_shadcn_cli/src/application/dto/registry_summary.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/core/utils/component_ref_normalizer.dart';
import 'package:flutter_shadcn_cli/src/core/utils/path_utils.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_entry.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_loader.dart';
import 'package:flutter_shadcn_cli/src/init_action_engine.dart';
import 'package:flutter_shadcn_cli/src/inline_action_journal.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_exception.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/state.dart';
import 'package:flutter_shadcn_cli/src/version_manager.dart';
import 'package:path/path.dart' as p;

part 'multi_registry_init_part.dart';
part 'multi_registry_add_part.dart';
part 'multi_registry_assets_part.dart';
part 'multi_registry_directory_part.dart';

class MultiRegistryManager {
  final String targetDir;
  final bool offline;
  final bool skipIntegrity;
  final CliLogger logger;
  final String directoryUrl;
  final String? directoryPath;
  final String? registryPathOverride;
  final String? registryUrlOverride;
  final RegistryDirectoryClient directoryClient;
  final InitActionEngine initActionEngine;
  final AddResolutionService addResolutionService;

  RegistryDirectory? _directoryCache;
  final Map<String, RegistrySource> _sources = {};
  final Map<String, Registry> _registryCache = {};
  String? _projectRootCache;
  ShadcnConfig? _configCache;

  MultiRegistryManager({
    required this.targetDir,
    required this.offline,
    this.skipIntegrity = false,
    required this.logger,
    this.directoryUrl = defaultRegistriesDirectoryUrl,
    this.directoryPath,
    this.registryPathOverride,
    this.registryUrlOverride,
    RegistryDirectoryClient? directoryClient,
    InitActionEngine? initActionEngine,
    AddResolutionService? addResolutionService,
  })  : assert(
          registryPathOverride == null || registryUrlOverride == null,
          'registryPathOverride and registryUrlOverride cannot both be set.',
        ),
        directoryClient = directoryClient ?? RegistryDirectoryClient(),
        initActionEngine = initActionEngine ?? InitActionEngine(),
        addResolutionService =
            addResolutionService ?? const AddResolutionService();

  void close() {
    directoryClient.close();
    initActionEngine.close();
  }

  static QualifiedComponentRef? parseComponentRef(String token) {
    return AddResolutionService.parseQualifiedComponentRef(token);
  }

  String get _projectRoot {
    return _projectRootCache ??= findProjectRootFrom(targetDir);
  }

  Future<ShadcnConfig> _loadProjectConfig() async {
    final cached = _configCache;
    if (cached != null) {
      return cached;
    }
    final config = await ShadcnConfig.load(_projectRoot);
    _configCache = config;
    return config;
  }

  Future<void> _saveProjectConfig(ShadcnConfig config) async {
    await ShadcnConfig.save(_projectRoot, config);
    _configCache = config;
    _sources.clear();
  }
}

class DiscoveryRegistryTarget {
  final String namespace;
  final String registryBase;
  final String registryId;
  final String indexPath;
  final String? indexSchemaPath;

  const DiscoveryRegistryTarget({
    required this.namespace,
    required this.registryBase,
    required this.registryId,
    required this.indexPath,
    required this.indexSchemaPath,
  });
}
