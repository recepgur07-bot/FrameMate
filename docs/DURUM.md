Şu an: Build 1.0 (202607301534) TestFlight iç test kullanıcılarına dağıtıldı — satın alma akışı ve ekran kaydı izin algılama düzeltmesi dahil, yeni kullanıcı deneyimiyle birebir aynı. Kayıt sırasında sadeleştirilmiş ekran ve mikrofon-kopma senaryosu için otomatik duraklatma özellikleri kod incelemesi/build/test ile doğrulandı; gerçek cihazda (kulaklık takıp çıkararak) kullanıcı testi bekleniyor.

- [x] Kayıt başladığında ekranda yalnız süre + duraklat/durdur kalması
- [x] Mikrofon (örn. kulaklık) koptuğunda kaydı sert durdurmak yerine otomatik duraklat + "yeniden tak" istemi
- [x] İç test build'inde satın alma akışının gerçek kullanıcı deneyimiyle aynı görünmesi (FrameMateDisablePurchasesForInternalTesting artık build sırasında true yapılmıyor)
- [x] Ekran kaydı izni Ayarlar'dan sonradan açıldığında uygulamanın bunu görmemesi sorunu: öne dönüşte SCShareableContent ile zorla yeniden kontrol eklendi
- [ ] Gerçek cihazda kulaklık takıp çıkararak kullanıcı doğrulaması
- [ ] Kamera kopma senaryosu ayrıca ele alınmadı (kasıtlı: hâlâ sert durdurur, video kaynağı kaybolduğu için kurtarılamaz)
- [ ] TestFlight'ta gerçek cihazda ekran kaydı izni önbellek düzeltmesinin doğrulanması (izin ver → kapat/aç → izin görünür mü)
