/// Encodes query parameters for non-HTTP URI schemes such as `mailto:`.
///
/// `Uri(queryParameters: ...)` uses form-style `+` for spaces, which the
/// `url_launcher` documentation warns can be interpreted literally by some
/// non-HTTP handlers. Percent-encode each key/value instead.
String encodeNonHttpQueryParameters(Map<String, String> params) {
  return params.entries
      .map(
        (entry) =>
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
      )
      .join('&');
}
