# Karar Kaydı

| Tarih | Sahip | Karar | Gerekçe | Durum |
| --- | --- | --- | --- | --- |
| 2026-07-27 | claude (kullanıcı onayıyla) | `docs/app-review-notes.md` tek kanonik review-notes dosyası; `docs/app-store/app-review-notes.md` ona yönlendiren bir nota indirgendi | İki dosya farklı içerik taşıyordu, hiçbiri fastlane/ASC'ye otomatik bağlı değildi; bu, 2026-05-08 mikrofon purpose string reddiyle aynı risk sınıfında bir "izin metni gerçek davranışla uyuşmuyor" riski yaratıyordu | Uygulandı |
| 2026-07-27 | claude (kullanıcı onayıyla) | Accessibility (AX) izninin yalnızca isteğe bağlı "Klavye Kısayolları" özelliği açıldığında istendiği review notes'a açıkça yazıldı (önceden "hiç istenmiyor" deniyordu) | 2026-07-20 planındaki "AXIsProcessTrusted çağrısı yok" varsayımı yanlıştı; kod gerçekten çağırıyor (`RecorderViewModel.swift:1110-1113`) | Uygulandı |
