# Brief: buat ulang landing page di `iot.pen`

Untuk sesi Claude Code **lokal** dengan MCP Pencil aktif dan `iot.pen` terbuka di Pencil.
Sumber kebenaran: [`landing/page.html`](../landing/page.html) (live di https://autonomous-pond-system.web.app).

## Aturan

- Hanya **tambah** frame baru. Jangan ubah frame v1–v4 / HW yang sudah ada.
- Pakai variabel yang sudah ada: `$p-bg`, `$p-ink`, `$p-ink-2`, `$p-blue`, `$p-blue-2`, `$p-tint`,
  `$g-teal`, `$g-amber`, `$g-violet`, `$g-line`, font `$p-font` (Outfit). Jangan bikin warna literal baru
  kecuali gradien v4 (oranye `#FFB547→#FF7A45`, violet `#2F6BFF→#7B5CFF`).
- Gambar: pakai file di `landing/img/` (screenshot v3/v4 dan foto hub).
- Taruh frame di kanan semua frame yang ada (x > frame terakhir + 200), y = 0.

## Frame yang dibuat

1. **`Web · 30a Landing (1440)`**: desktop, lebar 1440, tinggi mengikuti isi.
2. **`Web · 30b Landing (390)`**: mobile, lebar 390, satu kolom.
3. **`Web · 30c Waitlist sukses (390)`**: state setelah submit.

Gutter 120 px (desktop) / 20 px (mobile). Radius kartu 32, pill 999. Kartu putih + border `$g-line`.

## Section (urut dari atas)

| # | Section | Isi (copy persis dari page.html) |
|---|---|---|
| 1 | Nav sticky | Orb + "Sysnergi" · How it works · Features · Hub · Home · Pricing · tombol gradien "Join the waitlist" |
| 2 | Hero | Eyebrow "MONITORING & AUTOMATION FOR FARMS, PONDS AND HOMES" · H1 "Oxygen drops at 3 a.m. **The aerator is already on** before you wake up." (bagian bold = gradien biru) · lead · 2 tombol · segmen Pond/Farm/Livestock/Home · 3 proof ✓ · kanan: mockup ponsel (`v3-01-beranda-kolam.webp`) + 2 kartu mengambang ("Aerator switched on / Oxygen 4.1 mg/L · limit 4", "Hub SYN-0A41 / Online · 5 sensors active") |
| 3 | Ribbon metrik | 5 kolom: Dissolved oxygen 4.1 mg/L (Watch · safe ≥ 5, amber) · Water temp 28.4 °C · Water pH 7.2 · Ammonia 0.02 ppm · Water level 82 cm |
| 4 | One night at Pond 2 | Kiri: H2 "Pond problems usually happen while you sleep." + timeline 22:00 / 02:10 / 02:11 / 05:40. Kanan: kartu grafik DO 20:00–08:00, garis putus amber di 4 mg/L, pita biru muda 02:10–05:40 "aerator on", titik 02:10·4.0, low 3.6, 6.0 |
| 5 | Features (bento 6 kolom) | Kartu AI gradien biru (span 4, screenshot `v3-14-chat-asisten-ai.webp`) · Alerts · Telemetry · Guided pH calibration · Invite family & workers · Automations (2 baris aturan dengan toggle) · Keeps working offline (pill "Hub offline 12 min", "2 rules still running") |
| 6 | Hub | Foto `hub-2.webp` + tabel spek (ESP32-WROOM-32, IP65, 6×GX16-8, RS485, 4 relay, Wi-Fi+BT, 220 V, DS3231) · baris port P1–P6/RS485/RELAY/220 V · foto `hub-3.webp` + 4 catatan pemasangan |
| 7 | Setup 3 langkah | Kartu 1–3 dengan screenshot `v3-10a`, `v3-10c`, `v3-10d` (crop bagian bawah) |
| 8 | Sysnergi Home (v4) | Blok gradien violet radius 40 · tag "New · Sysnergi Home" · 4 scene pill · grid 2×2 perangkat (lampu oranye, AC biru, kunci putih "Secure", vakum teal) |
| 9 | Web dashboard | Frame browser + `v3-19-web-dashboard.webp` |
| 10 | Pricing | Toggle Business/Home · 3 kartu Business: Free Rp 0 / Plus Rp 390k/year / Pro Rp 1.19M/year (kartu gradien biru→violet) · catatan hijau "Danger alerts… keep working even if you stop paying." |
| 11 | Waitlist | Kiri: "Get a hub for your pond before launch." + 3 perk. Kanan: kartu form: Your name · Email or WhatsApp · 4 pilihan segmen (Fish pond aktif) · Number of ponds (optional) · City / regency (optional) · tombol penuh "Join the waitlist" · fine print |
| 12 | FAQ | 5 pertanyaan, yang pertama terbuka |
| 13 | Penutup + footer | Orb besar · "Safer ponds, calmer harvests." · 2 tombol · footer "© 2026 Sysnergi / Pond · Farm · Livestock · Home" |

## Selesai bila

- Ketiga frame ada, tanpa elemen yang overflow/terpotong (cek screenshot tiap frame).
- `iot.pen` disimpan, lalu di-commit ke branch `dev`:
  `git add iot.pen && git commit -m "Add landing page frames to iot.pen" && git push origin dev`
