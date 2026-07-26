# Uygulama Devri

## Kullanıcı onayı
- Tarih: 2026-07-26
- Onaylanan kapsam: Kullanıcı "şimdi bu karar verilen tüm önerilerin eksikliklerin giderilmesi lazım hepsini hallet" dedi — `synthesis.md`deki "Kabul edilenler" (8 madde) ve "Kullanıcı kararı gerekenler" bölümündeki tüm önerilen düzeltmelerin uygulanması olarak yorumlandı ve uygulandı.

## Yapılacaklar (synthesis.md "Kabul edilenler" ile eşleşir)
1. Üç ayrı "yüz algılanamıyor" metnini tek kaynağa (`FrameCoachingEngine.noFaceInstruction`) indir.
2. String-eşitliğine dayalı "kadraj uygun/dengeli" ve "sert talimat" tespitini tipli `FrameCoachInstructionKind`/`FrameCoachGuidance` ile değiştir.
3. `FrameAnalysisService`de sabit `confidence: 0.9`i gerçek Vision güvenine bağla; artık ölü kod olan `.advisory` mesafe dalını kaldır.
4. 4+ kişi sahnesinde sessizce "Üç kişi görünüyor" denmesini düzelt: `FrameAnalysis.isOverflowing` + dürüst "üçten fazla kişi" anonsu.
5. Kişi-sayısı anonsuna hysteresis ekle (2 ardışık analiz onayı, ilk anons hariç).
6. `overlapInstruction`/`scaleImbalanceInstruction`ı 3 kişilik sahnelere genişlet.
7. VoiceOver anons önceliğini `.high`den `.medium`e indir (rutin yönlendirme her şeyi kesmesin).
8. "Yön sesi" ayarının erişilebilirlik açıklamasını gerçek davranışla eşleştir (sesin yüzün değil, hareket yönünün kulağından geldiğini söyle); `Localizable.xcstrings`teki ilgili kayıtları düzelt (ayrıca eski "Yüz algılanamıyor, kameraya bak" anahtarının `tr` çevirisinin gerçekte kısaltılmış olduğunu tespit edip düzelttim — kök neden buydu).

## Yapılmayacaklar
- Apple'ın yeni erişilebilirlik API'lerinin (Personal Voice, Sound Recognition, `VNDetectHumanBodyPoseRequest`, Haptics) eklenmesi — synthesis.md'de ayrı bir keşif/ürün kararı olarak bırakıldı, bu turda kapsam dışı.
- VoiceOver anons önceliği/kesinti davranışının gerçek cihazda doğrulanması — kod tarafı düzeltildi (`.medium`), gerçek cihaz doğrulaması ayrı `verification.md` maddesi.

## Kabul ölçütleri
- [x] Tüm mevcut Swift birim testleri (355 test, FrameMateTests + 22 FrameMateProjectTests) geçiyor.
- [x] Yeni testler eklendi: 3 kişilik overlap/scale-imbalance, overflow anonsu, düşük güven → "yüz yok" davranışı, hysteresis.
- [x] Ruby lokalizasyon katalog testleri (`Tests/FrameCoachLocalizationCatalogTests.rb`) Frame Coach'a özgü tüm testler geçiyor.
- [ ] Gerçek cihaz/VoiceOver oturumunda doğrulama — bkz. `verification.md` (doğrulanamadı, bu oturumda cihaz erişimi yok).

## Uygulama kaydı
- Değişen dosyalar: `Sources/VideoRecorderApp/FrameCoach/{CaptureCoachingEngine,FrameCoachingEngine,FrameAnalysis,FrameAnalysisService,FrameCoachSpatialCueResolver,SpeechCuePlayer}.swift`, `Sources/VideoRecorderApp/RecorderViewModel.swift`, `Sources/VideoRecorderApp/ContentView.swift`, `Sources/VideoRecorderApp/Localizable.xcstrings`, `Tests/VideoRecorderAppTests/{FrameCoachingEngineTests,RecorderViewModelFrameCoachTests}.swift`.
- Testler: `xcodebuild test-without-building -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'` → 355 test, 0 hata (2 skip, ilgisiz). `ruby -E UTF-8 Tests/FrameCoachLocalizationCatalogTests.rb` → Frame Coach ile ilgili tüm testler geçti; kalan 1 hata (`Mikrofon kanalı`) bu oturumdan önceki, ilgisiz bir commit-edilmemiş değişiklikten kaynaklanıyor, dokunulmadı.
- Bilinen sınırlamalar: Gerçek VoiceOver/cihaz davranışı (anons kesintisi, stereo yön algısı, 4+ kişi ile gerçek Vision tespiti) bu oturumda doğrulanamadı — kod düzeyinde doğru olduğu statik olarak ve testle gösterildi, ancak `verification.md`de "doğrulanamadı" olarak işaretli kalıyor.
