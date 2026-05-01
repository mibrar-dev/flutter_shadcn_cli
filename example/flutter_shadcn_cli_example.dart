/// Example usage of flutter_shadcn_cli.
///
/// This CLI is designed to be run from the command line, not imported
/// as a library. Below are the common commands you'll use.
// ignore_for_file: dangling_library_doc_comments
///
/// ## Installation
///
/// ```bash
/// dart pub global activate flutter_shadcn_cli
/// ```
///
/// ## Initialize a project
///
/// Run this in your Flutter project root:
///
/// ```bash
/// flutter_shadcn init
/// ```
///
/// Initialize a specific registry namespace:
///
/// ```bash
/// flutter_shadcn init shadcn --yes
/// ```
///
/// ## Add components
///
/// ```bash
/// # Add a single component
/// flutter_shadcn add button
///
/// # Add a namespaced component
/// flutter_shadcn add @shadcn/button
///
/// # Add multiple components
/// flutter_shadcn add button dialog accordion
/// ```
///
/// ## Remove components
///
/// ```bash
/// flutter_shadcn remove button
/// ```
///
/// ## Check project status
///
/// ```bash
/// flutter_shadcn doctor
/// ```
///
/// ## Using theme presets programmatically
///
/// If you need to access theme data in your code:
import 'package:flutter_shadcn_cli/flutter_shadcn_cli.dart';

void main() {
  // List all available theme presets
  for (final preset in registryThemePresetsData) {
    print('Theme: ${preset.name} (${preset.id})');
    print('  Light primary: ${preset.light['primary']}');
    print('  Dark primary: ${preset.dark['primary']}');
  }

  // Find a specific theme
  final blueTheme = registryThemePresetsData.firstWhere(
    (preset) => preset.id == 'blue',
  );

  print('\nBlue theme colors:');
  print('  Background (light): ${blueTheme.light['background']}');
  print('  Background (dark): ${blueTheme.dark['background']}');
}
