import '../input/input.dart';
import '../../primitives/form_core/form_core.dart';

// Fixture component with a component -> component dependency (text_area ->
// input) and a primitive dependency.
class TextArea {
  const TextArea();
  Input get input => const Input();
  FormCore get form => const FormCore();
}
