# BootDeploy 2.0.0

Instal Windows **langsung ke SSD / HDD** lewat enclosure/adapter USB — tanpa flashdisk.
Image di-apply dengan DISM, bootloader dibuat dengan BCDBoot, lalu disk dipindah ke dalam
PC/laptop target dan first boot (OOBE) berjalan di hardware target.

> **Peringatan keras:** tool ini **menghapus SELURUH DATA** pada disk target yang dipilih.

## Fitur

- **Dua skema disk** — GPT/UEFI dan MBR/Legacy BIOS (+UEFI-CSM), dipilih dari UI.
- **Windows Edition selector** — daftar edition dibaca otomatis dari `install.wim` / `install.esd`.
- **Mode partisi** — Auto (Windows mengisi seluruh disk) atau Custom (tentukan ukuran partisi Windows + partisi DATA terpisah).
- **Opsi Windows 11** — bypass OOBE jaringan / jalur akun lokal.
- **Guard keamanan disk** — disk sistem otomatis dilindungi; identitas disk (serial + ukuran) diverifikasi ulang tepat sebelum penghapusan.
- **UI menyesuaikan layar** — ukuran window mengikuti work area, aman di layar 1366x768.
- **UI gelap modern (WPF)** dengan aksen cyan, font Segoe UI, dan log real-time (Cascadia Mono/Consolas).

## Instalasi

**Cara 1 — Installer (disarankan):**
1. Buka `installer/BootDeploy.iss` dengan [Inno Setup 6](https://jrsoftware.org/isinfo.php), lalu Compile (Ctrl+F9).
2. Jalankan `BootDeploy-2.0.0-Setup.exe` yang dihasilkan.
3. BootDeploy terpasang di Program Files dengan shortcut Start Menu (dan Desktop, opsional).

**Cara 2 — Portable:**
Jalankan `START-BootDeploy.cmd` langsung (otomatis meminta hak Administrator).

## Kebutuhan

- Windows 10 / 11 (x64) untuk menjalankan tool.
- **PowerShell 5.1** (sudah tersedia di Windows 10/11).
- **Hak Administrator** — launcher meminta elevasi otomatis.
- SSD/HDD target minimal **20 GB**, tersambung lewat USB/enclosure/adapter.
- File **ISO Windows** (Windows 10 atau 11).

## Cara pakai

1. Sambungkan disk target lewat enclosure/adapter USB.
2. Jalankan **`START-BootDeploy.cmd`**, lalu setujui prompt UAC.
3. Pilih file ISO Windows.
4. Pilih disk target (klik **REFRESH** kalau baru dicolok).
5. Pilih edition Windows.
6. Pilih skema partisi: **GPT** atau **MBR** (lihat tabel di bawah).
7. Pilih mode partisi: Auto atau Custom.
8. Klik **START** dan konfirmasi bahwa disk target sudah benar.
9. Tunggu sampai selesai — Apply-Image adalah tahap paling lama.
10. **Shutdown PC**, lepas disk dari enclosure, lalu pasang **secara internal** ke PC target.
11. Boot PC target dari disk tersebut. Windows menjalankan first boot/OOBE di hardware target.

## Skema partisi

| | GPT (UEFI) | MBR (Legacy BIOS) |
|---|---|---|
| Firmware PC target | UEFI (CSM off) | Legacy / CSM on |
| Partisi | EFI 260 MB (FAT32) + MSR 16 MB + NTFS Windows (+ DATA) | NTFS Windows (primary, **active**) (+ DATA) |
| Bootloader | `bcdboot /f UEFI` ke `EFI:\EFI\Microsoft\Boot\BCD` | `bcdboot /f BIOS` ke `Windows:\Boot\BCD` |
| Batas | sangat besar (GPT) | maks **2 TB** per partisi, maks 4 primary |

Belum yakin? PC keluaran 2013 ke atas hampir selalu UEFI, jadi pakai **GPT**.

## Catatan penting

- **Jangan boot Windows dari disk selama disk masih tersambung lewat USB.** Lepas dulu.
- Tool ini **bukan Windows To Go** — tidak ada `PortableOperatingSystem`, SAN policy, atau tweak USBSTOR. Disknya dipindah ke dalam PC, bukan dipakai portabel.
- Tidak ada `unattend.xml` permanen (sengaja dihindari agar specialize/OOBE tidak rusak di sebagian build).
- Karena memakai DISM Apply-Image langsung, compatibility check Windows Setup (TPM/CPU/RAM/Secure Boot) tidak dijalankan.

## Riwayat versi

- **2.0.0** — Rebrand dari SSDDeploy menjadi BootDeploy (dukungan SSD + HDD), redesign UI (tema gelap modern, aksen cyan, font Segoe UI), installer Inno Setup.
- **1.0.1** — Rilis awal sebagai SSDDeploy.
