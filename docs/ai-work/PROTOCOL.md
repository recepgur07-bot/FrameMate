# Çoklu Ajan İş Akışı Protokolü

## Dil ilkesi

- Kullanıcıya görünen tüm sohbet mesajları, seçenekler, durum bildirimleri ve sonuç özetleri Türkçedir; açık ve ekran okuyucuya uygun yazılır.
- Araçlar arası talimatlar ile plan, inceleme ve teknik çalışma dosyaları varsayılan olarak İngilizce yazılabilir.
- Kullanıcının özgün Türkçe isteği; uygulama/VoiceOver metinleri; hata metinleri; dosya yolları; kod sembolleri ve API adları aynen korunur. Gerektiğinde İngilizce çalışma metninde özgün ifade alıntılanır.
- Koordinatör çalışma dosyaları hangi dilde olursa olsun sonucu kullanıcıya Türkçe sunar. Hedef araç dosyaya yazdıktan sonra sohbette yalnız kısa Türkçe tamamlanma bildirimi verir.

## Tek kaynak ve aşamalar

Kanonik dosyalar `docs/ai-work/` altındadır. `TASKS.md` tüm görevlerin portföyüdür; `STATUS.md` aktif görevin kısa durumudur. Aşamalar:

`brief → plan → review → synthesis → user approval → handoff → implementation → verification → done`

`STATUS.md` her aşamada aktif görev, sorumlular ve tek sonraki adımı taşır.

Her görevde ayrıca `decisions.md` bulunur. Kullanıcının onayı, kapsam seçimi, istisna kabulü ve incelemeler arasındaki kararlar burada tarih/rol/gerekçeyle eklenir; eski karar satırı değiştirilmez.

## Başlangıç ve varsayılan roller

- Protokol yoksa, isteği alan araç başlatıcıyı çalıştırır; var olan `docs/ai-work/` dosyalarını ezmez.
- Kullanıcı rol atamadıysa isteği alan araç koordinatördür: planlayıcı ve sentezleyici odur; diğer iki araç bağımsız inceleyendir.
- Uygulayıcı kullanıcı onayı olmadan atanmış sayılmaz. Doğrulayıcı, uygulayıcıdan farklı bir araçtır.
- Roller görev bazlıdır; bir sonraki görevde aynı araç farklı rol alabilir.

## Dosya sahipliği

- Planlayıcı yalnız `plan.md`yi yazar.
- İnceleyen yalnız `reviews/NN-arac-rN.md`yi yazar. Var olan incelemeyi değiştirmez.
- Sentezleyici yalnız `synthesis.md`yi yazar; ham görüşleri değiştirmez.
- Uygulayıcı yalnız kullanıcı onaylı `handoff.md` kapsamını uygular.
- Doğrulayıcı yalnız `verification.md`ye kanıt yazar.
- Koordinatör `TASKS.md` ve `STATUS.md`nin güncelliğinden sorumludur. Bir aşama sahibi işini bitirdiğinde, kendi hedef dosyasına sonucu yazar ve koordinatör sonraki aşamayı bu iki dosyada ilan eder.
- Ortak kontrol dosyaları (`TASKS.md`, `STATUS.md`, `decisions.md`) yalnız koordinatör tarafından güncellenir. Aynı dosyayı iki araca eşzamanlı yazma görevi verilmez.

## Zorunlu inceleme formatı

İnceleyen, aşağıdaki numarasız üst seviye başlıkları **tam bu sırayla** ve her birinin altında boş olmayan içerikle kullanır. Başlıkları numaralandırmaz, yeniden adlandırmaz, önek veya sonek eklemez.

## Sonuç

Onay / Koşullu onay / Revizyon gerekli.

## Kritik bulgular

Öncelik, gerekçe ve öneri.

## Onaylanan kararlar

## Riskli varsayımlar

## Doğrulama listesi

## Önerilen plan düzeltmeleri

## Zorunlu inceleme kapsamı ve kanıtı

- İnceleyen, planı tek başına değerlendirmez. Görevin etkilediği mevcut ekranların, akışların ve davranışların ilgili kaynak kodunu; bunların ayar, binding, model ve servis bağlantılarını salt-okunur olarak inceler.
- Çalışan uygulama, simülatör veya uygun bir arayüz doğrulama aracı erişilebilirse; inceleyen ilgili ekran akışını, görünen öğeleri ve görevle ilgili erişilebilirlik davranışını da inceler. İnceleme sırasında kod, plan, ortak durum dosyası veya başka bir inceleme dosyası değiştirilmez.
- Kaynak ya da çalışır arayüz erişimi yoksa inceleyen bunu kendi görüşünde açıkça **doğrulanamadı** olarak yazar; planla mevcut uygulamanın uyumunu var saymaz.
- Görüş, incelenen kaynak/ekran kanıtını ve planla bulunan farkları belirtir. İnceleyen başka ham görüşleri okumaz; bağımsızlığını yalnız kendi atanan inceleme dosyasını yazarak korur.

## Geçiş kuralları

- Review için kanonik `plan.md` gerekir.
- Synthesis için istenen görüşler tamamlanmış olmalıdır.
- Handoff için kullanıcı açıkça onay vermelidir.
- Done için doğrulama kanıtı gerekir. Gerçek cihaz veya dış erişim yoksa durum `doğrulanamadı` yazılır.
- Koordinatör bir aşamayı kapatmadan önce `workflow_guard.py validate` ile gereken dosya/başlıkların dolu olduğunu kontrol eder; sentezden önce `--require-review` kullanır. Kontrol geçmezse aşama ilerlemez.
- Bir görev terminal aşamaya ("Uygulandı", "Doğrulandı") kapatılmadan önce koordinatör `workflow_guard.py validate --require-clean-tree` çalıştırır — çalışma ağacında commit edilmemiş değişiklik varsa kontrol başarısız olur ve aşama kapanmaz. Kullanıcı onayıyla tamamlanmış bir görev, git'e düşürülmeden "bitti" sayılamaz (bkz. tesbihim projesi 2026-07-19: birden fazla onaylı görev günlerce commitsiz birikmiş, başka bir aracın izole daldaki bekleme kapısını gereksiz uzatmıştı).

## Görüş çelişkisi ve karar kuralı

Sentezleyici her kritik bulguyu `synthesis.md` ve `decisions.md` içinde şu sonuçlardan biriyle kapatır: `kabul`, `ret`, `plan revizyonu`, `doğrulama gerekli`, `kullanıcı kararı gerekli`.

- Erişilebilirlik, güvenlik, veri kaybı, gizlilik veya App Store riski taşıyan çelişkide temkinli sonuç seçilir: plan revize edilir ya da kullanıcıya açıkça sunulur; çoğunluk oylaması yapılmaz.
- Ürün tercihi veya eşdeğer teknik seçeneklerde sentezleyici gerekçeli öneri sunar; kullanıcı kararı yoksa kapsam ilerlemez.
- İddia yalnız kanıt/gerçek cihaz deneyiyle çözülebiliyorsa durum `doğrulama gerekli` olur; varsayım karar yerine yazılmaz.

## Tur, revizyon ve yeni görev ayrımı

- Aynı kapsam ve aynı `plan.md` için ek veya yeniden yapılmış inceleme, yeni `reviews/NN-arac-r2.md` gibi yeni bir turdur; önceki görüş asla değiştirilmez.
- Plan, sentez bulguları nedeniyle değişirse, etkilenmiş inceleyenlerden yeni tur istenir. Kapsam değişmiyorsa yeni görev açılmaz.
- Amaç, kullanıcı değeri veya kabul ölçütleri bağımsızlaşacak kadar değişirse yeni `tasks/<konu>/` görevi açılır ve `TASKS.md`ye eklenir.

## Doğrulayıcı bağımsızlığı

Doğrulayıcı uygulayıcı olamaz. Aynı görevde planlayıcı veya inceleyen olmuş olabilir; ancak mümkünse uygulama kararlarını savunmakla doğrudan sorumlu olmayan bir araç seçilir. Gerçek bağımsızlık gerekiyorsa kullanıcı bunu açıkça ister ve daha önce uygulamaya katkı vermemiş araç atanır.

## Başarısız doğrulama dönüşü

- Kod veya kabul ölçütü uygulaması yanlışsa: `verification → implementation`.
- Planın kabul ölçütü eksik/yanlışsa: `verification → synthesis → plan → etkilenmiş inceleme turu`.
- Kullanıcı hedefi ya da kapsam değiştiyse: `brief` güncellenir; bağımsız hedefse yeni görev açılır.
- Test ortamı, cihaz veya erişim eksikse: geri dönüş yapılmaz; `doğrulanamadı` ve engel/sonraki sahip `verification.md`ye yazılır.

Koordinatör dönüş nedenini `decisions.md`ye, yeni aşamayı `TASKS.md` ve `STATUS.md`ye yazar.

## Kilit, arşiv ve geçmiş

- Plan, sentez veya ortak kontrol dosyası değişmeden önce koordinatör `workflow_guard.py lock acquire` ile görev kilidini alır; iş bittiğinde `release` eder. Kilit başka sahipse yazma yapılmaz; sahip ve zaman kullanıcıya bildirilir.
- `done` olmuş görev, kısa sonuç/karar/doğrulama özeti korunarak `archive/<görev>/` altına taşınır ve `TASKS.md`de `Arşivlendi` olur. Aktif `tasks/` dizininde yalnız açık işler kalır.
- Arşivlenen dosyalar salt okunur tarihçedir; yeniden çalışma yeni görev veya yeni inceleme turu olarak açılır.

## Araç erişimi

Varsayılan çalışma biçimi aynı yerel proje klasörüdür. GitHub/Drive aynası ancak kullanıcı kurmuş veya açıkça istemişse kullanılır; bu proje için kendiliğinden var kabul edilmez. Araç yerel dosyaları okuyamıyorsa ve erişilebilir bir ayna yoksa kullanıcı yalnız gereken girdi dosyasını paylaşır; ajan çıktısını yine belirtilen hedef dosya biçiminde döndürür.

## Genel görüşmeler

- Önce isteği sınıflandır: kod, plan, repo, uygulama, proje hedefi, önceki proje kararı veya proje verisi taşıyorsa proje görevidir ve bu protokol uygulanır; aksi halde genel görüşmedir. Belirsizlikte kullanıcıdan kısa teyit alınır. Dosya oluşturmadan, görüş yazmadan veya sentez yapmadan önce hedef araçlar, istenen rol/görüş sayısı ve kayıt isteği yeterince açık mı denetlenir; biri eksikse yalnız tek kısa netleştirme sorusu sorulur ve işlem yapılmaz.
- Genel görüş proje `docs/ai-work/` alanını değiştirmez. Koordinatör, `/Users/recepgur/ai-workflows/genel-gorusler/aktif/` altında oturumu oluşturmak için `init_general_opinions.py`yi çalıştırır. Başlatıcı `soru.md`, her hedef için `NN-arac.md`, `sentez.md` ve `talimatlar/NN-arac.md` altında hazır kopyalanabilir talimatları oluşturur. Koordinatör klasör oluşturduktan sonra bu talimatları aynı yanıtta zorunlu olarak sunar.
- Hedef araç yalnız kendine atanmış numaralı görüş dosyasını yazar; ikinci tur `NN-arac-r2.md` gibi yeni dosyadır. Koordinatör yalnız `sentez.md`yi yazar. Sentezde girdiler/tur, uzlaşma, ayrışma, karar, açık risk ve sonraki adım bulunur; eksik veya geçersiz görüş varsa durum `eksik görüşle sentez` diye açıkça yazılır.
- Hassas kişisel veri, kimlik bilgisi veya sağlık/hukuk/finans ayrıntısı varsa koordinatör, hedefleri ve aktarılacak veri-minimize özeti açıklamadan ve kullanıcı açıkça onay vermeden diske yazmaz veya hedef araca aktarmaz.
- Otomatik uygulamalar arası mesaj, kuyruk, arka plan izleme, UI denetimi ve UUID iş akışı yoktur. Genel görüş içeriği HAFIZA'ya yazılmaz.
- Yalnız kullanıcı açıkça `genel görüş arşiv bakımı yap` dediğinde tamamlanmış oturumlar `arsiv/YYYY-MM/` altına taşınır; silme yapılmaz.

## Görüş alma

- Koordinatör, görüş istenen her araç için kısa bir talimat üretir ve bu talimatı **aynı sohbet yanıtında ayrı kod bloğu olarak zorunlu sunar**; böylece kullanıcı arayüzün kopyalama düğmesini kullanabilir. Yalnız `prompts/` klasörünü işaret etmek, dosya yolunu vermek veya talimatı sonraki yanıta bırakmak yeterli değildir. Sohbette verilen metin ilgili `prompts/` dosyasının güncel içeriğiyle aynı olmalıdır. Talimat hangi dosyaların okunacağını, rolü, hedef `reviews/NN-arac-rN.md` dosyasını ve zorunlu inceleme başlıklarını belirtir.
- Kullanıcı bu talimatı hedef araca gönderir. Hedef araç yalnız kendi atanmış inceleme dosyasına yazar; başka aracın çıktısını veya ortak kontrol dosyalarını değiştirmez.
- Hedef araç dosya yazma yetkisine sahip değilse görüş tamamlanmış sayılmaz. Uygulamalar arası otomatik mesaj gönderimi, kuyruk ve arka plan izleme bu protokolün kapsamı dışındadır.

## HAFIZA sınırı

HAFIZA yalnız kalıcı kullanıcı tercihlerini, tekrar kullanılabilir iş akışını ve bu protokolün kullanıldığını hatırlar. Plan, görüş, görev durumu ve uygulama kanıtı yalnız proje içindeki bu dosyalarda tutulur; HAFIZA bunların ikinci kopyası değildir.

## Ortak öğrenme ve seyir defteri

- Ortak kök eksikse güvenli başlatıcıyla oluşturur; ortak kök: `/Users/recepgur/ai-workflows/ortak-ogrenme/`. Proje varsa yalnız eksik olan en küçük dosya kümesini ekler ve mevcut dosyayı ezmez. Açılış sırası: ortak kök; sonra `PROTOCOL.md, TASKS.md, STATUS.md, project-decisions.md ve ilgili seyir-defteri.md` son kayıtlarıdır.
- Öncelik: açık kullanıcı talimatı → proje kararı → ortak kayıt → protokol varsayılanı. Planlayıcı ve inceleyen öneriden önce `INDEX.md ve DERSLER.md` içinde ilgili kayıtları arar.
- Başarısız bir yöntemi yalnız koşullar değiştiğini ve önceki kanıtı yazıp yeniden dene; değişen koşulu, kanıtı ve gerekçeyi plan ile seyir defterine ekle. Ortak ya da proje dosyasına erişemiyorsa açıkça bildirir; okunmuş veya uygulanmış gibi davranmaz.
- Düşük etkili, açık kullanıcı tercihi doğrudan doğrulayabilir. Yüksek etkili aday (erişilebilirlik, veri kaybı, gizlilik, güvenlik veya tüm projeleri etkileyen tercih) ikinci araç incelemesi olmadan doğrulanmaz.
- Ortak dosyaları yalnız koordinatör ortak kilidi alarak günceller; aday önce `INCELEME.md`ye kaydedilir. Yalnız açık arşiv bakımı isteğinde veya çelişki saptandığında geçersiz veya yerine geçen kayıt için `archive` komutunu ortak kilidiyle çalıştırır ve `INDEX.md`yi yeniler.
- Manuel talimat kopyalama korunur. Otomatik dispatch, API teslimi, daemon, outbox veya arka plan tetikleme yoktur.

<!-- WORKFLOW_MAINTENANCE_CONTRACT:START -->
## Sonuç
## Kritik bulgular
## Onaylanan kararlar
## Riskli varsayımlar
## Doğrulama listesi
## Önerilen plan düzeltmeleri
Hızlı Özet: en fazla üç madde.
HAFIZA yalnız kalıcı tercih bağlamıdır; proje artefaktı değildir.
Kilit geri alma: terminal için --confirm-terminal, aktif/bilinmeyen için --override-active.
<!-- WORKFLOW_MAINTENANCE_CONTRACT:END -->
