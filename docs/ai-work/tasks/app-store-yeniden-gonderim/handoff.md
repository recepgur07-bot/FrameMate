# Uygulama Devri

## Kullanıcı onayı
- Tarih: 2026-07-20
- Onaylanan kapsam: Kullanıcı sohbette "o zaman her şeyi planla ve uygula" diyerek plan.md'deki tüm adımların uygulanmasını onayladı. Uygulayıcı: claude.

## Yapılacaklar
1. Test paketini çalıştır; geçtiğini kanıtla.
2. 2026-05-13'ten beri bekleyen değişiklikleri gözden geçirip anlamlı commit'lere böl ve commit et.
3. docs/app-review-notes.md'den bayat Accessibility izin maddesini kaldır; kayıt klasörü adı açıklaması ekle.
4. Release derleme yap; derlenmiş pakette purpose string'leri, IAP bayrağını (false) ve entitlements'ı doğrula.
5. CFBundleVersion'ı yükselt; fastlane beta ile App Store Connect'e yükle.
6. App Review yanıt taslağını ve güncel Review Notes metnini hazırla.

## Yapılmayacaklar
- App Store Connect'te "Submit for Review" tıklaması ve Apple'a mesaj gönderimi: yalnız kullanıcının ayrı, açık onayıyla.
- Yeni özellik geliştirme; iOS çalışması.
- Push (git push) kullanıcı onayı olmadan yapılmaz.

## Kabul ölçütleri
- brief.md'deki kabul ölçütleri geçerli; ek olarak testler yeşil olmadan commit yapılmaz.

## Uygulama kaydı
- Değişen dosyalar: (uygulama sırasında doldurulacak)
- Testler: (uygulama sırasında doldurulacak)
- Bilinen sınırlamalar: İzin diyaloglarının gerçek ekranda doğrulanması ve VoiceOver akışı kullanıcı ile birlikte test edilecek.
