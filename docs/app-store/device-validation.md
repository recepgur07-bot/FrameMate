# macOS release adayı cihaz doğrulaması

Bu belge tek bir immutable Mac App Store release adayı içindir. Cihaz modeli ve
macOS sürümü yazılabilir; kullanıcı verisi, cihaz kimliği ve erişim bilgisi
yazılmaz.

## Aday kimliği

- Uygulama / bundle ID: FrameMate / `com.recepgur.VideoRecorder`
- Version / build: `DOĞRULANAMADI`
- Archive Info.plist SHA-256: `DOĞRULANAMADI`
- Tarih / doğrulayan: `DOĞRULANAMADI`

## Temel akış ve dayanıklılık

| Kontrol | Mac ve macOS | Sonuç | Kanıt bağlantısı / test adı |
|---|---|---|---|
| Temiz kurulum ve ilk açılış | | `DOĞRULANAMADI` | |
| Onboarding ve ana kayıt akışı | | `DOĞRULANAMADI` | |
| Uygulamayı kapatıp açma / durum geri yükleme | | `DOĞRULANAMADI` | |
| Kamera, mikrofon ve Screen Recording izin reddi/sonradan verme | | `DOĞRULANAMADI` | |
| Kısa ekran, kamera ve ses kaydı | | `DOĞRULANAMADI` | |
| MP4 çıktı: süre, video/audio stream, codec ve dosya boyutu | | `DOĞRULANAMADI` | `ffprobe` çıktısı |
| Ayarlar, gizlilik ve destek URL'leri | | `DOĞRULANAMADI` | |
| IAP satın alma hatası, trial ve Restore Purchases | | `DOĞRULANAMADI` | |

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

- [ ] Bu adayda regresyon bulunmadı.
- [ ] `DOĞRULANAMADI` alanı yok.
- Açık bulgular veya gerekçe: Immutable archive ve gerçek cihaz oturumu henüz
  bu kayda bağlanmadı; bu nedenle release-ready kararı verilemez.
