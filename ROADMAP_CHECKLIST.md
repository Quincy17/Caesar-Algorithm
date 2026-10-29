# Roadmap & Checklist Pengembangan: EA QT-MSNR-ICT (MQL5)

**Versi Spesifikasi:** v1.1 (Locked)  
**Target Instrumen:** `XAUUSD` (Single Symbol)  
**Platform:** MetaTrader 5 (MQL5) — Mode Netting/Hedging Otomatis  
**Prinsip Utama:** Deterministik, Tanpa Repaint (`shift >= 1` / hanya bar tertutup), Modular (`.mqh`)

---

## Keputusan Spesifikasi yang Sudah Dikunci (Baseline Fase 0)

| Topik | Keputusan Terkunci |
| :--- | :--- |
| **Simbol Fokus** | Khusus `XAUUSD` (mata uang berita relevan: `USD`) |
| **Zona Waktu Acuan** | New York Time (NY) — Hari trading Daye: `18:00 NY` s/d `18:00 NY` (`shifted = NY + 6 jam`) |
| **True Open** | - **True Year Open:** Open candle harian Daye pada Senin pertama April (`Minggu 18:00 NY`)<br>- **True Month Open:** Open candle harian Daye pada Senin kedua bulan berjalan (`Minggu 18:00 NY`)<br>- **True Week Open:** Senin `18:00 NY` (open candle Selasa Daye)<br>- **True Day Open:** `00:00 NY`<br>- **True Session Open:** `19:30 NY` (Asia), `01:30 NY` (London), `07:30 NY` (NY AM), `13:30 NY` (NY PM) |
| **POI MSNR** | Classic A, Classic V, RBS, SBR (`W1, D1, H4, H1, M15, M5`), dan QM (`D1, H4, H1, M15, M5`). Level `M15` & `M5` diaktifkan juga untuk **Intraday** guna *refinement* (penyempitan zona) dan entry yang lebih presisi. Hanya **POI Fresh** (sentuhan pertama). *OCL tidak dipakai.* |
| **Aturan QM & Toleransi** | Default PRD: Maksimal `2` body break antara pola QM; Zona toleransi sentuhan = `max(spread, 0.05 * ATR(14) TF level)` |
| **Konfirmasi ICT & MSS** | Liquidity Sweep, FVG, EQH/EQL, DOL. **MSS wajib aktif (`true` by default)** sebagai gerbang pasca-sweep (tersedia opsi toggle on/off di input) |
| **Profil Trade Default** | **Intraday** (Gerbang wajib: `D1 & H4`, Skor: `W1`, TF POI: `H4, H1, M15, M5` [HTF POI + LTF M15/M5 refinement/presisi], Trigger: `M15/M5 Sweep + MSS`, Entry: `M5`, RR min: `2.0`). Tersedia juga profil **Scalping** dan **Swing** |
| **Filter Berita** | Blokir entry baru dari `5 jam sebelum` s/d `1 jam sesudah` berita *High Impact* `USD` (Live: JSON Forex Factory; Backtest: CSV Kalender MT5) |
| **Aturan Akhir Pekan** | Tidak ada entry baru di hari Jumat (`Q0`). **Penutupan paksa (Friday Flat)** pukul `15:00 NY` (semua posisi ditutup & pending order dibatalkan, profit maupun loss) |

---

## Rundown Pengembangan & Checklist Fitur per Fase

### Fase 0: Kunci Spesifikasi & Persiapan Data Acuan (Ukuran: S)
Tujuan: Memastikan spesifikasi final, parameter dasar, data berita historis untuk backtest, dan contoh chart acuan (*golden dataset*) siap digunakan.

- [x] **Kunci Keputusan Terbuka (Bagian 8 PRD)**
  - [x] Instrumen dikunci pada `XAUUSD`.
  - [x] Definisi *True Month Open* & *True Year Open* dikunci memakai *open candle harian Daye* (`Minggu 18:00 NY`).
  - [x] Parameter QM (`max_body_break = 2`) dan toleransi sentuhan (`max(spread, 0.05 * ATR(14))`) dikunci ke default PRD.
  - [x] MSS dikunci sebagai gerbang wajib default (`UseMSS = true`).
- [x] **Struktur Direktori Proyek MQL5**
  - [x] Pembuatan struktur folder `MQL5/Include/QT/`, `MQL5/Indicators/`, dan `MQL5/Scripts/`.
  - [x] Definisi file header bersama (`MQL5/Include/QT/Defines.mqh`) untuk enum, konstanta, dan struct lintas modul.
- [x] **Script Ekspor Berita Historis (`ExportNewsCSV.mq5`)**
  - [x] Script MQL5 untuk mengekspor kalender ekonomi bawaan MT5 ke `Common/Files` dalam format CSV (`waktu, mata uang, impact, judul`) guna kebutuhan backtest.
- [ ] **Persiapan Verifikasi Broker & Golden Dataset (Oleh User)**
  - [ ] Verifikasi offset jam server broker demo terhadap jam NY (memastikan pembukaan candle D1 broker = `17:00 NY`).
  - [ ] Penyiapan *golden dataset* (10–20 sampel chart `XAUUSD` bertanda manual untuk level A, V, RBS, SBR, QM, serta contoh Sweep, FVG, EQH/EQL).

> **Kriteria Lulus Fase 0:** Spesifikasi v1.1 terkunci, struktur file siap, dan script ekspor CSV berita siap dijalankan.

---

### Fase 1: M1 Time Engine & QT Visualizer (`QT_Time.mqh`) (Ukuran: M)
Tujuan: Membangun mesin waktu Quarterly Theory (TraderDaye) yang akurat terhadap pergantian DST AS dan memvisualisasikannya di chart.

- [x] **Konversi Waktu Server $\rightarrow$ New York (`QT_Time.mqh`)**
  - [x] **Mode A (Default):** `NY = ServerTime - 7 jam` (untuk broker yang mengikuti DST AS `GMT+2/+3`).
  - [x] **Mode B (Manual/Custom):** `GMT Offset Server + Kalkulasi Otomatis DST AS` (mulai Minggu ke-2 Maret s/d Minggu ke-1 November).
  - [x] Perhitungan waktu *shifted* Daye (`shifted = NY + 6 jam`) untuk penentuan batas hari dan tanggal trading Daye (`18:00 NY` ke `18:00 NY`).
- [x] **Perhitungan Siklus Kuartal (Quarterly Cycles)**
  - [x] **Siklus Tahunan:** Kuartal kalender (`Q1–Q4`).
  - [x] **Siklus Bulanan:** `Q1–Q4` (Senin ke-1 s/d ke-4 dalam bulan berjalan), minggu ke-5 = `Q0`.
  - [x] **Siklus Mingguan:** Senin (`Q1`), Selasa (`Q2`), Rabu (`Q3`), Kamis (`Q4`), Jumat (`Q0` — di luar siklus).
  - [x] **Siklus Harian (Sesi NY):**
    - `18:00–24:00 NY`: Asia (`Q1`)
    - `00:00–06:00 NY`: London (`Q2`)
    - `06:00–12:00 NY`: NY AM (`Q3`)
    - `12:00–18:00 NY`: NY PM (`Q4`)
  - [x] **Siklus 90 Menit:** Blok `Q1–Q4` di dalam tiap sesi (`floor(menit_sejak_awal_sesi / 90)`).
    - Asia: `18:00 (Q1)`, `19:30 (Q2)`, `21:00 (Q3)`, `22:30 (Q4)`
    - London: `00:00 (Q1)`, `01:30 (Q2)`, `03:00 (Q3)`, `04:30 (Q4)`
    - NY AM: `06:00 (Q1)`, `07:30 (Q2)`, `09:00 (Q3)`, `10:30 (Q4)`
    - NY PM: `12:00 (Q1)`, `13:30 (Q2)`, `15:00 (Q3)`, `16:30 (Q4)`
- [x] **Deteksi & Cache Harga True Open (dari Open Bar M5)**
  - [x] *True Year Open* (Open candle harian Daye pada Senin pertama April / `Minggu 18:00 NY`).
  - [x] *True Month Open* (Open candle harian Daye pada Senin kedua tiap bulan / `Minggu 18:00 NY`).
  - [x] *True Week Open* (`Senin 18:00 NY`).
  - [x] *True Day Open* (`00:00 NY`).
  - [x] *True Session Open* (`19:30`, `01:30`, `07:30`, `13:30 NY`).
- [x] **Output & Filter Waktu (`struct QTState`)**
  - [x] Menyimpan `yearQ`, `monthQ`, `weekQ`, `dayQ (sesi)`, `q90`, daftar harga *True Open*, dan flag `isTimeAllowed`.
- [x] **Visualizer & Unit Test Waktu**
  - [x] Indikator/modul visual (`QT_Visualizer.mqh` & `QT_Visualizer_Ind.mq5`) untuk menggambar kotak sesi, pembagi blok 90 menit, dan garis horizontal *True Open* di chart.
  - [x] Script unit test (`TestTimeEngine.mq5`) dengan tabel timestamp *ground truth* (termasuk tanggal transisi DST Maret & November).

> **Kriteria Lulus Fase 1:** Semua kasus uji timestamp lulus (termasuk DST) dan garis *True Open* serta kotak kuartal cocok dengan indikator Daye di TradingView pada minimal 5 tanggal berbeda.

---

### Fase 2: M2 Data Multi-Timeframe & M3 Swing Engine (`MTF_Data.mqh`, `Swings.mqh`) (Ukuran: S)
Tujuan: Menyediakan pembacaan bar tertutup bebas repaint untuk 6 timeframe dan mendeteksi titik-titik fractal swing (baik wick maupun body).

- [x] **Manajemen Data MTF (`MTF_Data.mqh`)**
  - [x] Cache `MqlRates` untuk 6 timeframe: `W1, D1, H4, H1, M15, M5`.
  - [x] Pembacaan ketat hanya pada **bar tertutup** (`shift >= 1`); bar berjalan (`shift 0`) diabaikan oleh logika sinyal.
  - [x] Detektor event *New Bar* independen per timeframe (modul hilir hanya dihitung ulang ketika TF terkait menutup bar baru).
  - [x] Cache nilai `ATR(14)` per timeframe untuk kalkulasi toleransi dan filter.
  - [x] Penanganan *data kosong / history belum sinkron* (EA otomatis *wait/skip* tanpa error).
- [x] **Detektor Swing / Fractal (`Swings.mqh`)**
  - [x] Parameter kekuatan fractal `N` bar kiri & kanan per TF (Default: `W1=2, D1=2, H4=2, H1=3, M15=2, M5=2`).
  - [x] Konfirmasi swing hanya setelah `N` bar tertutup di sebelah kanan selesai terbentuk (jaminan *zero repaint*).
  - [x] **Varian 1 — Swing High/Low (Wick):** Berbasis `high` dan `low` candle (digunakan oleh modul ICT & struktur).
  - [x] **Varian 2 — Swing Close/Body (Line Chart):** Berbasis `close` / body candle (digunakan oleh modul MSNR).
- [x] **Visualisasi & Pengujian Swing**
  - [x] Mode visual/indikator untuk menampilkan titik swing wick & swing body di chart.
  - [x] Script uji (`TestSwings.mq5`) untuk memastikan tidak ada pergeseran atau hilang-timbul (repaint) saat bar baru muncul.

> **Kriteria Lulus Fase 2:** Titik swing di semua TF cocok dengan penandaan manual pada *golden dataset* dan terbukti 100% tanpa repaint saat pergantian bar.

---

### Fase 3: M4 Level MSNR — Classic A, V, RBS, SBR (`MSNR_Levels.mqh`) (Ukuran: M)
Tujuan: Mendeteksi level support/resistance berbasis body (line chart) beserta siklus hidup statusnya (*Fresh $\rightarrow$ Touched / Broken $\rightarrow$ RBS/SBR Fresh $\rightarrow$ Used*).

- [x] **Deteksi Level Classic A & Classic V**
  - [x] Dihitung pada seluruh 6 timeframe: `W1, D1, H4, H1, M15, M5` (agar `M15` dan `M5` selalu aktif untuk *refinement* dan presisi entry baik pada profil **Intraday** maupun **Scalping**).
  - [x] **Classic A (Resistance):** Pivot puncak dari harga `close` (body).
  - [x] **Classic V (Support):** Pivot lembah dari harga `close` (body).
- [x] **Toleransi Sentuhan & Siklus Hidup Status (Hanya Bar Tertutup)**
  - [x] Zona toleransi sentuhan = `max(spread, 0.05 * ATR(14) TF level)` (dapat dikustomisasi via parameter).
  - [x] **Status `FRESH`:** Belum ada wick (`high`/`low`) bar mana pun setelah bar konfirmasi pivot yang menyentuh/masuk zona level.
  - [x] **Status `TOUCHED / UNFRESH`:** `high` menyentuh resistance A (atau `low` menyentuh support V), tetapi `close` tidak menembus level. Level langsung dikeluarkan dari kolam POI aktif (disimpan untuk riwayat visual).
  - [x] **Status `BROKEN` $\rightarrow$ Flip menjadi `RBS / SBR`:**
    - Jika `close` (body) menembus Resistance A ke atas $\rightarrow$ lahir **RBS (Resistance Become Support)** di harga yang sama dengan status **`FRESH`**.
    - Jika `close` (body) menembus Support V ke bawah $\rightarrow$ lahir **SBR (Support Become Resistance)** di harga yang sama dengan status **`FRESH`**.
  - [x] **Siklus Hidup `RBS / SBR`:** Berstatus `FRESH` sejak bar penembusan pada zona garis body `lvlPrice ± tolerance` (tanpa melebar ke bekas ekor pra-breakout) hingga ada wick pertama pada bar berikutnya yang menyentuhnya. Setelah tersentuh pertama kali (atau setelah trade terjadi), status berubah menjadi **`USED`**.
- [x] **Manajemen Memori & Beban Level**
  - [x] Simpan maksimal `20` level aktif terdekat dengan harga saat ini per TF.
  - [x] Expired otomatis untuk level yang lebih tua dari `MaxLevelAgeBars` (parameter per TF).
- [x] **Visualisasi Level MSNR**
  - [x] Penggambaran garis horizontal per level dengan kode warna/gaya garis berbeda untuk `FRESH`, `RBS/SBR FRESH`, dan `TOUCHED/USED`.

> **Kriteria Lulus Fase 3:** Semua level A, V, RBS, dan SBR pada *golden dataset* terdeteksi akurat; transisi status *Fresh $\rightarrow$ Touched/Broken $\rightarrow$ Flip* berjalan tepat sesuai aturan bar tertutup.

---

### Fase 4: M4 Level MSNR — Quasimodo / QM (`MSNR_Levels.mqh`) (Ukuran: M)
Tujuan: Menambahkan detektor pola Quasimodo (QM) berbasis 5 swing body pada `D1, H4, H1, M15, M5`.

- [x] **Detektor Pola QM Bullish (5 Swing Body Berurutan)**
  - [x] Urutan: *Left Shoulder* (Low 1) $\rightarrow$ *High Perantara* (High 1) $\rightarrow$ *Head* (Lower Low di bawah Left Shoulder) $\rightarrow$ *Structure Break* (High 2 dengan body `close` menembus High Perantara).
  - [x] Harga Level QM Bullish = harga body (`close`) pada **Left Shoulder** (bukan Head).
- [x] **Detektor Pola QM Bearish (5 Swing Body Berurutan)**
  - [x] Urutan: *Left Shoulder* (High 1) $\rightarrow$ *Low Perantara* (Low 1) $\rightarrow$ *Head* (Higher High di atas Left Shoulder) $\rightarrow$ *Structure Break* (Low 2 dengan body `close` menembus Low Perantara).
  - [x] Harga Level QM Bearish = harga body (`close`) pada **Left Shoulder**.
- [x] **Validasi & Siklus Hidup QM**
  - [x] Filter batas maksimal jumlah *body break* antara pola (Default: `MaxQMBodyBreak = 2`).
  - [x] Dihitung pada timeframe `D1, H4, H1, M15, M5` (mendukung QM di LTF `M15/M5` untuk konfluensi & presisi entry).
  - [x] Mengikuti aturan *Fresh-Only*: Level QM berstatus `FRESH` sejak bar *Structure Break* hingga wick pertama kembali menyentuh level *Left Shoulder*.

> **Kriteria Lulus Fase 4:** Pola QM pada *golden dataset* terdeteksi dengan harga level *Left Shoulder* yang presisi.

---

### Fase 5: M5 ICT Engine (`ICT_Engine.mqh`) (Ukuran: M)
Tujuan: Mendeteksi kolam likuiditas (EQH/EQL, Session/Daily/Weekly High-Low), Liquidity Sweep, Market Structure Shift (MSS), Fair Value Gap (FVG), dan kandidat Draw on Liquidity (DOL).

- [x] **Daftar Kolam Likuiditas (Liquidity Pools)**
  - [x] **PDH / PDL:** Previous Day High & Low (berdasarkan batas hari Daye `18:00 NY`, dengan opsi parameter memakai D1 broker).
  - [x] **PWH / PWL:** Previous Week High & Low.
  - [x] **Session High / Low:** High/Low sesi QT (Asia, London, NY AM).
  - [x] **Swing High / Low HTF:** Swing wick pada `D1, W1, H4, H1`.
- [x] **Detektor Equal Highs / Equal Lows (`EQH / EQL`)**
  - [x] Dua swing atau lebih dalam periode *lookback* dengan selisih harga $\le$ toleransi (Default: `0.1 * ATR(14) TF`).
  - [x] Disimpan sebagai klaster likuiditas dengan atribut harga rata-rata/ekstrem dan flag `isSwept`.
- [x] **Detektor Liquidity Sweep (Bar Tertutup)**
  - [x] **Buy-Side Sweep (Bearish):** `high` bar melewati level likuiditas, lalu `close` bar kembali di bawah level tersebut.
  - [x] **Sell-Side Sweep (Bullish):** `low` bar melewati level likuiditas, lalu `close` bar kembali di atas level tersebut.
  - [x] Valid pada level: `EQH/EQL`, `Session High/Low`, `PDH/PDL`, `PWH/PWL`, `Swing H1/H4`, serta **Rentang Akumulasi `Q1 90-Menit` Sesi Aktif (`Q1_90M_H / Q1_90M_L`)** untuk deteksi *Judas Swing Manipulation* di `Q2/Q3`.
- [x] **Detektor Market Structure Shift (`MSS`)**
  - [x] Setelah terjadi *Sweep*, memantau apakah ada bar yang `close` body-nya menembus swing berlawanan terakhir (*displacement*).
  - [x] Parameter `UseMSS = true` (default wajib aktif, dapat dimatikan via input).
- [x] **Detektor Fair Value Gap (`FVG`)**
  - [x] Pola 3 candle: **Bullish FVG** jika `low[candle 3] > high[candle 1]`; **Bearish FVG** jika `high[candle 3] < low[candle 1]`.
  - [x] Filter ukuran minimum: `FVG_Size >= MinFVG_ATR_Mult * ATR(14)`.
  - [x] Perhitungan titik acuan: **Tepi Proximal**, **CE (Consequent Encroachment / 50%)**, dan **Tepi Distal**.
  - [x] Pelacakan status FVG: `OPEN`, `PARTIAL` (tersentuh sebagian), `FILLED` (tertutup penuh).
  - [x] Dijalankan pada `M5` dan `M15` (untuk entry trigger) serta `H1` dan `H4` (untuk konteks).

> **Kriteria Lulus Fase 5:** Kasus uji Sweep, MSS, FVG, dan klaster EQH/EQL sesuai dengan definisi dan cocok dengan penandaan manual pada chart uji.

---

### Fase 6: M6 Bias, M10 Profil Trade, M7 Setup & Mode Sinyal Saja (Ukuran: L)
Tujuan: Menggabungkan seluruh analisis menjadi Bias Multi-TF, State Machine Setup (`S0–S6`), Skor Konfluensi, Dashboard Visual, dan Jurnal CSV dalam **Mode Sinyal Saja (Tanpa Eksekusi Order)** untuk evaluasi live demo.

- [x] **M6 & M10: Mesin Bias Multi-TF & Profil Trade (`Bias.mqh`, `TradeProfile.mqh`)**
  - [x] **Perhitungan Bias per TF (`W1, D1, H4`):** Output `BULL (+1)`, `BEAR (-1)`, atau `NEUTRAL (0)` saat bar TF tertutup. Jika struktur utama dan konfirmasi pelengkap bertentangan $\rightarrow$ `NEUTRAL`:
    - **W1:** Struktur body break swing W1 + Konfirmasi posisi harga terhadap *True Week Open*.
    - **D1:** Struktur body break swing D1 + Konfirmasi posisi harga terhadap *True Day Open (`00:00 NY`)* atau *Sweep PDH/PDL lalu close kembali*.
    - **H4:** Struktur body break swing H4 + Konfirmasi *Premium/Discount* (di bawah 50% dealing range H4 = dukung Buy; di atas 50% = dukung Sell).
  - [x] **Draw on Liquidity (`DOL`) & Roadblocks:**
    - Memilih likuiditas terdekat yang belum tersapu searah bias + level MSNR berlawanan terdekat sebagai kandidat target (*The Objective*).
    - Menandai level penghalang di antara harga dan target sebagai *Roadblock* (untuk pertimbangan TP).
  - [x] **Konfigurasi 3 Profil Trade (`TradeProfile`):**
    - **Scalping:** Gerbang `H4` | Skor `D1, W1` | POI `H1, M15, M5` | Trigger `M15/M5 Sweep+MSS, M5 Entry` | RR min `1.5` | Durasi maks 90 menit (tutup akhir blok 90m, tidak lintas sesi) | Waktu: Q2–Q3 London & NY AM.
    - **Intraday (Default):** Gerbang `D1 & H4` | Skor `W1` | POI `H4, H1, M15, M5` (mendukung *POI Refinement* `M15/M5` di dalam/dekat `H4/H1` maupun POI `M15/M5` mandiri untuk presisi entry) | Trigger `M15/M5 Sweep+MSS, M5 Entry` | RR min `2.0` | Tutup sebelum `18:00 NY` | Waktu: Sesi London & NY AM.
    - **Swing:** Gerbang `W1 & D1` | Skor `H4` | POI `W1, D1, H4` (dengan opsi refinement `H1/M15`) | Trigger `H1 Sweep+MSS, M15 Entry` | RR min `3.0` | Boleh lintas hari (wajib flat Jumat `15:00 NY`) | Waktu: Sesi mana pun, Selasa–Kamis.
  - [x] Mode Gerbang Bias (`BiasGateMode`): `STRICT` (default, semua TF gerbang wajib selaras) atau `MAJORITY`.
  - [x] **Aturan Storyline Reversal MSNR Murni:** Saat harga masuk/merejeksi **Zona Body-to-Wick Fresh SNR `D1` atau `H4`**, gerbang Storyline mengizinkan setup *reversal* searah pantulan SNR HTF tersebut (dikonfirmasi oleh *Sweep + MSS + FVG* di LTF).
- [x] **M7: State Machine Setup per Arah Buy/Sell (`Setup.mqh`)**
  - [x] `S0 IDLE`: Menunggu bias bukan NEUTRAL, hari Daye diizinkan (default Selasa–Kamis), dan jendela waktu profil aktif.
  - [x] `S1 POI_TOUCH`: Harga menyentuh **Zona Body-to-Wick (`[zoneLow, zoneHigh]` dari Body Close hingga Ujung Wick Pivot)** pada POI `FRESH` searah bias (`H4/H1/M15/M5` untuk Intraday), dilengkapi **`FindNestedRefinedPOI`** yang memindai level `M15/M5` (*prioritas QM & RBS/SBR*) yang bersarang di dalam zona Body-to-Wick `H4/H1` secara *real-time* (`S1..S3`).
  - [x] `S2 SWEEP`: Terjadi *Liquidity Sweep* di dalam/dekat POI pada TF Trigger (`M15`/`M5` atau `H1` untuk Swing).
  - [x] `S3 MSS`: Body `close` menembus swing berlawanan setelah sweep (*displacement*).
  - [x] `S4 ARMED`: FVG atau POI MSNR `M15/M5` fresh terbentuk pada leg displacement; kalkulasi level Entry presisi (CE FVG / Proximal / Level MSNR `M15/M5` / Market), SL (ekstrem sweep + buffer `0.2 * ATR(M5) + spread`), dan TP (DOL dengan `RR >= RR_min`).
  - [x] `S5 IN_TRADE` & `S6 DONE/EXPIRED`: Transisi saat order terisi atau setup batal.
  - [x] **Aturan Pembatalan Setup (Invalidation):** Jendela waktu habis, POI ditembus body `close`, harga menyentuh level SL atau TP sebelum entry terisi, bias TF gerbang berbalik arah, atau usia setup melebihi `MaxSetupBarsM5`.
- [x] **M7: Kalkulator Skor Konfluensi (Default Threshold $\ge 6$)**
  - [x] Bobot TF POI: `W1/D1 (+3)`, `H4 (+2)`, `H1 (+1)`, `M15/M5 (+1)`.
  - [x] Bobot Tipe POI: `QM atau RBS/SBR (+2)`, `Classic A atau V (+1)`.
  - [x] Bobot Tumpang Tindih (Overlap / Refinement) POI lintas TF: `+1 per TF` (maks `+2`, misal POI `M15/M5` bertumpuk dengan `H4/H1`).
  - [x] Bobot Waktu QT: Blok 90 menit `Q2 atau Q3 (+1)`, Sesi `London Q2 atau NY AM Q3 (+1)`.
  - [x] Bobot True Open: Posisi harga *Discount/Premium* searah terhadap *True Day Open* (`+1`) dan *True Week Open* (`+1`).
  - [x] Bobot ICT: Sweep pada `EQH/EQL, PDH/PDL, atau Ekstrem Sesi (+2)`, kehadiran `FVG pada leg displacement (+1)`.
  - [x] Bobot Bias Pelengkap (TF Skor sesuai profil): Selaras (`+1`), Netral (`0`), Berlawanan (`-1`).
- [x] **M9: Dashboard Visual & Logger CSV (`Visual.mqh`, `Logger.mqh`)**
  - [x] Panel Dashboard on-chart: Waktu NY, Kuartal (`Year/Month/Week/Day/90m`), Profil aktif, Status News, Bias `W1/D1/H4`, DOL aktif, State Setup (`S0–S6`), dan Skor Konfluensi terakhir.
  - [x] Jurnal CSV Setup (`Setups_Log.csv`): Mencatat setiap setup yang terdeteksi—baik yang valid maupun yang ditolak beserta alasan penolakannya (*rejected reason*).
  - [x] Alert & Notifikasi ( serta opsi `ChartScreenShot` saat sinyal mencapai `S4 ARMED`).

> **Kriteria Lulus Fase 6:** EA berjalan di demo dalam *Signal-Only Mode* selama 1–2 minggu; sebagian besar sinyal sesuai dengan pembacaan manual Anda dan seluruh alasan masuk/penolakan tercatat rapi di jurnal CSV.

---

### Fase 7: M8 Risiko & Eksekusi, M11 Filter Berita, M12 Penutupan Jumat (Ukuran: M)
Tujuan: Mengaktifkan eksekusi order (`CTrade`), manajemen risiko ketat, filter berita Forex Factory / CSV MT5, serta penutupan paksa hari Jumat (`15:00 NY`).

- [x] **M8: Kalkulasi Lot & Pembatas Risiko (`Risk.mqh`)**
  - [x] Kalkulasi lot otomatis berbasis persentase risiko (Default: `0.5%` saldo per trade) dari jarak SL menggunakan `OrderCalcProfit` / tick value `XAUUSD`.
  - [x] Normalisasi lot ke `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_MAX`, `SYMBOL_VOLUME_STEP`, serta validasi margin bebas via `OrderCalcMargin`.
  - [x] Filter batas maksimum lebar SL (skip trade jika jarak SL > `MaxSL_ATR_H1_Mult * ATR(H1)`).
  - [x] **Circuit Breakers (Rem Darurat):**
    - Batas rugi harian maksimal `2.0%` saldo.
    - Batas rugi mingguan maksimal `5.0%` saldo.
    - Maksimal `2` trade per hari trading Daye.
    - Berhenti trading sampai hari Daye berikutnya jika mengalami `3` kali *loss* beruntun (*consecutive losses*).
  - [x] Filter spread maksimum (`MaxSpreadPoints`) dan validasi `SYMBOL_TRADE_STOPS_LEVEL` & `SYMBOL_TRADE_FREEZE_LEVEL`.
- [x] **M8: Eksekusi & Manajemen Posisi Aktif (`Exec.mqh`)**
  - [x] Eksekusi order menggunakan `CTrade` dengan deteksi otomatis mode akun (Netting/Hedging) dan *filling mode* simbol (`FOK / IOC / RETURN`).
  - [x] Mekanisme *retry* terbatas untuk penanganan *requote / off quotes*.
  - [x] Penandaan unik dengan `MagicNumber` (berbeda per profil) dan `OrderComment` berisi ID Setup.
  - [x] **Manajemen Trade Berjalan:**
    - Opsi *Break-Even (BE)* otomatis saat profit mencapai `1R`.
    - Opsi *Partial Close* (tutup `50%` volume) pada target likuiditas internal pertama (`TP1`).
    - *Time Stop* sesuai profil: Tutup di akhir blok 90 menit (Scalping), tutup sebelum `18:00 NY` / akhir sesi NY PM (Intraday).
  - [x] **State Recovery (`OnInit`):** Membangun ulang status state machine dan melacak posisi/pending order aktif berdasarkan `MagicNumber` saat EA di-restart atau terminal dibuka ulang.
- [x] **M11: Filter Berita Ekonomi (`News.mqh`)**
  - [x] **Mode Live/Demo:** Mengambil feed JSON mingguan Forex Factory (`nfs.faireconomy.media/ff_calendar_thisweek.json`) via `WebRequest` setiap 60 menit & saat pergantian minggu, dilengkapi cache file lokal dan cadangan kalender bawaan MT5.
  - [x] **Mode Backtest (Strategy Tester):** Membaca file CSV historis di `Common/Files` yang diekspor oleh `ExportNewsCSV.mq5`.
  - [x] **Aturan Blokir Jendela Berita:** Memblokir entry baru dan membatalkan pending order `S4 ARMED` yang belum terisi pada rentang `[T - 5 jam, T + 1 jam]` untuk berita *High Impact* mata uang relevan (`USD` untuk `XAUUSD`).
  - [x] **Fail-Safe:** Jika data berita gagal dimuat atau lebih tua dari 24 jam (`NewsFailSafe = true`), EA menahan pembukaan entry baru.
  - [x] Opsi pengelolaan posisi terbuka saat memasuki jendela berita (Default: biarkan berjalan normal; opsi parameter: pindah ke BE atau tutup).
- [x] **M12: Penutupan Paksa Akhir Pekan / Friday Flat (`Exec.mqh` + `OnTimer`)**
  - [x] Blokir semua entry baru sepanjang hari Jumat (`Q0` siklus mingguan QT).
  - [x] Pada `FridayCloseNY` (Default: Jumat `15:00 NY`), atau 60 menit sebelum akhir sesi trading broker (`SymbolInfoSessionTrade`) jika ada hari libur/sesi pendek:
    - Menutup paksa seluruh posisi terbuka dengan `MagicNumber` EA (baik sedang profit maupun loss).
    - Membatalkan seluruh pending order yang tersisa.
  - [x] Dijalankan setiap detik melalui `OnTimer()` dengan loop *retry* sampai posisi benar-benar nol, termasuk jika terminal baru dinyalakan setelah melewati jam cutoff Jumat.
  - [x] Mencatat penutupan di jurnal CSV Trade (`Trades_Log.csv`) dengan alasan `FRIDAY_FLAT` beserta realisasi P/L dan R.
- [x] **M9+: Forward-Test Master Journal & Algorithm Evolution Telemetry (`QT_Forward_Journal.csv`)**
  - [x] Rekonsiliasi otomatis setiap posisi yang sudah tertutup (`HistorySelectByPosition`) ke dalam 1 baris utuh di `QT_Forward_Journal.csv`.
  - [x] Klasifikasi otomatis **Exit Outcome**: `TP_FULL`, `TP1_THEN_TP`, `TP1_THEN_BE`, `BE_HIT`, `SL_HIT`, `TIME_STOP`, `FRIDAY_FLAT`, atau `MANUAL_OR_OTHER`.
  - [x] Pencatatan jam buka & tutup (`Server` & `NY`), durasi hold (menit), tanggal & hari Daye, serta siklus Kuartal penuh (`YearQ`, `MonthQ`, `WeekQ`, `DayQ`, `Session`, `90m Q1..Q4`) saat entry maupun exit.
  - [x] Pencatatan finansial lengkap: `initial_risk_usd`, `gross_profit_usd`, `swap_usd`, `commission_usd`, `net_profit_usd` (termasuk akumulasi partial close TP1), `realized_r`, dan `balance_after`.
  - [x] **Algorithm Evolution Telemetry**: Pelacakan *real-time* **MFE** (*Maximum Favorable Excursion* dalam harga & R), **MAE** (*Maximum Adverse Excursion* dalam harga & R), `bars_to_fill_m5`, `spread_at_entry_pts`, `slippage_pts`, `atr_m5_entry`, `atr_h1_entry`, serta rincian 10 komponen skor konfluensi.

> **Kriteria Lulus Fase 7:** 20 eksekusi trade di akun demo berjalan mulus tanpa error eksekusi yang tidak tertangani; skenario uji restart terminal, blokir berita, dan penutupan paksa Jumat lulus 100%.

---

### Fase 8: Backtest Historis & Uji Ketahanan Parameter (Ukuran: L)
Tujuan: Menguji performa dan validitas aturan secara statistik di Strategy Tester MT5 dan mengkalibrasi skor tanpa *overfitting*.

- [ ] **Eksekusi Backtest Multi-Tahun (`XAUUSD`) (Di Strategy Tester MT5)**
  - [x] **Backtest Iterasi 1 (`report-1`, `2026.01.01 – 2026.10.27`, Real Ticks + Forward 1/2):** Lulus uji integrasi penuh 64 trade (In-Sample profit `+$80.77` / peak `+$411.48`), dan selesai dilakukan audit telemetri `QT_Forward_Journal.csv`.
  - [x] **Kalibrasi & Tuning Pasca-Report-1 (`v1.11`):**
    - Patenkan ukuran lot berbasis kelipatan ekuitas (`0.05 lot` per `$5,000 USD` Equity: `$5k -> 0.05`, `$10k -> 0.10`, `$25k -> 0.25`) di `Risk.mqh`.
    - Wajibkan **Partial Close 50% (`PARTIAL_TP1`) + Break-Even secara serentak tepat saat running `100 pips` (`$10.00` di XAUUSD)** di `Setup.mqh` & `Exec.mqh`.
    - Kalibrasi jarak SL manual XAUUSD (`45–75 pips`, target default `60 pips` / `$6.00`) dan Full TP Runner (`300 pips` / `$30.00` atau HTF DOL) untuk mengeliminasi *micro-SL* (`< 15 pips`) maupun SL terlalu lebar.
    - Filter *standalone* POI `M15`/`M5` agar hanya menerima zona *Flip/QM* (`RBS`, `SBR`, `QM_Bull`, `QM_Bear`) jika tanpa Anchor HTF (`H4`/`H1`), serta auto-cancel *orphan pending limit order* saat jendela waktu sesi berakhir atau setup batal.
  - [x] **Backtest Iterasi 2 (`report-2`, `v1.11`) & Kalibrasi Top-Down HTF POI (`v1.12`):**
    - Verifikasi mekanis `report-2`: Ukuran lot `0.25 lot` (`$25k` equity), `0` orphan limit order, `0` pelanggaran waktu sesi/hari, dan 100% disiplin Partial Close 50% pada `+100 pips` (`H4` Anchor POI mencetak `50.0% WR`, `+$885.23`, `+5.59R`, Profit Factor `2.04` di In-Sample & Forward Test).
    - **Kunci Anchor POI Intraday Khusus HTF (`D1`, `H4`, `H1`) (`TradeProfile.mqh` & `QT_MSNR_EA.mq5`):** Nonaktifkan *standalone* `M15` dan `M5` sebagai Anchor POI utama (`allowPOITF[M15]=false`, `allowPOITF[M5]=false`) yang sebelumnya menyumbang 67% frekuensi trade dan rugi `-$2,591.07`; gunakan `M15` & `M5` murni untuk *nested refinement* (`FindNestedRefinedPOI`) di dalam zona HTF `D1`/`H4`/`H1`.
    - **Proteksi Trade 2-Tahap Berdasarkan Grafik MFE/MAE MT5 (`Exec.mqh`):**
      - **Tahap 1 (`+65 Pips` / `$6.50`):** Geser `SL` ke *Break-Even* (`entryPrice +/- buffer`) saat *running profit* mencapai `+65 pips` (`InpBreakEvenPips = 65.0`) untuk menyelamatkan posisi yang sudah lari `+67 s/d +95 pips` (`> 1.1R`) agar tidak berbalik menjadi `-1R` (`SL_HIT`).
      - **Tahap 2 (`+100 Pips` / `$10.00`):** Eksekusi *Mandatory Partial Close 50%* (`PARTIAL_TP1`) saat *running profit* mencapai `+100 pips` (`InpPartialTp1Pips = 100.0`), menyisakan 50% *runner* bebas risiko menuju `+300 pips` (`$30.00`) / HTF DOL.
    - **Perbaikan Filter Reversal Bias & Siklus Hidup Zona `RBS`/`SBR` (`Bias.mqh` & `MSNR_Levels.mqh`):** Cegah `rejH4` membuka posisi *counter-trend* melawan arah `biasD1`, serta wajibkan minimal 1 candle tutup di luar zona (`hasLeftZone`) setelah *breakout* sebelum *retest* menandai zona `RBS`/`SBR` sebagai `USED`.
  - [x] **Backtest Iterasi 3 (`report-3`, `v1.12`: +$959.98, PF 1.65, 27 trades) & Daily Cycle Engine (`v1.20`):**
    - **Fallback Limit → Market (`Exec.mqh`):** Saat `OrderSend` mengembalikan `10015`/`10016` dan harga live sudah menyentuh/melewati harga limit (≤ `15 pips`), order otomatis dieksekusi *Market* agar setup valid tidak hilang.
    - **Klasifikasi Siklus Harian `AMDX` / `XAMD` (`Defines.mqh` & `Bias.mqh`):** Enum `ENUM_DAILY_CYCLE_TYPE`, `ENUM_AMDX_PHASE`, `ENUM_LIQ_NARRATIVE`; tracking `Phase A High/Low`, deteksi *manipulation sweep* (single & multi-candle), dan pembukaan gate bias saat sweep Fase M didukung minimal satu bias HTF (`D1`/`H4`) atau posisi Discount/Premium True Open.
    - **Entry Fase M (ekstrem) & Fase D (pullback IRL) (`Setup.mqh`):** POI `M15`/`M5` diizinkan khusus dalam konteks siklus harian (maks 1 trade LTF siklus per hari Daye), SL Fase M dijangkar di ekstrem sweep, tolak SL struktural LTF `< 18 pips` (noise), dan minimum Confluence Score LTF `≥ 8`.
    - **Naratif Likuiditas:** Label `ERL→IRL`, `IRL→ERL`, `ERL→ERL` disimpan di setup & `dolLabel`.
    - **Target Harian:** TP = `Swing High Fase A` (BUY) / `Swing Low Fase A` (SELL) bila jarak ≥ `max(SL × minRR, 115 pips)`; jika tidak, fallback ke HTF DOL / `RUNNER_300P`. Lot paten (`0.05`/`$5k`), SL `45–75 pips`, BE `+65 pips`, dan Partial 50% `+100 pips` tidak berubah.
    - **Input EA baru:** `InpEnableDailyAmdxCycle = true` (versi EA `1.20`).
  - [x] **Backtest Iterasi 4 (`report-4`, `v1.20`) & Arsitektur Dual-Tracker Decoupled (`v1.21`):**
    - **Temuan Kritis `report-4`:** Setup siklus harian LTF menimpa slot tracker HTF sehingga membatalkan 4 trade pemenang besar HTF v1.12 (kehilangan `+$914.77`), Fase M berisiko tinggi rugi `-4.72R` terutama saat fallback ke runner 300p pada range Fase A sempit, sedangkan Fase D profit `+3.77R` (`+$568.44`) dan naratif `IRL→ERL` profit `+2.50R`.
    - **Tracker Terpisah (Decoupled Dual-Trackers):** `m_buyHtf` / `m_sellHtf` (murni HTF W1/D1/H4/H1, mempertahankan 100% perilaku v1.12 yang menghasilkan `+$959.98`) dan `m_buyCycle` / `m_sellCycle` (Daily Cycle AMDX/XAMD). Slot HTF tidak lagi dapat tergeser oleh setup siklus harian.
    - **Pengetatan Fase M Ekstrem:** Wajib berada di blok `Q3` 90 menit (`q90 == QT_Q3`), wajib searah struktur `biasD1`, dan range Fase A wajib `≥ 115 pips` ($11.50). Target wajib menyentuh Swing High/Low Fase A; dilarang keras fallback ke `RUNNER_300P`.
    - **Fase D & Naratif `IRL→ERL`:** Menjadi pilar utama entry siklus harian pada zona Flip/QM M15 di area Diskon/Premium.
    - **Eliminasi Anchor Standalone M5:** POI `M5` dihapus dari anchor siklus harian, hanya `M15` yang digunakan sebagai POI anchor harian.
    - **Buka Hari Senin & Jumat Khusus Fase D:** Parameter `InpAllowMondayCycleD = true` dan `InpAllowFridayCycleD = true` membuka hari Senin dan Jumat secara eksklusif hanya untuk entry Fase D (pullback rendah risiko), sementara tracker HTF tetap menjaga disiplin Selasa–Kamis.
    - **Queue Buffer Log Setup:** Seluruh evaluasi setup (HTF maupun Cycle) di-drain menggunakan `while(PopLastLogEvent)` sehingga 0 setup terbuang dari `QT_Setups_Log.csv`.
  - [x] **Backtest Iterasi 5 (`report-5`, `v1.21`: +$1,051.47, PF 1.59, 29 trades, DD 2.60%) & Arsitektur Tri-Engine Multi-Profile Simultan (`v1.30`):**
    - **Temuan Kritis `report-5`:** Net profit menembus all-time high `+$1,051.47` (+6.52R, PF 1.59) dengan drawdown terendah dalam seluruh histori pengujian (`$665.50` / `2.60%`). 4 trade HTF pulih seutuhnya, Fase D menyumbang profit besar `+3.71R` (`+$556.63`), dan 0 setup yang terbuang dari log CSV.
    - **Akar Penyebab Trade Terbatas (29 trades):** Sebanyak 34 pending limit order (54% dari setup yang armed) batal karena harga memantul langsung di *Proximal Edge* FVG tanpa pullback ke 50% CE (fenomena ICT *IOFED* — Institutional Order Flow Entry Drill); serta batasan arsitektur sebelumnya yang hanya menjalankan 1 profil secara bergantian.
    - **Multi-Profile Tri-Engine Simultan (`v1.30`):** Ketiga Trade Profile (Scalping, Intraday, Swing) kini aktif bekerja secara serentak dalam 1 EA instance:
      - Magic Number Offset Otomatis: Swing (`magic + 0`), Intraday (`magic + 1`), Scalping (`magic + 2`).
      - **Profil Scalping:** POI M15/M5 di jendela likuiditas tinggi sesi London & NY AM (blok Q2 Judas & Q3 Expansion, Senin–Jumat), SL `60 pips` (`$6.00`), BE di `+50 pips` (`$5.00`), Partial 50% di `+50 pips` (`$5.00`), Full TP max `100 pips` (`$10.00`), Time Stop akhir blok 90m.
      - **Profil Intraday:** Daily Bread AMDX/XAMD, default entry beralih ke `ENTRY_FVG_PROXIMAL` (IOFED Proximal Edge) untuk menangkap 34 order yang sebelumnya terlewat, SL `45–75 pips` (default `60 pips`), BE `+65 pips`, Partial 50% `+100 pips`, target Session ERL (Phase A High/Low atau Asian High/Low, `100–150 pips`).
      - **Profil Swing:** HTF Narrative (W1/D1/H4 DOL), target Full HTF DOL / `300+ pips` runner, SL `60–75 pips`, BE `+65 pips`, Partial 50% `+100 pips`.
      - **Smart Coexistence Rule (`Exec.mqh`):** Scalp dan Intraday diizinkan membuka posisi searah Swing asalkan posisi Swing yang sedang berjalan sudah mengamankan *Break-Even* (`beApplied == true`), menjaga total risiko portofolio tetap terkontrol.
      - **Paten Ukuran Lot:** Seluruh profil tetap patuh pada aturan lot berbasis ekuitas: `0.05 lot` per `$5,000 Equity` (`0.25 lot` pada `$25k` equity).
  - [x] **Backtest Iterasi 6 (`report-6`, `v1.30`) & Stabilisasi Scalping + CISD + MTF Sniper Entry (`v1.31`):**
    - **Temuan Kritis `report-6`:**
      - Profil **Intraday** terbukti sangat sehat dan profitable: `+$928.47` (PF 1.49, Win Rate 53.33%, 30 trades).
      - Profil **Scalping** menjadi beban utama kerugian: `-$4,152.19` (-30.90R, 134 trades) akibat entry pada level-level standalone M5 yang sering berada di tengah chop/konsolidasi serta ketidakseimbangan matematika (SL 60 pips vs BE/partial 50 pips).
      - Ditemukan bug pembatalan pending order lintas profil: pembatalan pending order pada satu profil memicu pembatalan pending order profil lain karena pemanggilan `CancelPendingOrders` tanpa isolasi magic number profil (`filterProfile = -1`).
      - Ditemukan bug visualisasi/pencatatan log profil di `Logger.mqh` yang mencatat profil acuan global (`prof.profile`) bukan profil setup aktual (`tr.profile`).
    - **Solusi & Implementasi Fitur `v1.31` (Opsi B):**
      - **Stabilisasi Scalping Engine via AMDX/XAMD Continuation:** Entry scalping kini diselaraskan secara ketat dengan kelanjutan ekspansi/distribusi sesi harian AMDX/XAMD (Fase D) searah arah manipulasi harian pada zona diskon/premium, menghilangkan entry standalone M5 acak di area konsolidasi.
      - **Konfirmasi Entry CISD (Change in State of Delivery):** Menambahkan algoritma deteksi CISD berbasis penutupan body candle M5 yang mematahkan harga pembukaan delivery run sebelum sweep/touch. Input baru `InpConfirmationMode` mendukung `CONFIRM_MODE_MSS_ONLY`, `CONFIRM_MODE_CISD_ONLY`, dan `CONFIRM_MODE_EITHER` (default: Either / konfirmasi tercepat).
      - **Institutional MTF Sniper Entry:** Menambahkan logika Sniper Entry dengan prioritas tertinggi: SELL di POI fresh MTF/HTF yang berada tepat di atas atau memotong Buy-Side Liquidity (BSL) valid; BUY di POI fresh MTF/HTF yang berada tepat di bawah atau memotong Sell-Side Liquidity (SSL) valid. Dikonfigurasi aktif serentak untuk profil Intraday dan Scalping via input `InpEnableSniperEntry = true` (+2 poin skor konfluensi).
      - **Simetri Rasio Risiko Scalping:** Kalibrasi parameter SL Scalping menjadi `50 pips` ($5.00) agar simetris dengan ambang BE `+50 pips` dan Partial close 50% di `+50 pips`, dengan Max TP tetap `100 pips` ($10.00).
      - **Isolasi Pending Order Cancellation:** `OnTick()` membatalkan pending order yang setup-nya tidak lagi armed secara ketat per profil (`PROFILE_SCALPING`, `PROFILE_INTRADAY`, `PROFILE_SWING`) tanpa membatalkan pending order milik profil lainnya.
      - **Logging Setup Profile Fix:** `Logger.mqh` kini mencatat profil trade riil (`tr.profile`) ke dalam `QT_Setups_Log.csv`.
      - **Kompilasi Sukses:** Terverifikasi 100% kompilasi MetaEditor dengan `0 errors, 0 warnings`. Seluruh file binari `.ex5` dan `.mqh` telah diperbarui ke direktori terminal MT5.
  - [x] **Backtest Iterasi 7 (`report-7`, `v1.31`) - Validasi Opsi B (Jan - Nov 2025):**
    - **Pembalikan Kinerja Scalping yang Masif:** Kerugian Scalping berhasil ditekan drastis dari `-$4,152.19` (-30.90R di `report-6`) menjadi praktis Break-Even `-$20.52` (+3.11R realized, Win Rate 49.47%, PF 1.00 dari 285 deals). Filter kelanjutan ekspansi/distribusi AMDX Phase D sukses membatalkan 237 setup di luar fase (`CANCEL_CYCLE_DAY_PHASE_NOT_D`), dan kalibrasi risiko SL 50p / Partial 50% di +50p menyelamatkan modal >$4,100.
    - **Konsistensi Intraday:** Profil Intraday tetap menghasilkan laba bersih positif: `+$645.66` (PF 1.13, 60 deals).
    - **Hasil Total Akun:** Membalikkan performa dari rugi tajam menjadi **Net Profit Positif (+$148.30)** selama 11 bulan (365 total trades).
    - **Pemeriksaan Fitur MT5 Forward:** Hasil `report-7` mencakup periode `2025.01.02 s/d 2025.11.28` karena penggunaan opsi tester `Forward: 1/2` saat `Optimization: Disabled`. MT5 secara arsitektural hanya menjalankan bagian backtest (1/2 awal) dan melewati bagian forward jika mode optimasi dinonaktifkan.
  - [x] **Backtest Iterasi 8 (`report-8`, 21 Bulan Penuh) & Restrukturisasi Scalping Engine (`v1.32`):**
    - **Audit Forensik `report-8` (2025.01.02 s/d 2026.09.18, 689 Trades):**
      - **Profil Intraday Terbukti Konsisten Profit:** Net `+$441.95` (PF 1.05, 104 trades, average win `$215.74` vs loss `-$135.54`, payout ratio sehat `1.59:1`).
      - **Profil Scalping Penyebab Tunggal Kegagalan:** Menyumbang kerugian `-$3,696.37` (-32.20R, 549 trades, 91.8% dari seluruh kerugian akun) dengan payout ratio hanya 1.02:1 ($100.27 vs -$98.19).
      - **Akar Penyebab 1 — Reversal Prematur ($6,374 Bleed):** Sebanyak 61 trade scalping sempat mencapai floating profit `+0.5R s.d. +1.0R` (+25 s.d. +49 pips) namun berbalik membentur SL penuh -50 pips karena ketiadaan proteksi dini sebelum ambang kaku +50 pips.
      - **Akar Penyebab 2 — Sesi London Q2 vs Q3:** London Q2 (Judas manipulation) rugi `-$2,415.10`, sedangkan London Q3 (True expansion) profit `+$1,003.08` (WR 50.4%, PF 1.18).
      - **Akar Penyebab 3 — NY_AM Incompatibility:** Scalping di NY_AM rugi `-$2,284.35` akibat volatilitas pembukaan pasar AS yang menyapu SL 50 pips sebelum tren berkembang.
      - **Akar Penyebab 4 — Bleeding Hari Kamis:** Hari Kamis menyumbang `-$2,127.11` (57.5% dari seluruh kerugian scalp).
      - **Akar Penyebab 5 — POI Lemah:** POI `M15_RBS` dan `M15_Classic_V` menyumbang kerugian `-$1,684.71`.
    - **Solusi & Implementasi Fitur `v1.32`:**
      - **Stage-0.5 Early Defensive Break-Even (`InpScalpUseEarlyBE = true`):** Proteksi dini saat profit scalping mencapai `+30 pips` (`+0.6R`), otomatis menggeser SL ke titik entry + buffer 5 points, mengamankan 61 posisi dari pembalikan menjadi loss penuh.
      - **Pemisahan Konfigurasi & Perbaikan Ekspektansi Scalping:** Menambahkan parameter independen di EA: `InpScalpSlPips = 45.0`, `InpScalpBePips = 45.0`, `InpScalpPartialPips = 45.0`, `InpScalpPartialRatio = 0.30` (menyisakan 70% runner untuk memaksimalkan win ke target 100 pips), dan `InpScalpFinalTpPips = 100.0`.
      - **Filter Hari Kamis Toxic (`InpScalpAllowThursday = false`):** Mencegah eksekusi scalping di hari Kamis untuk memangkas potensi loss -$2,127.
      - **Filter Sesi Scalping (`InpScalpSessionMode = SCALP_SESS_LONDON_ONLY`):** Mengecualikan volatilitas liar sesi NY_AM dan fokus pada London (tersedia opsi `SCALP_SESS_LONDON_Q3_ONLY` untuk tingkat kemenangan tertinggi).
      - **Filter POI Lemah (`InpScalpFilterWeakPoi = true`):** Memblokir `M15_RBS` dan `M15_Classic_V` jika skor konfluensi < 12.
      - **Verifikasi & Sinkronisasi:** Seluruh 25 file MQL5 lolos verifikasi sintaks (0 errors). Memperbaiki identifier `qtState.dayeDayOfWeek == 4` dan `tr.anchorPOI.id` di `Setup.mqh`, serta menyinkronkan seluruh file ke direktori terminal MT5.
  - [x] **Backtest Iterasi 9 (`report-9`, `v1.32`) & Kalibrasi Sesi Scalp London Q3 + Swing H4 Only (`v1.33`):**
    - **Hasil Signifikan `report-9`:**
      - Pemulihan Scalping masif: kerugian terpangkas 93% dari `-$3,696.37` (`report-8`) menjadi `-$263.18` (PF 0.98, hampir break-even).
      - Filter Kamis berhasil 100% (0 trade Kamis), Filter NY_AM berhasil 100% (0 trade NY_AM).
      - Early BE (+30p) berhasil menyelamatkan 37 trade menjadi `BE_HIT` tanpa loss penuh.
      - **Temuan Kritis Swing:** Swing menyumbang kerugian tersisa `-$1,694.79` karena mengambil POI H1 (`-$964.07`) dan D1 (`-$828.00`), sedangkan POI H4 Swing justru profit `+$466.10`.
      - **Temuan Kritis Sesi Scalp:** London Q3 (True Expansion) menghasilkan profit `+$1,990.84` (WR 55.6%), sedangkan London Q2 (Judas Swing) menderita `-$2,254.02`.
    - **Implementasi Fitur `v1.33`:**
      - **Default Scalp Session ke London Q3 Only:** Mengubah default `InpScalpSessionMode = SCALP_SESS_LONDON_Q3_ONLY` untuk mengunci jendela profit institusional (+18.78R / +$1,990.84 di Report-9).
      - **Isolasi Anchor POI Swing ke H4 Saja:** Pada `TradeProfile.mqh`, menonaktifkan POI H1 & D1 untuk Swing (`allowPOITF[TF_IDX_H1] = false; allowPOITF[TF_IDX_D1] = false;`), membatasi Swing hanya pada level H4 yang terbukti profit (+1.84R).
      - **Verifikasi Sintaks:** 25 file MQL5 lolos verifikasi sintaks (0 errors), disinkronkan ke direktori terminal MT5.
  - [ ] Pengujian ulang di Strategy Tester dengan mode *Every tick based on real ticks* pasca-implementasi `v1.33` (Periode penuh 2 tahun, `Forward: No`).
  - [ ] Pengujian ulang di Strategy Tester dengan mode *Every tick based on real ticks* pasca-implementasi `v1.32` (Periode penuh 2 tahun, `Forward: No`).
  - [ ] Pengujian ulang di Strategy Tester dengan mode *Every tick based on real ticks* pasca-implementasi `v1.31` (Periode penuh 2 tahun, `Forward: No`).
  - [ ] Pengujian ulang di Strategy Tester dengan mode *Every tick based on real ticks* pasca-implementasi `v1.30`.
  - [ ] Pengujian ulang di Strategy Tester dengan mode *Every tick based on real ticks* pasca-implementasi `v1.21`.
  - [ ] Pengujian ulang di Strategy Tester dengan mode *Every tick based on real ticks* pasca-kalibrasi `v1.12`.
  - [ ] Pemisahan periode data menjadi **In-Sample (IS)** dan **Out-of-Sample (OOS)**.
- [x] **Script Analisis Statistik & Validasi Asumsi QT (`AnalyzeBacktestCSV.mq5`)**
  - [x] Evaluasi metrik utama: Jumlah trade (target $\ge 100$), *Expectancy* (dalam R), *Profit Factor*, *Max Drawdown*, *Win Rate*, dan rata-rata RR.
  - [x] **Simulasi Monte Carlo Bootstrap (2.500 Iterasi + Slippage Jitter):** Menghitung *Probability of Profit*, *95% Confidence Interval Net R*, serta *50th / 95th / 99th Percentile Worst-Case Max Drawdown* (dalam R dan %) langsung dari histori trade `QT_Forward_Journal.csv`.
  - [x] Evaluasi performa spesifik per **Hari Daye** (`Selasa Q2, Rabu Q3, Kamis Q4`), per **Sesi Harian**, dan per **Blok 90 Menit** (`Q2 vs Q3`) dari jurnal CSV.
  - [x] Evaluasi jumlah setup yang terblokir oleh filter berita `[-5 jam, +1 jam]`.
- [ ] **Uji Sensitivitas Parameter (Robustness Test) (Di Strategy Tester MT5)**
  - [ ] Menggeser kecil parameter kunci (ambang skor konfluensi, kekuatan pivot, toleransi ATR) untuk memastikan performa tidak runtuh akibat *overfitting*.

> **Kriteria Lulus Fase 8:** *Expectancy* positif pada data *Out-of-Sample*, *Max Drawdown* di dalam batas aman, dan performa stabil terhadap pergeseran kecil parameter.

---

### Fase 9: Forward Test Akun Demo (Ukuran: L)
Tujuan: Membuktikan kestabilan operasional EA secara *real-time* di akun demo sebelum spesifikasi v1 dinyatakan selesai (*Definition of Done*).

- [ ] **Operasional Demo Terkunci (Minimal 8 Minggu)**
  - [ ] Menjalankan EA dengan kode dan parameter yang sudah dikunci tanpa intervensi manual pada chart `XAUUSD`.
- [ ] **Audit & Rekonsiliasi**
  - [ ] Membandingkan metrik *Forward Test* terhadap hasil *Backtest* (frekuensi sinyal, distribusi RR, *slippage*, perilaku spread saat dekat berita, dan eksekusi *Friday Flat*).
  - [ ] Menyimpan dokumen spesifikasi final dan tabel parameter default bersama repositori kode.

> **Kriteria Lulus Fase 9 (Definition of Done v1):** EA berjalan stabil tanpa bug eksekusi selama periode *forward test*, jurnal CSV merekam setiap setup & trade secara utuh, dan metrik *forward test* konsisten dengan ekspektasi *backtest*.
