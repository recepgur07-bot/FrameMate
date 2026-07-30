# Seyir Defteri

Format: `TARIH SAAT — ARAÇ — ne yapıldı/denendi (tek satır) — [varsa link/dosya yolu]`

Bu dosya append-only'dir; var olan satır silinmez veya değiştirilmez.

2026-07-30 12:10 — Claude — Kayıt başladığında ekranı sadeleştirdi: mod seçici/önizleme/kurulum kartları kaldırıldı, yalnız süre + duraklat/durdur kalan sade bir "aktif kayıt" ekranı eklendi — Sources/VideoRecorderApp/ContentView.swift
2026-07-30 12:24 — Claude — Kayıt sırasında seçili mikrofon (örn. kulaklık) koptuğunda kaydı tamamen durdurmak yerine mevcut duraklat/kes mekanizmasıyla otomatik duraklatıp kullanıcıya "mikrofonu yeniden tak, Devam Et'e bas" istemi gösterecek şekilde değiştirdi; kamera kopmasında sert-durdurma davranışı korundu (video kaynağı kaybolduğu için kurtarılamaz) — Sources/VideoRecorderApp/RecorderViewModel.swift (handleCaptureDeviceDisconnect, pauseRecordingForMicrophoneReconnect), Sources/VideoRecorderApp/ContentView.swift (recordingActiveZone uyarı bandı)
