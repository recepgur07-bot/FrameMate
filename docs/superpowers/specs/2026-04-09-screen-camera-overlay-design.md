# Screen Camera Overlay Design

## Goal

Ekran kaydı modlarında kullanicinin kamera goruntusunu kucuk bir kutu olarak videoya eklemek. Ilk surumde kutu konumu 9 noktadan secilebilir olacak ve kayit bittikten sonra MP4 export asamasinda ekrana birlestirilecek.

## User Experience

- Ozellik sadece ekran modlarinda gorunur.
- Kullanici `Kamera kutusunu goster` secenegini acar.
- Acinca sunlar gorunur:
  - Kamera secimi
  - Kutu konumu secimi
- Kayit sirasinda ekran kaydi normal akar.
- Kayit tamamlandiginda olusan MP4 dosyasinda ekran ustunde kamera kutusu gorunur.

## Scope

Bu turda:

- Tam ekran ve pencere kaydinda kamera kutusu desteklenecek
- 9 konum desteklenecek
- Sabit tek boyut kullanilacak
- MP4 export asamasinda birlestirme yapilacak
- Ekran modlarinda kucuk bir kamera onizlemesi gosterilecek

Bu turda yapilmayanlar:

- Canli ekran onizlemesi ustunde gercek zamanli picture-in-picture
- Yuvarlak koseler, cerceve, golge
- Ayrik boyut secimi
- Akilli dikey layout
- Sistem sesiyle ilgili ek degisiklikler

## Design

### 1. Overlay Settings

Yeni bir `ScreenCameraOverlayPosition` modeli eklenecek. Ust-sol, ust-orta, ust-sag, orta-sol, merkez, orta-sag, alt-sol, alt-orta, alt-sag konumlarini tutacak.

View model ekran modlari icin su ayarlari yonetecek:

- `isScreenCameraOverlayEnabled`
- `selectedScreenCameraOverlayPosition`

### 2. Camera Overlay Capture

Ekran kaydi baslarken kamera kutusu aciksa ikinci bir kamera oturumu baslatilacak. Bu oturum yalnizca goruntu kaydedecek ve gecici bir `.mov` dosyasina yazacak.

Bu capture hattinin sorumlulugu:

- Kamera secimini kullanmak
- Ekran modunun yatay/dikey yonune gore video rotasyonunu uygulamak
- UI icin bir preview session saglamak
- Stop sonrasinda dosyayi temizce tamamlamak

### 3. Export Composition

Ekran kaydi bittiginde:

- ana ekran videosu asset olarak okunacak
- kamera overlay videosu asset olarak okunacak
- ikisi tek composition icinde birlestirilecek
- overlay track sabit boyutta scale edilip secilen konuma tasinacak
- ana ekran videosunun sesi korunacak

Bu is icin ayri bir composition builder eklenecek.

### 4. Failure Handling

- Kamera kutusu acik ama kamera secili degilse ekran kaydi normal devam etmeyecek; durum metni bunu net soyleyecek
- Overlay capture baslatilamazsa kullaniciya hata verilecek ve ekran kaydi da baslamayacak
- Overlay export basarisiz olursa hata gosterilecek; yarim bozuk MP4 uretilecek gibi davranilmayacak

## Testing

- Overlay position rect hesaplari
- Overlay acikken ekran kaydinin kamera overlay recorder baslatmasi
- Overlay kapaliyken bu recorder'in devreye girmemesi
- Screen export'ta overlay composition secilmesi
- Ekran modlarinda ilgili UI kontrollerinin gorunmesi
