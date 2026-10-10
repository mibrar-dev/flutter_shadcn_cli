// The `dashboard-01` block fixture: a two-file block.
//
// The second part lives in the same directory and is imported relatively, so
// the manifest must list both files and the CLI must copy both.

import '../../components/button/button.dart';
import '../../components/text_area/text_area.dart';
import '../../foundation/gap.dart';
import 'dashboard_01_table.dart';

/// The `dashboard-01` public widget.
class Dashboard01 {
  /// Creates the block.
  const Dashboard01();

  /// The table part of this block.
  Dashboard01Table get table => const Dashboard01Table();

  /// The export action.
  Button get action => const Button();

  /// The notes field.
  TextArea get notes => const TextArea();

  /// The layout gap between the tiles.
  double get spacing => gapSm;
}
