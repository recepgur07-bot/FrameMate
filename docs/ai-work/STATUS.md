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

Son durum: build yeşil, `-only-testing:FrameMateTests` 368 test/0 hata (bu
ortamda gerçek cihaz izinleri olmadığı için tam `test` hedefi —
`FrameMateProjectTests` dahil — bir kez daha ayrıca doğrulanmaya çalışıldı;
sonucu bu dosyanın en altına eklenecek). **Gerçek cihazda doğrulanmadı**: Faz
2/3/4'ün zamanlama matematiği (özellikle ekran+kamera overlay ve kamera+sistem
sesi modlarındaki A/V senkronu) ve Faz 4'ün macOS 15+ gözlem stream'i yalnız
birim testleriyle (sentetik zaman çizelgeleri) doğrulandı, gerçek bir kayıtla
değil. Ayrıntı ve kanıt: `tasks/kayit-zamanlama-duzeltmesi/seyir-defteri.md`.
Sonraki adım: kullanıcı gerçek cihazda screen/camera/audio-only kayıt + duraklama
+ `runtimeDebugLog` çıktısını doğrulamalı (bkz. görev dosyasındaki final rapor).

Görev: `tasks/kadraj-seslendirme-incelemesi` — aşama: implementation tamamlandı,
gerçek cihaz doğrulaması açık. Koordinatör/uygulayıcı: claude. Kullanıcı onayı
("hepsini hallet") ile synthesis.md'nin 8 kabul edilen bulgusu uygulandı;
355 Swift testi + 22 proje testi + Ruby lokalizasyon testleri geçiyor. Kod
değişikliği commit edilmedi (kullanıcı henüz commit istemedi). Sonraki adım:
kullanıcı isterse commit/gerçek cihaz doğrulaması; aksi halde açık iş yok.
