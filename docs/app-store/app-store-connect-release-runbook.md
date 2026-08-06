# FrameMate App Store Connect Release Runbook

Bu dosya, App Store Connect işlemlerinin tekrar tekrar keşfedilmesini önleyen
operasyonel kontrol listesidir. Kod derleme veya App Review gönderme yetkisi
vermez; yalnızca hangi ekranda neyin doğrulanacağını sabitler.

## Kimlikler

| Ürün | App Store Connect ID | Product ID |
| --- | --- | --- |
| Uygulama | `6762084840` | `com.recepgur.VideoRecorder` |
| Yıllık abonelik | `6762824043` | `com.recepgur.videorecorder.pro.yearly` |
| Lifetime non-consumable | `6762823649` | `com.recepgur.videorecorder.pro.lifetime` |

## Değişmez kurallar

- Doğrudan `/pricing-matrix` ekranı, tek başına kaydın yapıldığına dair kanıt
  değildir. Fiyat ancak ürün detayındaki fiyat akışında `Next` → inceleme →
  `Confirm` tamamlandıktan ve ürün detayından yeniden okunup doğrulandıktan
  sonra uygulanmış kabul edilir.
- ABD taban fiyatı ile Türkiye özel fiyatı ayrı ayrı doğrulanır; yalnızca
  fiyat menüsünde seçilmiş görünmesi yeterli değildir.
- `Add for Review`, `Update Review` veya uygulamayı gönderme düğmeleri,
  kullanıcı açıkça istemeden kullanılmaz.
- App Store Connect’te aynı anda tek aktif sekme kullanılır. Her tıklamadan
  önce güncel ekran durumu okunur; açılan menülerin yüklenmesi beklenir.
- Ürün, fiyat türü veya mevcut durum beklenenden farklıysa fiyat tahmini
  yapılmaz; işlem durdurulup durum yeniden incelenir.

## Yıllık abonelik fiyat akışı

Mevcut fiyatı düzenlemek için:

1. Yıllık ürün detayını aç: `/apps/6762084840/distribution/subscriptions/6762824043`.
2. `Subscription Prices` → `Starting Price` → `Edit Price` yolunu kullan.
3. Baz fiyat değişmiyorsa `Keep the calculated prices...` seçeneğini koru ve
   `Next` ile ülke fiyatları ekranına geç.
4. `Türkiye (TRY)` satırındaki fiyat düğmesini açıp hedef fiyatı seç.
5. `Next` → fiyat özeti → `Confirm` adımlarını tamamla.
6. `Starting Price` özetini yeniden açıp hem `United States (USD)` hem de
   `Türkiye (TRY)` satırlarını kontrol et.

ABD taban fiyatı da değişecekse, aynı düzenleme akışında baz fiyatı değiştirip
Türkiye satırını ayrıca manuel olarak ayarla; otomatik hesaplanan Türkiye
fiyatını hedef fiyat sanma.

## Lifetime fiyat akışı

Mevcut fiyatı olan bir lifetime üründe:

1. Lifetime ürün detayını aç: `/apps/6762084840/distribution/iaps/6762823649`.
2. `Price Schedule` → `Schedule a price change` → `Custom Price Change` yolunu
   kullan.
3. Etkinlik tarihini seç; belirli ülke yönetiminde yalnızca gerekli ülkeyi
   (örneğin Türkiye) seç.
4. `Calculate Prices` ekranında ülke olarak `Türkiye (TRY)` seç, fiyatı ayarla.
5. `Next` → ülke fiyatları özeti → `Next` → tarihli değişiklik özeti →
   `Confirm` adımlarını tamamla.

ABD taban fiyatı da değişecekse:

1. `Base Country or Region` → `Edit` yolunu kullan.
2. Apple’ın eski fiyat planlarını sileceğini gösteren onay kutusunu yalnızca
   bu değişiklik gerçekten isteniyorsa işaretle.
3. ABD baz fiyatını seç; sonraki ülke matrisi ekranında Türkiye satırını da
   hedef özel fiyatla değiştir.
4. `Next` → `Confirm` sonrasında ürün detayından ABD ve Türkiye fiyatlarını
   yeniden oku.

## Son doğrulama kapısı

Her fiyat işlemi sonunda aşağıdaki kanıtlar alınmadan iş tamamlanmış sayılmaz:

- Ürün detay sayfası yeniden yüklendi.
- ABD satırı hedef baz fiyatı gösteriyor.
- Türkiye satırı hedef özel fiyatı gösteriyor.
- Fiyat planında yanlışlıkla eklenmiş ikinci bir değişiklik veya tarih yok.
- Ürün statüsü ve `Add for Review` durumu not edildi; gönderme yapılmadı.

## Bu turdaki gecikmenin kökü

İlk denemede doğrudan fiyat matrisi, kaydetme akışı sanıldı. Oysa Apple’ın
abonelik, non-consumable ve mevcut fiyat değişikliği ekranları farklı. Ayrıca
ülke listesi dar tarayıcı görünümünde sanallaştırılmıştı ve fiyat menüleri
asenkron yüklendi. Bu nedenle yanlış ekranın doğrulanması, ülke satırının
manuel bulunması ve sonradan ürün detayından gerçek kaydın kontrol edilmesi
gerekti. Yukarıdaki ürün kimlikleri, sabit ekran yolları ve iki aşamalı
doğrulama bu keşif maliyetini ortadan kaldırmak için eklendi.
