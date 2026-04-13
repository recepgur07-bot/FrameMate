fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac doctor

```sh
[bundle exec] fastlane mac doctor
```

Fastlane ortam kontrolu

### mac certificates

```sh
[bundle exec] fastlane mac certificates
```

App Store sertifika/provision profile cek

### mac setup_certificates

```sh
[bundle exec] fastlane mac setup_certificates
```

Ilk kurulum: yeni appstore certificate/profile olustur

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Mac icin internal TestFlight build yukle

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
