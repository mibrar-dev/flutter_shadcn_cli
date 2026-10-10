// The `login-01` block fixture: a centred sign-in card.
//
// Layer 4 of the registry: it may import foundation, theme, primitives and
// components, never another block.

import '../../components/button/button.dart';
import '../../components/input/input.dart';
import '../../foundation/gap.dart';

/// The `login-01` public widget. Its preview is itself, so docs and app render
/// exactly the same code.
class Login01 {
  /// Creates the block.
  const Login01();

  /// The submit action.
  Button get action => const Button();

  /// The email field.
  Input get email => const Input();

  /// The layout gap between the rows.
  double get spacing => gapMd;
}
