# Aktif İş Durumu

Görev: `tasks/kayit-zamanlama-duzeltmesi` — aşama: 2026-07-27'de sıfırdan yeniden
ele alındı (önceki seyir-defteri girdileri diskte karşılığı olmayan uydurma
kayıtlardı — dosyanın başındaki UYARI'ya bakınız). Bu oturumda handoff.md'nin
altı fazı da gerçekten uygulandı, her faz kendi commit'inde, her commit öncesi
build + `xcodebuild ... test-without-building -only-testing:FrameMateTests`
yeşil doğrulandı:
- `29d7cb6` Faz 1 (yaşam döngüsü hiç takılı kalmıyor: stop watchdog, isStopping
  latch düzeltmesi, .preparing'den durdurma)
- `879a79a` Faz 2 (RecordingSessionClock, duraklama artık ilk örneğe göre)
- `6f30aee` Faz 3 (üç modda da ikincil track offset hizalaması — handoff'un
  "zaten var" dediği mekanizma hiçbir modda yoktu, sıfırdan yazıldı)
- Faz 4 ayrı commit gerektirmedi, Faz 2 commit'inde geldi (frame status filtresi
  + gerçek ilk kare PTS farkının loglanması)
- `0de5661` Faz 5 + Faz 6 (recordingGeneration koruması, tam enstrümantasyon)

Son durum: canonical `xcodebuild test` yeşil — `FrameMateTests` 379 test / 2
skip / 0 hata ve `FrameMateProjectTests` 23 test / 0 hata;
`tools/mobile-quality-gate.sh` de yeşil. **Gerçek cihazda doğrulanmadı**: Faz
2/3/4'ün zamanlama matematiği (özellikle ekran+kamera overlay ve kamera+sistem
sesi modlarındaki A/V senkronu) ve Faz 4'ün macOS 15+ gözlem stream'i gerçek
kayıtla ayrıca doğrulanmalı. Kamera overlay görüntüsünün önceki Build 1.0
(202608031748) üzerinde göründüğü kullanıcı tarafından doğrulandı. Ayrıntı ve
kanıt: `tasks/kayit-zamanlama-duzeltmesi/seyir-defteri.md`,
`../app-store/device-validation.md`. Sonraki adım: kullanıcı aday build'de
screen/camera/audio-only kayıt + duraklama + satın alma/restore +
`runtimeDebugLog` çıktısını doğrulamalı.

Görev: `tasks/kadraj-seslendirme-incelemesi` — aşama: implementation tamamlandı,
commit edildi, gerçek cihaz doğrulaması açık. Koordinatör/uygulayıcı: claude.
Kullanıcı onayı ("hepsini hallet") ile synthesis.md'nin 8 kabul edilen bulgusu
uygulandı; güncel canonical kapıda 379 Swift testi + 23 proje testi + Ruby
kontrolleri geçiyor. Değişiklikler 660eaf3 commit'ine dahil. Sonraki adım:
aday build'de gerçek cihaz/VoiceOver doğrulaması.
