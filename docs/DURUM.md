Şu an: Ekran + kamera kutusu birleştirme hatasının (-11841 AVErrorInvalidVideoComposition) kök nedeni kod düzeyinde bulundu ve düzeltildi: kamera izi kompozisyona ekran süresinden uzun yerleşiyor ve video talimatları kompozisyonun tamamını kapsamıyordu; ayrıca insertTimeRange'in baştaki boşluğu sessizce yutması yüzünden pozitif offset'li tüm ikincil izler (kamera/mikrofon/sistem sesi) hizadan kayıyordu. Her iki hata da tüm kayıt modlarında (ekran, kamera, ses) giderildi; 3 yeni regresyon testiyle birlikte tüm test paketi geçti. Düzeltmeler Build 1.0 (202608031748) olarak TestFlight iç testine yüklendi ve kullanıcı gerçek cihazda doğruladı: kamera görüntüsü artık ekran kaydı videosunda görünüyor. Günlerdir süren sorun kapandı; değişiklikler git'e commit edildi.

- [x] Ekran+kamera birleşik export'un -11841 hatası: talimat kapsaması + iz kırpma düzeltmesi (2026-08-03 17:50 kaydı)
- [x] insertTimeRange boşluk-yutma hatası: ekran/kamera/ses modlarındaki tüm ikincil iz yerleşimleri düzeltildi
- [x] Duraklat/devam-et ve başlat/durdur akışları gözden geçirildi — ek hata bulunmadı
- [x] Yeni TestFlight build'i çıkarıldı ve iç teste yüklendi: Build 1.0 (202608031748)
- [x] Kullanıcı gerçek cihazda doğruladı: ekran + kamera kutusu kaydında kamera görüntüsü nihai videoda görünüyor (Build 202608031748)
- [ ] Gerçek cihazda kulaklık takıp çıkararak kullanıcı doğrulaması (önceki açık madde)
- [ ] TestFlight'ta ekran kaydı izni önbellek düzeltmesinin doğrulanması (önceki açık madde)
- [ ] Kamera kopma senaryosu ayrıca ele alınmadı (kasıtlı: hâlâ sert durdurur)
- [x] Değişiklikler git'e commit edildi (birikmiş önceki düzeltmelerle birlikte)
- [x] App Store hazırlık denetimi: ayarlar, dosya sistemi, kısayollar, kota — sağlam; 5 sağlamlaştırma yapıldı (StoreKit Transaction.updates dinleyicisi, öne-gelişte erişim tazeleme, fatalError kaldırma, güvenli indeks, dosya adı nokta temizliği) — commit bekliyor
- [x] Dil bütünlüğü doğrulandı: TR+EN 577 anahtar %100 çevrili; tek yerelleştirmesiz metin ("Hata: ...") düzeltildi
- [x] App Store editör denetimi: izin metinleri örnekli ve amaca özel, gizlilik manifestosu/entitlements/2.4.5(i) uyumlu, paywall'a 3.1.2 otomatik yenileme açıklaması eklendi — commit bekliyor
