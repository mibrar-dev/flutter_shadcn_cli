import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_directory_client.dart';
import 'package:test/test.dart';

void main() {
  test('default remote registry base points at the live registry repo', () {
    expect(
      resolveRemoteBase(null),
      'https://raw.githubusercontent.com/ibrar-x/shadcn-flutter-registry/master',
    );
  });

  test('default registries directory is served from the live registry repo',
      () {
    expect(
      defaultRegistriesDirectoryUrl,
      'https://raw.githubusercontent.com/ibrar-x/shadcn-flutter-registry/master/registries.v2.json',
    );
  });
}
