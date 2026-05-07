import 'dart:io';

class RegistryTrustPolicy {
  const RegistryTrustPolicy._();

  static String? validateRemoteUrl({
    required Uri url,
    required String context,
  }) {
    if (_isLoopback(url)) {
      return null;
    }
    if (url.scheme.toLowerCase() == 'https') {
      return null;
    }
    return '$context must use https unless it targets a loopback development '
        'server: ${url.toString()}';
  }

  static String? validateRemoteRegistryTrust({
    required String namespace,
    required Uri url,
    required String? trustMode,
    required String? trustSha256,
    String trustModeField = 'trustMode',
    String trustSha256Field = 'trustSha256',
  }) {
    final urlError = validateRemoteUrl(
      url: url,
      context: 'Remote registry "$namespace"',
    );
    if (urlError != null) {
      return urlError;
    }

    if (_isLoopback(url)) {
      return null;
    }

    if ((trustMode ?? '').trim().toLowerCase() == 'sha256' &&
        (trustSha256 ?? '').trim().isNotEmpty) {
      return null;
    }
    return 'Remote registry "$namespace" requires $trustModeField "sha256" '
        'and $trustSha256Field before loading components.json.';
  }

  static bool isLoopbackUrl(Uri url) => _isLoopback(url);

  static bool _isLoopback(Uri url) {
    if (url.scheme.toLowerCase() != 'http' &&
        url.scheme.toLowerCase() != 'https') {
      return false;
    }
    final host = url.host.toLowerCase();
    if (host == 'localhost') {
      return true;
    }
    final address = InternetAddress.tryParse(host);
    return address?.isLoopback ?? false;
  }
}
