# FrameMate proje geliştirme kurulumu

## Başlangıç profili

- [x] **App Store Ready:** macOS App Store hedefi; metadata, ekran görüntüsü,
  App Review kanıtı, release öncesi kalite kapısı ve CI etkin.

## Proje

- Platform: macOS 14.0+
- Bundle ID: `com.recepgur.VideoRecorder`
- Apple Developer Team: `9MA297YYN2` (yalnız kimlik; sertifika veya anahtar yok)
- Dağıtım hedefi: Mac App Store
- Signing: manual App Store distribution; App Sandbox ve Hardened Runtime etkin

## Etkin araçlar ve kanıtlar

- [x] Unit ve proje iş akışı testleri (`FrameMate` scheme)
- [x] GitHub Actions kalite kapısı
- [x] gitleaks secret taraması
- [x] Türkçe ve İngilizce lokalizasyon ile mağaza metadata'sı
- [x] Lokalizasyon kataloğu ve Mac App Store screenshot üretim hattı testleri
- [x] Kamera, mikrofon, ekran kaydı ve erişilebilirlik izin akışları
- [x] Medya çıktısı için `ffprobe` doğrulama aracı
- [x] StoreKit / IAP (yıllık ve ömür boyu Pro)
- [x] App Review reviewer journey, cihaz doğrulama ve SDK/privacy envanteri
- [x] Privacy manifest ve App Sandbox entitlement denetimi

## Koşullu veya kapsam dışı araçlar

- [x] SwiftFormat — mevcut Swift 5 stili için boş satır ve trailing-space
  doğrulaması CI'da zorunlu; daha geniş format dönüşümü ayrı bir baseline işi.
- [x] SwiftLint — üretim kaynaklarında force unwrap/cast/try, kullanılmayan
  import, `TODO`, `fatalError` mesajı ve `isEmpty` tercihlerini denetler.
- [ ] UI testleri — **koşullu:** mevcut macOS izin/TCC ve medya donanımı
  akışları gerçek cihaz kanıtıyla doğrulanır; deterministik UI otomasyonu
  eklendiğinde etkinleştirilecek.
- [ ] XcodeGen — **mevcut:** `project.yml` kaynak proje tanımıdır; bu görevde
  proje yeniden üretilmedi.
- [ ] Maestro / fiziksel iOS cihaz testi / iOS simülatörü — **kapsam dışı:**
  uygulama yalnız macOS hedefler.
- [ ] Widget veya diğer extension, bildirim, backend, analytics/crash SDK,
  hesap oluşturma, reklam — **kapsam dışı:** kaynak ve bağımlılık envanterinde
  bu yüzeyler yok.
- [ ] mitmproxy — **kapsam dışı:** uygulamanın ağ/backend akışı yok.
- [ ] iOS release-gate runner — **kapsam dışı:** ortak 05 runner'ı yalnız
  `platform: ios` adaylarını kabul eder. Mac App Store adayını yanlış bir iOS
  archive şemasıyla denetlememek için onun kanıt şablonları macOS'a uyarlandı.
- [ ] Notarization / DMG / PKG — **kapsam dışı:** yalnız doğrudan dağıtım için
  gerekir; seçili dağıtım modeli Mac App Store'dur.

## Doğrulama komutları

- Build: `xcodebuild build -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`
- Test: `xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`
- Kalite kapısı: `bash tools/mobile-quality-gate.sh --project VideoRecorder.xcodeproj --scheme FrameMate --destination 'platform=macOS'`
- Medya örneği: `ffprobe -v error -show_format -show_streams <kayit.mp4>`
- Reviewer journey: `docs/app-store/reviewer-journey.md`
- Cihaz/erişilebilirlik kanıtı: `docs/app-store/device-validation.md`
- Privacy SDK envanteri: `docs/app-store/privacy-sdk-inventory.json`

## Release sınırı

Bu dosyalar yalnız yerel denetim ve kanıt toplama içindir. Archive, gerçek
macOS cihaz doğrulaması, App Store Connect ve hukuki beyanlar kanıtlanmadan
FrameMate "hazır" sayılmaz. Yükleme, incelemeye gönderme ve yayınlama bu
kurulumun kapsamı dışındadır.
