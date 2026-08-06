# Mac App Store reviewer journey

Bu kayıt belirli bir release adayına bağlanır. Gerçek kullanıcı verisi, parola,
API anahtarı veya sertifika eklenmez.

## Aday kimliği

- Uygulama / bundle ID: FrameMate / `com.recepgur.VideoRecorder`
- Version / build: `1.0 (202608041156)` — App Store Connect'e yüklendi ve `VALID`; iç TestFlight/gerçek cihaz doğrulaması açık.
- Archive Info.plist SHA-256: `98223799e0f57e35cfb9a89bf6485503ce21dea25a5925eb601064ae678aef4b`
- Package: `build/release/FrameMate-1.0-202608041156.pkg` — SHA-256 `50bc8f6c9fba59ca92f0a70f42769a252aed133b259239b6cdfabe1c8bc4fc3b`
- Hazırlayan / tarih: `Codex / 2026-08-04` — archive/export doğrulaması ve ASC yükleme sonucu kaydedildi; release sahibi doğrulaması bekliyor.

Archive `Apple Distribution: RECEP GUR (9MA297YYN2)` ve package installer sertifikasıyla
başarıyla üretildi. Kullanılan profile UUID `23fe9adf-478d-4477-84b4-e5323bf9ebbe`.

## Bir dakikalık özet

- Değer: Kamera, mikrofon ve ekranı yerel MP4 kaydı olarak birleştirir; Frame
  Coach, görme engelli veya az gören üreticiler için sesli kadraj yardımı sunar.
- Ana akış: Onboarding → gereken macOS izinleri → kayıt modu ve kaynak seçimi
  → kısa kayıt → durdurma → Save As veya Finder'da gösterme.
- Backend: Yok. Kayıtlar kullanıcının Mac'inde saklanır; hesap gerekmez.
- Görünmeyen özellik: Sistem geneli kısayol yalnız Ayarlar'da "Keyboard
  Shortcuts" overlay'i kullanıcı tarafından açılırsa Accessibility (AX) izni
  ister. Ana kayıt akışı için zorunlu değildir.

## Erişim

- [x] Login veya demo hesap gerekmiyor.
- [x] Donanım/QR/davet gerekmiyor; kamera veya mikrofon olmayan Mac'te ekran
  kaydı akışı yine incelenebilir.
- [ ] Release adayındaki IAP ürünleri App Store Connect sandbox'ta görünür ve
  satın alma/restore ile doğrulandı — adayla birlikte kanıtlanacak.

## İnceleme adımları

| Sıra | İncelemecinin eylemi | Beklenen sonuç | Kanıt/UI testi |
|---|---|---|---|
| 1 | FrameMate'i aç ve onboarding'i tamamla | Ana kayıt ekranı ve izin açıklamaları görünür | `docs/app-review-notes.md` |
| 2 | Kamera, mikrofon veya Screen Recording iznini ver; ret akışını da bir kez dene | Gerekli izin açıkça açıklanır, reddedilince kurtarma yönlendirmesi sunulur | `device-validation.md` |
| 3 | Kısa kamera veya ekran kaydı başlatıp durdur | Aktif durum ve süre görünür; oynatılabilir yerel MP4 oluşur | `device-validation.md`, `ffprobe` çıktısı |
| 4 | Kaydı kaydet veya Finder'da göster | Kullanıcı görünür klasör ve standart Save As akışı kullanılır | `docs/app-review-notes.md` |
| 5 | Ayarlar'ı aç | Privacy/support, erişilebilirlik ve satın alma kontrolleri görünür | `docs/app-review-notes.md` |
| 6 | Paywall'dan yıllık veya ömür boyu Pro'yu incele ve Restore Purchases'ı dene | Ürünler, fiyat/yenileme bilgisi ve restore akışı görünür | IAP cihaz kanıtı gerekli |

## Gelir modeli

- [x] Hesap gerekmeden başlar: ilk 3 gün sınırsız yerel deneme, sonrasında her ay
  otomatik yenilenen 7 dakikalık ücretsiz kayıt kotası (cihaz üzerinde, StoreKit'e
  dokunmaz).
- [x] IAP/abonelik var: yıllık Pro (App Store introductory offer/deneme yok — ücretsiz
  deneyim yukarıdaki yerel modelle sağlanıyor) ve ömür boyu Pro.
- [x] Paywall, kayıt başlatıldığında aktif entitlement yoksa ve Ayarlar'dan
  erişilebilir.
- [x] Restore Purchases, privacy ve Apple standard EULA bağlantıları paywall'da
  yer alır.
- [ ] Her ürün release build'de görünür ve işlevsel — aday cihaz kanıtı gerekli.
- [ ] App Review Notes bu adayın IAP test yoluyla eşleştirildi — adayla gözden
  geçirilecek.

## Gönderim öncesi onay

- [ ] `DOĞRULANAMADI` alanı yok.
- [ ] `docs/app-review-notes.md` bu adayın gerçek davranışıyla yeniden eşleşti.
- [ ] Açık hata veya ulaşılamaz akış yok.
