# Hızlı Kullanım

1. `brief.md`yi kullanıcı isteğiyle doldur.
2. Koordinatör, ortak durum dosyalarını güncellemeden önce kilit alır: `python3 /Users/recepgur/.codex/skills/multi-agent-workflow/scripts/workflow_guard.py --project . --task <görev> lock acquire --owner <araç>`.
3. Planlayıcıya `prompts/planner-talimat.md` dosyasının tam içeriğini aynı sohbet yanıtında ayrı bir kod bloğu olarak ver.
4. Her inceleyen için kendi araç adlı `prompts/NN-...-inceleme-talimat.md` dosyasının tam ve güncel içeriğini aynı sohbet yanıtında ayrı bir kod bloğu olarak ver; yalnız klasöre veya dosya yoluna yönlendirme yapma.
5. Sentezleyiciye `prompts/synthesizer-talimat.md` dosyasının tam içeriğini aynı sohbet yanıtında ayrı kod bloğu olarak ver; kullanıcı kararlarını `decisions.md`ye kaydet.
6. Kullanıcı onayından sonra handoff'u tamamla ve uygulayıcıya `prompts/implementer-talimat.md` dosyasının tam içeriğini aynı sohbet yanıtında ayrı kod bloğu olarak ver.
7. Doğrulayıcıya `prompts/verifier-talimat.md` dosyasının tam içeriğini aynı sohbet yanıtında ayrı kod bloğu olarak ver.
8. Aşama kapatmadan önce `workflow_guard.py --project . --task <görev> validate` çalıştır; terminal aşamaya ("Uygulandı"/"Doğrulandı") kapatırken `--require-clean-tree` ekle (çalışma ağacı commit edilmemişse kontrol başarısız olur). Sonra kilidi bırak.

Bir inceleme tekrarlanırsa yeni `reviews/NN-arac-r2.md` ve buna karşılık yeni talimat dosyası oluştur; eski dosyayı değiştirme.
