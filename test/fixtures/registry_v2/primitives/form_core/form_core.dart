import '../clickable.dart';
import '../../theme/theme.dart';

// Fixture primitive that depends on another primitive (primitives/form_core ->
// primitives/clickable) and a layer.
class FormCore {
  const FormCore();
  Clickable get clickable => const Clickable();
  ShadcnTheme get theme => const ShadcnTheme();
}
