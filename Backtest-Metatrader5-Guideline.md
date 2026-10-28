# Panduan Integrasi, Backtest, & Simulasi Monte Carlo EA QT-MSNR-ICT (MetaTrader 5)

Dokumen ini berisi panduan lengkap langkah demi langkah mulai dari persiapan awal di **MetaTrader 5 (MT5)**, menjalankan **EA QT-MSNR-ICT (`XAUUSD`)**, melakukan **Backtest & Stress Test**, hingga menjalankan **Simulasi Monte Carlo (2.500 Iterasi)** serta menghitung **Win Rate & Risk:Reward (RR)**.

---

## 1. Status Instalasi & File yang Sudah Terpasang Otomatis

Seluruh kode sumber (`.mqh` & `.mq5`) di dalam workspace `D:\Trading\Caesar Algorithm\MQL5\` telah dikompilasi menggunakan `metaeditor64.exe` (**0 Error, 0 Warning**) dan **sudah disalin otomatis** ke dalam Data Folder MetaTrader 5 Anda:

- **Lokasi Data Folder MT5 Anda:**
  `C:\Users\Farrel Caesarian\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\`
- **Lokasi Folder Jurnal CSV Bersama (`Common\Files`):**
  `C:\Users\Farrel Caesarian\AppData\Roaming\MetaQuotes\Terminal\Common\Files\`

Daftar file siap pakai di Navigator MT5 Anda:
1. **Expert Advisor:** `MQL5/Experts/QT_MSNR_EA.ex5`
2. **Custom Indicator (Fase 1 Visualizer):** `MQL5/Indicators/QT_Visualizer_Ind.ex5`
3. **Scripts:**
   - `ExportNewsCSV.ex5` — Mengekspor kalender berita High Impact MT5 ke `news_high_impact.csv`.
   - `AnalyzeBacktestCSV.ex5` — Menganalisis hasil backtest/forward test (`QT_Forward_Journal.csv`) + menjalankan **Simulasi Monte Carlo 2.500 Iterasi**.
   - `TestTimeEngine.ex5`, `TestSwings.ex5`, `TestMSNR.ex5`, `TestICT.ex5`, `TestSetupAndRisk.ex5`, `TestNews.ex5` — Unit test otomatis per modul.

---

## 2. Tabel Risk:Reward (RR) & Target Win Rate

Pada **EA QT-MSNR-ICT**, batas minimum **Risk:Reward (RR)** mengikuti **Trade Profile (`InpTradeProfile`)** yang Anda pilih, tetapi **dapat Anda ubah secara manual** melalui input **`InpCustomMinRR`**:

| Trade Profile (`InpTradeProfile`) | Default Minimum RR | Cara Mengubah ke `1:1.5` | Win Rate Titik Impas (*Break-Even Murni*) | Target Win Rate Sehat (Profit Konsisten) |
| :--- | :---: | :---: | :---: | :---: |
| **Scalping** (`PROFILE_SCALPING`) | **`1 : 1.5`** (`1.5R`) | Sudah `1.5` otomatis | **40.0%** | **48% – 55%+** |
| **Intraday** (`PROFILE_INTRADAY` - *Default*) | **`1 : 2.0`** (`2.0R`) | Ubah `InpCustomMinRR = 1.5` | **33.3%** (pada 1:2) / **40.0%** (pada 1:1.5) | **42% – 50%+** |
| **Swing** (`PROFILE_SWING`) | **`1 : 3.0`** (`3.0R`) | Ubah `InpCustomMinRR = 1.5` | **25.0%** | **35% – 45%+** |

### Bagaimana EA Menentukan TP, BE, dan Partial Close?
1. **Target TP Utama (`final_tp`):** Ditarik ke **Draw on Liquidity (DOL)** terdekat yang memenuhi syarat minimum RR (misalnya `PDH/PDL`, `PWH/PWL`, `Session High/Low`, `EQH/EQL`, atau level `MSNR` berlawanan yang masih *Fresh*).
2. **Break-Even Otomatis di +1R (`InpUseBreakEven1R = true`):** Saat harga sudah bergerak profit sejauh `+1.0R`, SL otomatis digeser ke harga Entry + buffer (`InpBeBufferPoints`).
3. **Partial Close 50% di TP1 (`InpUsePartialTP1 = true`):** Saat harga menyentuh likuiditas internal pertama (`TP1`), EA mengamankan `50%` volume posisi dan membiarkan `50%` sisanya berjalan menuju DOL utama.
   - Karena adanya fitur **BE +1R** dan **Partial TP1**, banyak posisi yang gagal mencapai TP akhir tidak berakhir `-1R`, melainkan tercatat sebagai **`BE_HIT` (`0R`)** atau **`TP1_THEN_BE` (`+0.5R`)** di jurnal!

---

## 3. Persiapan Awal di MetaTrader 5 (Pertama Kali Buka)

### Langkah 1: Login Akun Demo & Munculkan Simbol `XAUUSD`
1. Buka aplikasi **MetaTrader 5**.
2. Jika belum memiliki akun aktif, klik **File -> Open an Account**, cari nama broker Anda (atau pilih *MetaQuotes Ltd*), lalu pilih **Open a demo account** (pilih tipe akun **Hedging**, deposit misal `$10,000`).
3. Tekan **`Ctrl+M`** untuk menampilkan panel **Market Watch** di sebelah kiri.
4. Klik kanan di area Market Watch -> pilih **Symbols** (`Ctrl+U`):
   - Ketik **`XAUUSD`** di kolom pencarian.
   - Klik simbol **`XAUUSD`**, lalu klik tombol **Show Symbol** hingga ikon di sebelahnya berwarna emas, lalu klik **OK**.
5. Klik kanan pada **`XAUUSD`** di Market Watch -> pilih **Chart Window**, lalu ubah timeframe chart di toolbar atas menjadi **M5**.

---

### Langkah 2: Aktifkan Izin Algorithmic Trading & WebRequest Berita
1. Klik menu **Tools -> Options** (atau tekan **`Ctrl+O`**).
2. Buka tab **Expert Advisors**, lalu centang:
   - [x] **Allow Algorithmic Trading**
   - [x] **Allow WebRequest for listed URL**
3. Di tabel URL di bawahnya, klik tanda `+` (Add new URL) dan masukkan:
   ```text
   https://nfs.faireconomy.media
   ```
4. Klik **OK**.
5. Pastikan tombol **Algo Trading** di toolbar bagian atas MT5 berwarna **Hijau (Aktif)**.

---

### Langkah 3: Verifikasi Modul & Ekspor Berita Historis (`news_high_impact.csv`)
1. Tekan **`Ctrl+N`** untuk membuka panel **Navigator**.
2. Buka bagian **Scripts**, lalu tarik (*drag & drop*) **`ExportNewsCSV`** ke chart `XAUUSD` dan klik **OK**.
3. Lihat tab **Experts** di bagian bawah layar (`Ctrl+T`):
   - Pastikan muncul pesan sukses bahwa file `news_high_impact.csv` telah disimpan di folder `Common\Files`.
   - *(Opsional)* Anda juga bisa menarik script `TestTimeEngine`, `TestSwings`, `TestMSNR`, `TestICT`, `TestSetupAndRisk`, dan `TestNews` ke chart untuk melihat seluruh unit test lulus (`0 FAILED`) di tab **Experts**.

---

## 4. Cara Menjalankan EA Secara Live di Chart Demo (Signal-Only / Auto-Trade)

Jika Anda ingin memasang EA langsung di chart `XAUUSD` untuk berjalan *real-time* (Forward Test):
1. Buka chart **`XAUUSD`** timeframe **M5**.
2. Dari panel **Navigator -> Expert Advisors**, tarik **`QT_MSNR_EA`** ke atas chart `XAUUSD`.
3. Pada tab **Common**, pastikan **Allow Algorithmic Trading** dicentang.
4. Pada tab **Inputs**:
   - **`InpTradeProfile`**: Pilih `PROFILE_INTRADAY` (atau `PROFILE_SCALPING` / `PROFILE_SWING`).
   - **`InpSignalOnlyMode`**:
     - Pilih `true` jika hanya ingin melihat kotak visual, dashboard, dan menerima Alert tanpa membuka order (Fase 6).
     - Pilih `false` jika ingin EA membuka & mengelola posisi secara otomatis di akun Demo (Fase 7/9).
   - **`InpCustomMinRR`**: Isi `1.5` jika ingin memakai minimum RR `1:1.5`, atau biarkan `0.0` untuk memakai default profil (`1:2.0` untuk Intraday, `1:1.5` untuk Scalping).
5. Klik **OK**. Di pojok kiri atas chart akan muncul **Dashboard QT-MSNR-ICT** lengkap beserta garis True Opens (`00:00 NY`, `Mon 18:00 NY`, dst.) dan kotak sesi.

---

## 5. Cara Menjalankan Backtest di Strategy Tester MT5

1. Tekan **`Ctrl+R`** (atau klik **View -> Strategy Tester**) untuk membuka panel Strategy Tester di bagian bawah.
2. Pilih ikon **Single** (atau **Visualize** jika ingin menonton pergerakan harga dan penggambaran zona MSNR/FVG/QT secara visual).
3. Pada tab **Settings**, atur konfigurasi berikut:
   - **Expert:** `QT_MSNR_EA.ex5`
   - **Symbol:** `XAUUSD`
   - **Period:** `M5`
   - **Date:** Pilih *Custom period* (misalnya `2025.01.01` sampai tanggal hari ini).
   - **Forward:**
     - Pilih **No** untuk backtest penuh, atau
     - Pilih **1/2** atau **1/3** jika ingin MT5 membagi periode menjadi **In-Sample** dan **Out-of-Sample (Forward)** secara otomatis.
   - **Delays (Simulasi Kondisi Pasar & Slippage):**
     - Pilih **Random delay** untuk menguji ketahanan eksekusi terhadap latensi jaringan & slippage acak, atau *Zero latency* untuk eksekusi ideal.
   - **Modelling:** Pilih **Every tick based on real ticks** (sangat disarankan untuk akurasi *wick liquidity sweep* dan *spread* historis asli).
   - **Deposit:** `10000` (`USD`), **Leverage:** `1:100`.
4. Buka tab **Inputs** di Strategy Tester:
   - Ubah **`InpSignalOnlyMode`** menjadi **`false`** *(WAJIB `false` agar EA mengeksekusi transaksi saat backtest!)*.
   - Atur **`InpTradeProfile`** (`PROFILE_INTRADAY` atau `PROFILE_SCALPING`).
   - Atur **`InpCustomMinRR`**:
     - Isi **`1.5`** jika Anda ingin menguji performa dengan Risk:Reward minimum **1:1.5**.
     - Isi **`0.0`** jika ingin menggunakan RR bawaan profil (`1:2.0` untuk Intraday, `1:1.5` untuk Scalping).
   - *(Tips Kecepatan Backtest)*: Jika Anda menjalankan backtest *Non-Visual* selama bertahun-tahun dan ingin prosesnya jauh lebih cepat, Anda dapat mengubah **`InpEnableVisuals` = `false`** (pencatatan CSV tetap berjalan 100% meskipun visual dimatikan).
5. Klik tombol hijau **Start** di pojok kanan bawah!

> **Cek Penting di Tab Journal Saat Backtest Dimulai:**
> Lihat baris awal di tab **Journal** Strategy Tester: pastikan muncul pesan `[QT_MSNR_EA] PASS: Broker D1 open ... maps to 17:00 NY`. Jika broker Anda menggunakan zona waktu berbeda dari GMT+2/+3 (misal GMT+0), sesuaikan nilai `InpModeAServerToNY` (misal `-5`) hingga statusnya `PASS`.

---

## 6. Cara Menjalankan Simulasi Monte Carlo & Melihat Rekap Win Rate / TP / SL / BE

Setiap kali backtest (atau forward test) selesai, EA otomatis menyimpan seluruh rekaman transaksi ke dalam 3 file CSV di folder `Common\Files`:
- **`QT_Forward_Journal.csv`** — Rekap 1 baris per posisi yang sudah tutup (lengkap dengan status `TP_FULL`, `TP1_THEN_TP`, `TP1_THEN_BE`, `BE_HIT`, `SL_HIT`, `TIME_STOP`, `FRIDAY_FLAT`, profit `$` & `R`, waktu/sesi buka-tutup, serta `MFE` & `MAE`).
- **`QT_Trades_Log.csv`** — Log kronologis setiap event eksekusi.
- **`QT_Setups_Log.csv`** — Log seluruh setup yang terdeteksi beserta alasan penolakan (`REJECT_NEWS`, `REJECT_LOW_SCORE`, dll.).

### Langkah Menjalankan Analisis Statistik & Simulasi Monte Carlo:
1. Setelah backtest selesai, kembali ke jendela chart `XAUUSD` biasa di MT5.
2. Dari panel **Navigator -> Scripts**, tarik (*drag & drop*) script **`AnalyzeBacktestCSV`** ke atas chart `XAUUSD`.
3. Pada jendela Inputs script `AnalyzeBacktestCSV`:
   - `InpForwardJournalCsv`: `QT_Forward_Journal.csv`
   - `InpSetupsCsv`: `QT_Setups_Log.csv`
   - `InpReportTxt`: `QT_Forward_Evolution_Report.txt`
   - `InpMonteCarloRuns`: `2500` *(jumlah simulasi pengacakan urutan trade + slippage jitter)*
   - `InpRiskPctPerTrade`: `0.50` *(persentase risiko per 1R untuk menghitung persentase Drawdown Monte Carlo)*
4. Klik **OK**.
5. Buka tab **Experts** di bagian bawah (`Ctrl+T`) untuk langsung membaca laporannya, atau buka file **`QT_Forward_Evolution_Report.txt`** di dalam folder:
   `C:\Users\Farrel Caesarian\AppData\Roaming\MetaQuotes\Terminal\Common\Files\QT_Forward_Evolution_Report.txt`

---

## 7. Cara Membaca Laporan `QT_Forward_Evolution_Report.txt`

Laporan yang dihasilkan oleh `AnalyzeBacktestCSV` memiliki **7 Bagian Diagnostik Utama**:

1. **Setup Funnel & Pre-Trade Filter Rejections (`QT_Setups_Log.csv`):**
   - Menampilkan berapa total setup yang dievaluasi dan berapa yang diblokir oleh filter berita `[-5 jam, +1 jam]`, skor konfluensi rendah, RR di bawah minimum, atau SL terlalu lebar.
2. **Closed-Trade Outcome Distribution (Rekap TP / SL / BE):**
   - Merinci jumlah posisi yang berakhir di:
     - `TP_FULL` (kena TP penuh tanpa partial)
     - `TP1_THEN_TP` (kena Partial 50% di TP1 lalu sisa 50% kena TP penuh)
     - `TP1_THEN_BE` (kena Partial 50% di TP1 lalu sisa 50% kena Break-Even)
     - `BE_HIT` (kena Break-Even di +1R)
     - `SL_HIT` (kena Stop Loss penuh `-1R`)
     - `TIME_STOP` (ditutup otomatis karena batas waktu profil habis)
     - `FRIDAY_FLAT` (ditutup paksa Jumat `15:00 NY`)
3. **Overall Financial & R-Multiple Performance:**
   - Menampilkan **Total Trades**, **Win Rate (`WR: xx.x%`)**, **Net R (`+xx.xxR`)**, **Net Profit USD (`+$xxxx.xx`)**, **Expectancy per Trade (`+x.xxR`)**, **Profit Factor (`PF`)**, serta **Max Drawdown** historis.
4. **Monte Carlo Bootstrap Simulation (2.500 Iterasi + Slippage Jitter):**
   - Mengacak urutan trade sebanyak 2.500 kali dengan tambahan *execution/slippage jitter* acak (`[-0.05R .. +0.02R]` per trade) untuk menguji skenario terburuk (*bad luck streak*):
     - **Probability of Profit (%):** Peluang sistem tetap profit.
     - **Net Profit 5%..95% Confidence Interval:** Rentang ekspektasi total R dari skenario pesimis (persentil ke-5) hingga optimis (persentil ke-95).
     - **50th / 95th / 99th Percentile Worst-Case Max Drawdown:** Estimasi drawdown maksimum pada kondisi normal (50%), konservatif (95%), dan ekstrim (99%) dalam satuan `R` maupun `%` saldo akun.
5. **Algorithm Evolution Telemetry (MFE / MAE / POI Diagnostics):**
   - **Avg MFE (`+x.xxR`):** Rata-rata profit floating tertinggi yang dicapai posisi sebelum tutup (untuk mengevaluasi apakah target TP bisa diperbesar).
   - **Avg MAE on Winners (`-x.xxR`):** Rata-rata drawdown floating pada posisi yang akhirnya menang (untuk mengevaluasi apakah SL terlalu sempit/lebar).
   - **SL Hits after >= +0.8R:** Jumlah posisi yang akhirnya kena SL padahal sempat profit `>= +0.8R` (indikator apakah trigger Break-Even perlu dimajukan ke `+0.8R`).
   - **Perbandingan Performa `M15/M5 Refined` vs `HTF Only`:** Mengukur apakah konfirmasi POI M15/M5 meningkatkan Win Rate & Expectancy.
6. **Tabel Performa per Hari Daye (`Mon Q1` s/d `Fri Q0`) & Sesi Harian (`Asia Q1`, `London Q2`, `NY_AM Q3`, `NY_PM Q4`).**
7. **Tabel Performa per Siklus 90 Menit (`Q1`, `Q2`, `Q3`, `Q4`).**

---

> **Tips Sebelum Memulai Backtest Baru:**
> Jika Anda ingin memulai pengujian baru dari nol agar file jurnal tidak bercampur dengan hasil backtest sebelumnya, cukup hapus atau pindahkan file `QT_Forward_Journal.csv`, `QT_Trades_Log.csv`, dan `QT_Setups_Log.csv` di dalam folder `C:\Users\Farrel Caesarian\AppData\Roaming\MetaQuotes\Terminal\Common\Files\` sebelum menekan tombol **Start** di Strategy Tester.
