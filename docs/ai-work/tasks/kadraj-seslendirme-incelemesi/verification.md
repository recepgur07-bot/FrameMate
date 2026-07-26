# Doğrulama Kaydı

| Kabul ölçütü | Test yöntemi | Kanıt | Durum |
| --- | --- | --- | --- |
| Tüm mevcut + yeni Swift birim testleri geçer | `xcodebuild test-without-building -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'` | 355 test, 0 hata (2 skip, ilgisiz); ayrıca `FrameMateProjectTests` 22/22 | geçti |
| Frame Coach lokalizasyon kataloğu tutarlı | `ruby -E UTF-8 Tests/FrameCoachLocalizationCatalogTests.rb` | Frame Coach'a özgü testler geçti; kalan tek hata (`Mikrofon kanalı`) bu göreve ait değil | geçti (kapsam dışı 1 ilgisiz hata var) |
| 3 kişilik overlap/scale-imbalance artık çalışıyor | Yeni testler: `testThreePeopleWhenTwoAreOverlappingNamesTheHiddenPerson`, `testThreePeopleWithScaleImbalanceAskCloserPersonToMoveBack` | `Tests/VideoRecorderAppTests/FrameCoachingEngineTests.swift` | geçti |
| 4+ kişi artık "üç kişi" olarak yanlış raporlanmıyor | Yeni test: `testSubjectCountAnnouncementReportsOverflowInsteadOfClaimingExactlyThree` | aynı dosya | geçti |
| Düşük Vision güveni artık "yüz yok" a düşüyor (ölü kod canlandı) | Yeni test: `testLowConfidenceDetectionIsTreatedAsNoFace` | aynı dosya | geçti |
| Kişi-sayısı anonsunda hysteresis (çırpınma önleme) | Yeni test: `testFrameCoachRequiresTwoConsecutiveAnalysesBeforeAnnouncingSubjectCountChange`; güncellenen `testFrameCoachAnnouncesSubjectCountOnlyWhenItChanges` | `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift` | geçti |
| Yön sesi UI açıklaması artık gerçek davranışla eşleşiyor | Kod incelemesi: `ContentView.swift`teki yeni metin + `FrameCoachSpatialCueResolver.swift`teki yön hesaplaması karşılaştırıldı | manuel statik doğrulama (bu PR'de) | geçti (statik); gerçek VoiceOver oturumunda kullanıcı algısı doğrulanamadı |
| VoiceOver anons önceliği artık `.medium` | Kod incelemesi: `SpeechCuePlayer.swift` `SystemAccessibilityAnnouncer.announce` | manuel statik doğrulama | geçti (statik); gerçek kesinti/kuyruk davranışı doğrulanamadı |

## Açık riskler ve takip işleri

- **Gerçek cihaz/VoiceOver oturumu yok**: anons kesintisi/kuyruklama, stereo yön algısının gerçek kulaklıkta nasıl hissedildiği, ve 4+ kişiyle gerçek Vision tespiti bu oturumda **doğrulanamadı**. Kod düzeyinde doğru olduğu gösterildi (testlerle ve statik incelemeyle), ama gerçek deneyim ayrı bir doğrulama gerektirir.
- Apple'ın yeni erişilebilirlik API'lerinin eklenmesi (Personal Voice, Sound Recognition, vücut pozu tespiti, Haptics) kapsam dışı bırakıldı — ayrı bir keşif görevi olarak ele alınabilir.
- Bu görev kapsamında rastlanan ama görevle ilgisiz bir bulgu: `Localizable.xcstrings`teki bazı anahtarların "tr" çevirisi kaynak metinle sync değilmiş (örn. düzelttiğim "Yüz algılanamıyor, kameraya bak" anahtarı) — bu türden başka sync-dışı kayıt olup olmadığı bu görevde taranmadı, ayrı bir bakım görevi olabilir.
