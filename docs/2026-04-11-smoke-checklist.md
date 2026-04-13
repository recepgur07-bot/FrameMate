# 2026-04-11 Smoke Checklist

Bu turdaki amaç, kayıt yaşam döngüsünün kullanıcı gözünden güven verdiğini doğrulamak:

- `Cmd+Ctrl+R` ile uygulama dışından başlat.
- Aynı kısayolla durdur.
- Başlangıç ve bitiş sesini doğrula.
- Final çıktının tek `.mp4` olarak geldiğini doğrula.
- `Kayıt Tamamlandı` panelinden:
  - `Aç`
  - `Klasörde Göster`
  - `Yeniden Adlandır`
  - `Farklı Kaydet`
  aksiyonlarını tek tek dene.
- Ayarlar’dan varsayılan kayıt klasörünü değiştir, yeni kaydın oraya gitmesini doğrula.
- Menü bardan:
  - `Kaydı Başlat/Durdur`
  - `Ana Pencereyi Göster`
  - `Son Kaydı Aç`
  - `Klasörde Göster`
  aksiyonlarını dene.

Önerilen varyasyon matrisi:

- Yatay kamera
- Dikey kamera
- Yatay ekran
- Dikey ekran
- Mikrofon açık / kapalı
- Sistem sesi açık / kapalı
- Kısa kayıt
- Biraz uzun kayıt

Bu turda otomasyonla doğrulananlar:

- Özel kayıt klasörü seçimi
- Yeniden adlandırma
- Farklı kaydet
- Menü bar hazır/kayıt durumları
- Mevcut export/finalize hattı ve preset matrisi için hedefli XCTest setleri
