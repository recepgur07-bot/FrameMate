# Uygulama Planı

## Önerilen yaklaşım
Yeniden gönderimden önce "kanıtla, sonra gönder" turu: geçmiş iki ret nedeninin düzeltmeleri kod düzeyinde mevcut, ancak hiçbiri gerçek release/sandbox derlemede uçtan uca doğrulanmış değil ve değişiklikler 2026-05-13'ten beri commit edilmemiş durumda. Önce depo hijyeni (test + commit), sonra derlenmiş uygulamada iki ret senaryosunun bire bir tekrarı, sonra metadata/inceleme notu tutarlılık taraması, en son ASC yanıtı + yeniden gönderim.

## Etkilenen alanlar
- Resources/Info.plist, Sources/VideoRecorderApp/InfoPlist.xcstrings (purpose string'ler)
- VideoRecorder.entitlements (sandbox + movies read-write; doğru görünüyor)
- RecorderViewModel.swift / kayıt hedef klasörü, NSSavePanel akışı
- docs/app-review-notes.md (bayat Accessibility izni iddiası — uygulama artık Accessibility API kullanmıyor, AXIsProcessTrusted çağrısı yok)
- fastlane metadata + ASC abonelik meta verisi (EULA/gizlilik linkleri)

## Adımlar
1. Depo hijyeni: `swift test` (veya fastlane test lane) çalıştır; geçiyorsa Mayıs'tan beri bekleyen değişiklikleri anlamlı commit'lere böl ve commit et.
2. Bayat inceleme notunu düzelt: docs/app-review-notes.md'den Accessibility izin maddesini kaldır (uygulama istemiyor; reviewer kafa karışıklığı / güven kaybı riski).
3. Release derleme + gerçek doğrulama (kullanıcı ile birlikte, VoiceOver ile yapılabilir):
   a. İlk açılışta mikrofon/kamera/ekran izin diyaloglarında yeni örnekli metinlerin göründüğünü doğrula.
   b. Kısa bir kayıt yap; dosyanın `~/Movies/Video Recorder` altına düştüğünü, "Farklı Kaydet" ve "Finder'da Göster"in çalıştığını doğrula.
   c. Paywall'ı review-benzeri ortamda aç: Restore Purchases, gizlilik + EULA linkleri tıklanabilir; FrameMateDisablePurchasesForInternalTesting=false olduğunu derlenmiş Info.plist'te teyit et.
4. Metadata taraması: ASC'de abonelik grubunda EULA/gizlilik linkleri, ekran görüntülerinin güncel UI ile eşleşmesi, App Privacy beyanının PrivacyInfo.xcprivacy ile tutarlılığı.
5. CFBundleVersion'ı yeni bir değere yükselt, arşivle, ASC'ye yükle.
6. ASC'de ret mesajına kısa bir yanıt yaz: 2.4.5(i) için varsayılan `~/Movies/Video Recorder` + Save dialog çözümünü, 5.1.1(ii) için yeni purpose string'leri açıkla; app-review-notes içeriğini Review Notes alanına koy. Yeniden gönder.

## Riskler ve açık sorular
- İki aydır commit edilmemiş büyük diff: hangi parçaların bilinçli, hangilerinin yarım kaldığı belirsiz; commit öncesi diff gözden geçirilmeli.
- ScreenCaptureKit/sistem sesi: reviewer farklı macOS sürümünde test edebilir; LSMinimumSystemVersion 14.0 ile davranış farkları.
- Klasör adı "Video Recorder" ile uygulama adı "FrameMate" farklı; ret nedeni olmaz ama nota bir cümle eklenebilir.
- ASC tarafındaki mevcut gönderim durumu (Mayıs'taki "Rejected" gönderim iptal mi edildi?) doğrulanmadı.

## Kabul ölçütü eşlemesi
- Adım 3a → purpose string ölçütü
- Adım 3b → 2.4.5(i) ölçütü
- Adım 2 → inceleme notu tutarlılık ölçütü
- Adım 3c + 4 → IAP ölçütü
- Adım 1 + 5 → commit/build ölçütü
- Adım 6 → ASC yanıtı ve yeniden gönderim ölçütü
