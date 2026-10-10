import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_components.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_diagnostics.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_models.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_project.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_tooling.dart';

export 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_models.dart';

/// Every command reference group, in the order the docs render them.
///
/// The groups are split across `command_metadata_*` files to keep each file
/// small; this list is the single entry point used by the docs generator, the
/// command registry and the command-matrix test.
const List<CliCommandGroupMeta> cliCommandMetadata = [
  componentsCommandGroup,
  projectCommandGroup,
  diagnosticsCommandGroup,
  toolingCommandGroup,
  advancedCommandGroup,
];
