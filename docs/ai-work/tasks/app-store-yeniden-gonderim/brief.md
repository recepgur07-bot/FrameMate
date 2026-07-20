# Görev Özeti

## Kullanıcı isteği
FrameMate (macOS ekran/kamera/ses kaydedici) App Store'dan iki kez ret aldı (2026-05-08 Guideline 5.1.1(ii) mikrofon purpose string; 2026-05-10 Guideline 2.4.5(i) app container'a kayıt). Kullanıcı mevcut halin yeniden gönderime hazır olup olmadığından emin değil; eksiklerin bulunup güvenli bir yeniden gönderim yolu çizilmesini istiyor.

## Hedef
Yeniden gönderim öncesi tüm bilinen ret nedenlerinin gerçek (release, sandbox) derlemede doğrulanmış şekilde kapatılması ve yeni ret riski taşıyan tutarsızlıkların giderilmesi; ardından App Store'a yeniden gönderim.

## Kapsam dışı
- Yeni özellik geliştirme.
- iOS/başka platform çalışması.

## Kısıtlar
- Kullanıcı VoiceOver kullanıcısı; tüm doğrulama adımları klavye/VoiceOver ile yapılabilir olmalı.
- Kod değişikliğine yalnız kullanıcı onaylı handoff.md ile başlanır.

## Kabul ölçütleri
- [ ] Mikrofon (ve diğer tüm) purpose string'leri derlenmiş uygulamada TR+EN örnekli görünür.
- [ ] Release sandbox derlemede kısa bir kayıt `~/Movies/Video Recorder` altına düşer; "Farklı Kaydet" ve "Finder'da Göster" çalışır.
- [ ] docs/app-review-notes.md uygulamanın gerçekten istediği izinlerle birebir örtüşür (bayat Accessibility maddesi kaldırılır).
- [ ] IAP akışı review ortamında çalışır: paywall, Restore Purchases, gizlilik + EULA linkleri; ASC abonelik meta verisinde de linkler tanımlı.
- [ ] Mayıs'tan beri commit edilmemiş ~400 satırlık değişiklik test edilip commit edilir; build numarası güncellenir.
- [ ] App Store Connect'te ret mesajına yapılan düzeltmeleri özetleyen yanıt yazılır ve yeniden gönderim yapılır.

## Roller
- Koordinatör: claude
- Planlayıcı: claude
- İnceleyenler: codex, antigravity
- Sentezleyici: claude
- Uygulayıcı: Kullanıcı onayı sonrası atanacak
- Doğrulayıcı: Uygulayıcıdan farklı bir araç, uygulama sonrası atanacak
