# macOS release adayı cihaz doğrulaması

Bu belge tek bir immutable Mac App Store release adayı içindir. Cihaz modeli ve
macOS sürümü yazılabilir; kullanıcı verisi, cihaz kimliği ve erişim bilgisi
yazılmaz.

## Aday kimliği

- Uygulama / bundle ID: FrameMate / `com.recepgur.VideoRecorder`
- Version / build: `1.0 (202608041156)` — App Store Connect'e yüklendi ve `VALID`; iç TestFlight/gerçek cihaz doğrulaması açık
- Archive Info.plist SHA-256: `98223799e0f57e35cfb9a89bf6485503ce21dea25a5925eb601064ae678aef4b`
- Archive: `build/release/FrameMate-1.0-202608041156.xcarchive`
- Package SHA-256: `50bc8f6c9fba59ca92f0a70f42769a252aed133b259239b6cdfabe1c8bc4fc3b`
- Tarih / doğrulayan: `2026-08-04 / Codex` — yerel imza/export doğrulaması ve App Store Connect yükleme kontrolü

`xcodebuild archive` ve `xcodebuild -exportArchive` başarıyla tamamlandı. Archive,
`Apple Distribution: RECEP GUR (9MA297YYN2)` ile; package ise `3rd Party Mac Developer
Installer: RECEP GUR (9MA297YYN2)` ile imzalandı. Kullanılan profile UUID:
`23fe9adf-478d-4477-84b4-e5323bf9ebbe` (2027-04-16'ya kadar geçerli).

## Temel akış ve dayanıklılık

| Kontrol | Mac ve macOS | Sonuç | Kanıt bağlantısı / test adı |
|---|---|---|---|
| Yerel otomatik kalite kapısı | macOS / Xcode host | `DOĞRULANDI` | `tools/mobile-quality-gate.sh`: build, test, gitleaks, SwiftFormat, SwiftLint, Ruby kontrolleri |
| Temiz kurulum ve ilk açılış | | `DOĞRULANAMADI` | |
| Onboarding ve ana kayıt akışı | | `DOĞRULANAMADI` | |
| Uygulamayı kapatıp açma / durum geri yükleme | | `DOĞRULANAMADI` | |
| Kamera, mikrofon ve Screen Recording izin reddi/sonradan verme | | `DOĞRULANAMADI` | |
| Kısa ekran, kamera ve ses kaydı | | `DOĞRULANAMADI` | |
| MP4 çıktı: süre, video/audio stream, codec ve dosya boyutu | | `DOĞRULANAMADI` | `ffprobe` çıktısı |
| Ayarlar, gizlilik ve destek URL'leri | | `DOĞRULANAMADI` | |
| Yerel 3 günlük erişim, aylık 7 dakika kota, IAP satın alma hatası ve Restore Purchases | | `DOĞRULANAMADI` | |

## Erişilebilirlik

| Kontrol | Sonuç | Bulgu / kanıt |
|---|---|---|
| VoiceOver: odak sırası ve anlamlı etiketler | `DOĞRULANAMADI` | |
| Klavye ile ana akış ve görünür odak | `DOĞRULANAMADI` | |
| Kontrast, pencere boyutu ve büyük metin | `DOĞRULANAMADI` | |
| Frame Coach sesli yönergeleri ve Reduce Motion | `DOĞRULANAMADI` | |

## Koşullu akışlar

- [x] Hesap yok; hesap silme veya Sign in with Apple kapsam dışı.
- [ ] IAP: satın alma, başarısız satın alma, restore ve mevcut entitlement
  release adayı üzerinde doğrulandı.
- [x] Reklam, backend ve ağ hatası akışı yok.
- [ ] Kamera/mikrofon/Screen Recording/AX izin metinleri ve ret akışları temiz
  macOS kullanıcı hesabında doğrulandı.

## Sonuç

- [x] Immutable archive ve App Store package üretildi; imza/profile kanıtı kayda bağlandı.
- [x] `1.0 (202608041156)` App Store Connect'e yüklendi; build durumu `VALID`, iç test dağıtımı ve gerçek cihaz doğrulaması açık.
- [ ] `DOĞRULANAMADI` alanı yok.
- Açık bulgular veya gerekçe: Gerçek cihaz/VoiceOver/IAP akışı ve App Store Connect
  metadata/App Privacy/hukuki son onayları henüz bu archive'a bağlanmadı; release-ready
  kararı henüz verilemez.
