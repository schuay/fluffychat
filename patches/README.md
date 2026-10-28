# Matrix SDK token refresh patch

This personal build applies `matrix-sdk-token-refresh.patch` to Matrix SDK
commit `466a60792159b22530e9c043585545ee2e766d0b` (14.0.0).
`pubspec_overrides.yaml` selects the generated `build/matrix-sdk` directory.
Prepare it before dependency resolution in a fresh checkout:

```bash
bash scripts/prepare-matrix-sdk.sh /path/to/matrix-dart-sdk
flutter pub get
```

The source repository must contain the pinned commit. The script reads that
commit without changing the source checkout and refuses to replace an existing
generated directory unless the same patch is already present.

Token refresh updates only the access token, expiry, and refresh token. It does
not rewrite encryption identity or sync state. The update checks the expected
refresh token inside a real SQLite/IndexedDB transaction so a delayed response
cannot overwrite a rotated or cleared session.

The patch includes native token-refresh regression tests and shared box tests.
In the prepared SDK, run:

```bash
dart test test/token_refresh_test.dart test/box_test.dart
dart test test/box_test.dart --platform chrome
```

The SDK's native tests require its usual vodozemac and SQLite setup. See its
`scripts/prepare_vodozemac.sh` and `test/fake_client.dart` for the library path.

# Patched pub.dev packages

`scripts/prepare-pub-packages.sh` downloads pinned pub.dev archives, checks
their sha256, and applies a patch from this directory into `build/<package>`.
`pubspec_overrides.yaml` selects the results. Both patches fix Android builds
against `compileSdk = 37`:

- `flutter-vodozemac-compile-sdk.patch`: cargokit parses `compileSdkVersion`
  (`android-37.0`) as an integer; read `compileSdk` instead.
- `flutter-shortcuts-new-compile-sdk.patch`: compile against 36; its AndroidX
  dependencies require at least 34.

Run `flutter pub get` after changing `pubspec_overrides.yaml`; `flutter build`
does not re-resolve on its own.

For the personal Android release, use the existing Android SDK and the personal
signing key:

```bash
ORG_GRADLE_PROJECT_personalRelease=true \
ORG_GRADLE_PROJECT_personalKeystore=/path/to/keystore.p12 \
ORG_GRADLE_PROJECT_personalKeyAlias=<alias> \
ORG_GRADLE_PROJECT_personalKeyPasswordFile=/path/to/password-file \
  flutter build apk --release --target-platform android-arm64
```

This builds `cx.linke.fluffychat`. The password file holds the keystore
password, which is also used as the key password. Every build must use the same
key, or installed copies cannot update in place.
