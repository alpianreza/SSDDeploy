# SSDDeploy 1.0.0

Instal Windows **langsung ke SSD** lewat enclosure/adapter USB — tanpa flashdisk.
Image di-apply dengan DISM, bootloader dibuat dengan BCDBoot, lalu SSD dipindah ke dalam
PC/laptop target dan first boot (OOBE) berjalan di hardware target.

> **Peringatan keras:** tool ini **menghapus SELURUH DATA** pada disk target yang dipilih.

## Fitur

- **Dua skema disk** — GPT/UEFI dan MBR/Legacy BIOS (+UEFI-CSM), dipilih dari UI.
- **Windows Edition selector** — daftar edition dibaca otomatis dari `install.wim` / `install.esd`.
- **Mode partisi** — Auto (Windows mengisi seluruh SSD) atau Custom (tentukan ukuran partisi Windows + partisi DATA terpisah).
- **Opsi Windows 11** — bypass OOBE jaringan / jalur akun lokal.
- **Guard keamanan disk** — disk sistem otomatis dilindungi; identitas disk (serial + ukuran) diverifikasi ulang tepat sebelum penghapusan.
- **UI menyesuaikan layar** — ukuran window mengikuti work area, aman di layar 1366x768.
- **UI gelap (WPF)** dengan progress bar dan log real-time.

## Kebutuhan

- Windows 10 / 11 (x64) untuk menjalankan tool.
- **PowerShell 5.1** (sudah tersedia di Windows 10/11).
- **Hak Administrator** — launcher meminta elevasi otomatis.
- SSD/HDD target minimal **20 GB**, tersambung lewat USB/enclosure/adapter.
- File **ISO Windows** (Windows 10 atau 11).

## Cara pakai

1. Sambungkan SSD target lewat enclosure/adapter USB.
2. Jalankan **`START-SSDDeploy.cmd`**, lalu setujui prompt UAC.
3. Pilih file ISO Windows.
4. Pilih SSD target (klik **REFRESH** kalau baru dicolok).
5. Pilih edition Windows.
6. Pilih skema partisi: **GPT** atau **MBR** (lihat tabel di bawah).
7. Pilih mode partisi: Auto atau Custom.
8. Klik **START** dan konfirmasi bahwa disk target sudah benar.
9. Tunggu sampai selesai — Apply-Image adalah tahap paling lama.
10. **Shutdown PC**, lepas SSD dari enclosure, lalu pasang SSD **secara internal** ke PC target.
11. Boot PC target dari SSD tersebut. Windows menjalankan first boot/OOBE di hardware target.

## Skema partisi

| | GPT (UEFI) | MBR (Legacy BIOS) |
|---|---|---|
| Firmware PC target | UEFI (CSM off) | Legacy / CSM on |
| Partisi | EFI 260 MB (FAT32) + MSR 16 MB + NTFS Windows (+ DATA) | NTFS Windows (primary, **active**) (+ DATA) |
| Bootloader | `bcdboot /f UEFI` ke `EFI:\EFI\Microsoft\Boot\BCD` | `bcdboot /f BIOS` ke `Windows:\Boot\BCD` |
| Batas | sangat besar (GPT) | maks **2 TB** per partisi, maks 4 primary |

Belum yakin? PC keluaran 2013 ke atas hampir selalu UEFI, jadi pakai **GPT**.

## Catatan penting

- **Jangan boot Windows dari SSD selama SSD masih tersambung lewat USB.** Lepas dulu.
- Tool ini **bukan Windows To Go** — tidak ada `PortableOperatingSystem`, SAN policy, atau tweak USBSTOR. SSD-nya dipindah ke dalam PC, bukan dipakai portabel.
- Tidak ada `unattend.xml` permanen (sengaja dihindari agar specialize/OOBE tidak rusak di sebagian build).
- Karena memakai DISM Apply-Image langsung, compatibility check Windows Setup (TPM/CPU/RAM/Secure Boot) tidak dijalankan.
- Bypass akun lokal bergantung pada build Windows dan bisa berubah pada build terbaru.

## Struktur berkas

```
SSDDeploy.ps1          skrip utama (WPF GUI)
START-SSDDeploy.cmd    launcher: elevasi ke Administrator lalu menjalankan skrip
README.md              dokumen ini
```

## Troubleshooting

| Gejala | Sebab / solusi |
|---|---|
| SSD tidak muncul di daftar disk | Klik **REFRESH**. Pastikan SSD `Online` dan kapasitas >= 20 GB. |
| `Disk sistem tidak dapat dideteksi` | PC gagal memetakan drive sistem; operasi dibatalkan sebagai pengaman. |
| `Disk N sekarang bukan disk yang dipilih` | Daftar disk berubah (perangkat USB dicabut/dicolok). REFRESH lalu pilih ulang. |
| `Ukuran Disk N berubah` | Sama seperti di atas — REFRESH lalu pilih ulang. |
| MBR: `hanya mendukung partisi sampai 2 TB` | Perkecil partisi Windows, atau pindah ke GPT. |
| `Offline SOFTWARE registry hive tidak ditemukan` | ISO/edition tidak cocok atau image belum ter-apply sempurna. |
| SSD terisi tapi tidak boot di PC target | Firmware PC target harus cocok dengan skema: UEFI untuk GPT, Legacy/CSM untuk MBR. |

## Changelog

### 1.0.0
- Rilis pertama dengan nama SSDDeploy.
- Pemilih skema partisi GPT (UEFI) / MBR (Legacy BIOS), saling terikat seperti Rufus.
- Jalur MBR lengkap: partisi primary aktif, `bcdboot /f BIOS`, BCD di `\Boot\BCD`.
- Guard keamanan: disk sistem tak terdeteksi membatalkan operasi; identitas disk (serial + ukuran) diverifikasi ulang sebelum penghapusan.
- Pilihan disk dipertahankan saat REFRESH; polling mount ISO; path image tidak tersisa setelah ISO di-dismount.
- Window menyesuaikan work area (aman di 1366x768) dan tidak menutupi taskbar.

## Lisensi

Belum ditentukan. Tetapkan sebelum publikasi (mis. MIT, GPL-3.0, atau lainnya).

## Kredit

Dibuat dengan ❤️ oleh REZA.