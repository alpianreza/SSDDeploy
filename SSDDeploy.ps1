#Requires -Version 5.1
# SSDDeploy 1.0.0
# Install Windows directly to an external SSD using DISM + BCDBoot.
# IMPORTANT: This tool ERASES the selected target disk.

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

$ErrorActionPreference = "Stop"
$script:MountedIso = $null
$script:SelectedIso = $null
$script:SelectedDisk = $null
$script:EditionIndex = $null

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    [System.Windows.MessageBox]::Show(
        "Tool harus dijalankan sebagai Administrator.`nKlik kanan launcher dan pilih Run as administrator.",
        "SSDDeploy",
        "OK",
        "Warning"
    ) | Out-Null
    exit
}

function Get-SystemDiskNumber {
    try {
        $sys = Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop | Get-Disk -ErrorAction Stop
        return [int]$sys.Number
    } catch {
        return -1
    }
}

function Get-ExternalCandidateDisks {
    $systemDisk = Get-SystemDiskNumber
    Get-Disk | Where-Object {
        $_.Number -ne $systemDisk -and
        $_.OperationalStatus -eq "Online" -and
        $_.Size -ge 20GB
    } | Sort-Object Number
}

function Format-Bytes([double]$bytes) {
    if ($bytes -ge 1TB) { return "{0:N2} TB" -f ($bytes/1TB) }
    elseif ($bytes -ge 1GB) { return "{0:N1} GB" -f ($bytes/1GB) }
    else { return "{0:N0} MB" -f ($bytes/1MB) }
}

function Refresh-Disks {
    $previousNumber = $null
    if ($cmbDisk.SelectedItem) { $previousNumber = [int]$cmbDisk.SelectedItem.Number }

    $cmbDisk.Items.Clear()
    $systemDisk = Get-SystemDiskNumber
    foreach ($d in Get-ExternalCandidateDisks) {
        $bus = $d.BusType
        $label = "Disk $($d.Number) | $($d.FriendlyName) | $(Format-Bytes $d.Size) | $bus"
        $item = [PSCustomObject]@{
            Label = $label
            Number = [int]$d.Number
            Size = [int64]$d.Size
            FriendlyName = $d.FriendlyName
            BusType = "$bus"
            SerialNumber = "$($d.SerialNumber)"
        }
        [void]$cmbDisk.Items.Add($item)
    }
    $cmbDisk.DisplayMemberPath = "Label"

    # Keep the user's previous choice instead of silently jumping back to index 0.
    if ($cmbDisk.Items.Count -gt 0) {
        $index = 0
        if ($previousNumber -ne $null) {
            for ($i = 0; $i -lt $cmbDisk.Items.Count; $i++) {
                if ([int]$cmbDisk.Items[$i].Number -eq $previousNumber) { $index = $i; break }
            }
        }
        $cmbDisk.SelectedIndex = $index
    }

    if ($systemDisk -lt 0) {
        $lblSystemDisk.Text = "WARNING: disk sistem tidak terdeteksi - periksa target dengan teliti"
    }
    else {
        $lblSystemDisk.Text = "Protected system disk: Disk $systemDisk"
    }
}

function Dismount-IsoSafe {
    if ($script:MountedIso) {
        try { Dismount-DiskImage -ImagePath $script:MountedIso -ErrorAction SilentlyContinue | Out-Null } catch {}
        $script:MountedIso = $null
    }
    # Never keep a stale wim/esd path: after the ISO is gone that drive letter
    # can be reused by another volume, so the old path becomes meaningless.
    $script:WimPath = $null
}

function Get-WimPathFromMountedIso([string]$isoPath) {
    Dismount-IsoSafe
    Mount-DiskImage -ImagePath $isoPath -PassThru | Out-Null

    # The mounted volume is not always ready immediately, especially with large
    # ISOs or slow machines, so poll instead of relying on one fixed delay.
    $drive = $null
    for ($i = 0; $i -lt 30 -and -not $drive; $i++) {
        Start-Sleep -Milliseconds 500
        $vol = Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue
        $drive = ($vol | Where-Object DriveLetter | Select-Object -First 1).DriveLetter
    }
    if (-not $drive) { throw "Drive letter ISO tidak ditemukan." }

    $script:MountedIso = $isoPath
    $installWim = "${drive}:\sources\install.wim"
    $installEsd = "${drive}:\sources\install.esd"

    if (Test-Path $installWim) { return $installWim }
    if (Test-Path $installEsd) { return $installEsd }

    throw "install.wim / install.esd tidak ditemukan di ISO."
}

function Load-Editions {
    $cmbEdition.Items.Clear()
    if (-not $script:SelectedIso) { return }

    try {
        $wim = Get-WimPathFromMountedIso $script:SelectedIso
        $script:WimPath = $wim
        $images = Get-WindowsImage -ImagePath $wim
        foreach ($img in $images) {
            $obj = [PSCustomObject]@{
                Label = "Index $($img.ImageIndex) - $($img.ImageName)"
                Index = [int]$img.ImageIndex
                Name  = $img.ImageName
            }
            [void]$cmbEdition.Items.Add($obj)
        }
        $cmbEdition.DisplayMemberPath = "Label"
        if ($cmbEdition.Items.Count -gt 0) { $cmbEdition.SelectedIndex = 0 }
        $lblStatus.Text = "ISO loaded. Pilih edition Windows (Home / Pro / lainnya)."
        Write-Log "Edition tersedia: $($cmbEdition.Items.Count)"
    } catch {
        Dismount-IsoSafe
        [System.Windows.MessageBox]::Show($_.Exception.Message,"ISO Error","OK","Error") | Out-Null
        $lblStatus.Text = "Gagal membaca ISO."
    }
}

function Write-Log([string]$text) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $txtLog.AppendText("[$timestamp] $text`r`n")
    $txtLog.ScrollToEnd()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Progress([int]$value, [string]$status) {
    $pb.Value = [Math]::Max(0,[Math]::Min(100,$value))
    $lblStatus.Text = $status
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-FreeDriveLetter {
    $used = (Get-Volume | Where-Object DriveLetter).DriveLetter
    foreach ($c in [char[]]"STUVWXYZ") {
        if ($used -notcontains "$c") { return "$c" }
    }
    throw "Tidak ada drive letter kosong."
}

function Confirm-DestructiveAction($diskObj, $editionObj) {
    $schemeText = "GPT (UEFI)"
    if ($cmbScheme.SelectedIndex -eq 1) { $schemeText = "MBR (Legacy BIOS)" }
    $targetText = "UEFI (non CSM)"
    if ($cmbTarget.SelectedIndex -eq 1) { $targetText = "BIOS (or UEFI-CSM)" }

    $msg = @"
PERINGATAN: SEMUA DATA PADA TARGET DISK AKAN DIHAPUS!

Target:
Disk $($diskObj.Number)
$($diskObj.FriendlyName)
$(Format-Bytes $diskObj.Size)
Bus: $($diskObj.BusType)
Serial: $($diskObj.SerialNumber)

Windows:
$($editionObj.Name)

Partition scheme: $schemeText
Target system: $targetText

Pastikan ini benar-benar SSD external yang ingin dipakai.
"@
    $res = [System.Windows.MessageBox]::Show(
        $msg,
        "KONFIRMASI FORMAT DISK",
        "YesNo",
        "Warning"
    )
    return ($res -eq "Yes")
}


function Set-OfflineRegistryBypasses([string]$WindowsDrive, [bool]$HardwareBypass, [bool]$OnlineBypass) {
    # Direct DISM Apply-Image does not run Windows Setup compatibility checks,
    # so TPM/CPU/Secure Boot setup checks are already effectively skipped.
    if ($HardwareBypass) {
        Write-Log "Direct Apply mode: Windows Setup hardware checks are not invoked."
    }

    if (-not $OnlineBypass) { return }

    $softwareHive = Join-Path $WindowsDrive "Windows\System32\Config\SOFTWARE"
    if (-not (Test-Path $softwareHive)) {
        throw "Offline SOFTWARE registry hive tidak ditemukan."
    }

    $mount = "SSDDEPLOY_SOFTWARE"
    # Do NOT add 2>$null on this reg.exe line: with $ErrorActionPreference='Stop'
    # a redirected native stderr becomes a terminating error, and this pre-cleanup
    # unload normally fails because the hive is not loaded yet. Keep it non-fatal.
    & reg.exe unload "HKLM\$mount" | Out-Null

    $p = Start-Process -FilePath "reg.exe" `
        -ArgumentList @("load","HKLM\$mount",$softwareHive) `
        -Wait -NoNewWindow -PassThru

    if ($p.ExitCode -ne 0) {
        throw "Gagal me-load offline SOFTWARE registry."
    }

    try {
        $oobe = "Registry::HKEY_LOCAL_MACHINE\$mount\Microsoft\Windows\CurrentVersion\OOBE"
        if (-not (Test-Path $oobe)) {
            New-Item -Path $oobe -Force | Out-Null
        }

        New-ItemProperty -Path $oobe `
            -Name "BypassNRO" `
            -PropertyType DWord `
            -Value 1 `
            -Force | Out-Null

        Write-Log "BypassNRO = 1 diterapkan ke offline SOFTWARE hive."
    }
    finally {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 250
        & reg.exe unload "HKLM\$mount" | Out-Null
    }
}

function Write-OobeUnattend([string]$WindowsDrive, [bool]$OnlineBypass) {
    # Intentionally no persistent unattend.xml.
    # Persistent Panther unattend can break specialize/OOBE on some builds.
    if ($OnlineBypass) {
        Write-Log "Online setup bypass prepared without persistent unattend.xml."
    }
}

function Prepare-SSDForPC {
    $diskObj = $cmbDisk.SelectedItem
    $editionObj = $cmbEdition.SelectedItem

    if (-not $script:SelectedIso) { throw "Pilih file ISO Windows terlebih dahulu." }
    if (-not $diskObj) { throw "Pilih SSD target." }
    if (-not $editionObj) { throw "Pilih edition Windows." }

    $systemDisk = Get-SystemDiskNumber
    if ($systemDisk -lt 0) {
        throw "Disk sistem tidak dapat dideteksi. Operasi dibatalkan demi keamanan."
    }
    if ([int]$diskObj.Number -eq $systemDisk) {
        throw "Disk sistem utama terdeteksi sebagai target. Operasi dibatalkan."
    }

    $targetDisk = Get-Disk -Number ([int]$diskObj.Number)
    if ($targetDisk.IsBoot -or $targetDisk.IsSystem) {
        throw "Target adalah boot/system disk. Operasi dibatalkan."
    }

    # The disk list is only a snapshot: disk numbers can be reassigned when USB
    # devices are added or removed after the last REFRESH. Re-verify the identity
    # of the disk that is about to be erased so a stale number cannot hit
    # a different device.
    if ($diskObj.SerialNumber -and "$($targetDisk.SerialNumber)" -and
        $diskObj.SerialNumber -ne "$($targetDisk.SerialNumber)") {
        throw "Disk $($diskObj.Number) sekarang bukan disk yang dipilih ($($diskObj.FriendlyName)). Klik REFRESH lalu pilih ulang."
    }
    if ([int64]$targetDisk.Size -ne [int64]$diskObj.Size) {
        throw "Ukuran Disk $($diskObj.Number) berubah sejak REFRESH terakhir. Klik REFRESH lalu pilih ulang."
    }

    if (-not (Confirm-DestructiveAction $diskObj $editionObj)) {
        Write-Log "Dibatalkan pengguna."
        return
    }

    $btnInstall.IsEnabled = $false
    $btnBrowse.IsEnabled = $false
    $btnRefresh.IsEnabled = $false

    $script:CurrentStage = "Validating"
    try {
        Set-Progress 3 "Validating..."
        Write-Log "Memulai proses."
        Write-Log "ISO: $script:SelectedIso"
        Write-Log "Target: Disk $($diskObj.Number) - $($diskObj.FriendlyName)"
        Write-Log "Edition: $($editionObj.Name)"
        if ($rbCustomPartition.IsChecked) {
            Write-Log "Partition mode: Custom | Windows=$($txtWindowsSizeGB.Text) GB | Data=$($txtDataLabel.Text)"
        } else {
            Write-Log "Partition mode: Auto"
        }
        Write-Log "Bypass hardware check: $([bool]$chkBypassHardware.IsChecked)"
        Write-Log "Bypass online setup: $([bool]$chkBypassOnline.IsChecked)"

        # GPT is deployed as EFI system, MBR as active primary + legacy boot sector.
        $useMbr = ($cmbScheme.SelectedIndex -eq 1)
        if ($useMbr) {
            Write-Log "Partition scheme: MBR (Legacy BIOS) | Target system: BIOS (or UEFI-CSM)"
        } else {
            Write-Log "Partition scheme: GPT (UEFI) | Target system: UEFI (non CSM)"
        }

        if (-not $script:MountedIso) {
            $script:WimPath = Get-WimPathFromMountedIso $script:SelectedIso
        }

        $script:CurrentStage = "Preparing target disk"
        Set-Progress 8 "Preparing target disk..."
        Write-Log "Membersihkan Disk $($diskObj.Number)..."

        $disk = Get-Disk -Number ([int]$diskObj.Number)
        if ($disk.IsOffline) { Set-Disk -Number $disk.Number -IsOffline $false }
        if ($disk.IsReadOnly) { Set-Disk -Number $disk.Number -IsReadOnly $false }

        Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false

        $customPartition = [bool]$rbCustomPartition.IsChecked
        $dataPartition = $null
        $efi = $null

        if ($useMbr) {
            Initialize-Disk -Number $disk.Number -PartitionStyle MBR
            Write-Log "MBR mode: tanpa EFI System Partition dan tanpa MSR."
        }
        else {
            Initialize-Disk -Number $disk.Number -PartitionStyle GPT

            Set-Progress 15 "Creating EFI partition..."
            Write-Log "Membuat EFI System Partition 260 MB..."
            $efi = New-Partition -DiskNumber $disk.Number -Size 260MB -GptType "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}" -AssignDriveLetter
            Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel "SYSTEM" -Confirm:$false | Out-Null

            Set-Progress 20 "Creating MSR partition..."
            Write-Log "Membuat Microsoft Reserved Partition 16 MB..."
            New-Partition -DiskNumber $disk.Number -Size 16MB -GptType "{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}" | Out-Null
        }

        Set-Progress 25 "Creating Windows partition..."

        if ($customPartition) {
            $windowsSizeText = $txtWindowsSizeGB.Text.Trim()
            [double]$windowsSizeGB = 0

            if (-not [double]::TryParse($windowsSizeText, [ref]$windowsSizeGB)) {
                throw "Ukuran partisi Windows tidak valid."
            }

            if ($windowsSizeGB -lt 64) {
                throw "Ukuran partisi Windows minimal 64 GB."
            }

            $requiredBytes = [int64]($windowsSizeGB * 1GB)
            $availableBytes = (Get-Disk -Number $disk.Number).LargestFreeExtent

            if ($requiredBytes + 2GB -gt $availableBytes) {
                throw "Ukuran Windows terlalu besar untuk SSD target. Sisakan ruang untuk partisi DATA."
            }

            # MBR cannot address a single partition larger than 2 TB.
            if ($useMbr -and $requiredBytes -gt 2TB) {
                throw "MBR hanya mendukung partisi sampai 2 TB. Perkecil ukuran partisi Windows atau gunakan GPT."
            }

            Write-Log "Membuat Windows partition $windowsSizeGB GB..."
            if ($useMbr) {
                $win = New-Partition -DiskNumber $disk.Number -Size $requiredBytes -MbrType IFS -AssignDriveLetter
            }
            else {
                $win = New-Partition -DiskNumber $disk.Number -Size $requiredBytes -GptType "{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}" -AssignDriveLetter
            }
            Format-Volume -Partition $win -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-Null

            $dataLabel = $txtDataLabel.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($dataLabel)) { $dataLabel = "DATA" }
            if ($dataLabel.Length -gt 32) { $dataLabel = $dataLabel.Substring(0,32) }

            $remaining = (Get-Disk -Number $disk.Number).LargestFreeExtent
            if ($remaining -ge 1GB) {
                # MBR cannot address a single partition larger than 2 TB.
                if ($useMbr -and $remaining -gt 2TB) {
                    throw "Sisa ruang melebihi 2 TB; MBR tidak dapat mengalamati partisi DATA sebesar itu. Perkecil ukuran partisi Windows."
                }

                Write-Log "Membuat DATA partition dari sisa SSD..."
                if ($useMbr) {
                    $dataPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -MbrType IFS -AssignDriveLetter
                }
                else {
                    $dataPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType "{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}" -AssignDriveLetter
                }
                Format-Volume -Partition $dataPartition -FileSystem NTFS -NewFileSystemLabel $dataLabel -Confirm:$false | Out-Null
            }
        }
        else {
            Write-Log "Auto Partition: Windows menggunakan seluruh sisa SSD..."
            $win = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType "{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}" -AssignDriveLetter
            Format-Volume -Partition $win -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-Null
        }

        $winLetter = ($win | Get-Volume).DriveLetter

        if (-not $winLetter) {
            throw "Drive letter partisi target gagal dibuat."
        }

        if ($useMbr) {
            # MBR has no EFI System Partition. The Windows volume is itself the
            # system partition, so it must be flagged active for the legacy boot sector.
            Set-Partition -DiskNumber $disk.Number -PartitionNumber $win.PartitionNumber -IsActive $true
            Write-Log "MBR active partition set: Windows (partition $($win.PartitionNumber))."
        }
        else {
            $efiLetter = ($efi | Get-Volume).DriveLetter

            if (-not $efiLetter) {
                throw "Drive letter partisi EFI gagal dibuat."
            }

            $efiCheck = Get-Partition -DiskNumber $disk.Number -PartitionNumber $efi.PartitionNumber
            if ($efiCheck.GptType.ToString().ToLower() -ne "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}") {
                throw "EFI partition GPT type tidak valid: $($efiCheck.GptType)"
            }
            Write-Log "EFI GPT Type verified: $($efiCheck.GptType)"
        }

        $script:CurrentStage = "Applying Windows image"
        Set-Progress 30 "Applying Windows image..."
        Write-Log "Apply image ke ${winLetter}: ... proses ini bisa lama."

        $applyArgs = @(
            "/Apply-Image",
            "/ImageFile:$($script:WimPath)",
            "/Index:$($editionObj.Index)",
            "/ApplyDir:${winLetter}:\"
        )

        $p = Start-Process -FilePath "dism.exe" -ArgumentList $applyArgs -NoNewWindow -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            throw "DISM gagal. Exit code: $($p.ExitCode)"
        }

        $script:CurrentStage = "Applying bypass options"
        Set-Progress 78 "Applying Windows bypass options..."
        $hardwareBypass = [bool]$chkBypassHardware.IsChecked
        $onlineBypass = [bool]$chkBypassOnline.IsChecked

        if ($hardwareBypass -or $onlineBypass) {
            Set-OfflineRegistryBypasses "${winLetter}:" $hardwareBypass $onlineBypass
            Write-OobeUnattend "${winLetter}:" $onlineBypass
        }

        $script:CurrentStage = "Creating boot files"
        Set-Progress 82 "Creating boot files..."

        if ($useMbr) {
            Write-Log "Membuat legacy (MBR/BIOS) bootloader..."
            $bcd = Start-Process -FilePath "bcdboot.exe" `
                -ArgumentList @("${winLetter}:\Windows","/s","${winLetter}:","/f","BIOS") `
                -NoNewWindow -Wait -PassThru
            $bcdStore = "${winLetter}:\Boot\BCD"
        }
        else {
            Write-Log "Membuat UEFI bootloader..."
            $bcd = Start-Process -FilePath "bcdboot.exe" `
                -ArgumentList @("${winLetter}:\Windows","/s","${efiLetter}:","/f","UEFI") `
                -NoNewWindow -Wait -PassThru
            $bcdStore = "${efiLetter}:\EFI\Microsoft\Boot\BCD"
        }

        if ($bcd.ExitCode -ne 0) {
            throw "BCDBoot gagal. Exit code: $($bcd.ExitCode)"
        }

        if (-not (Test-Path $bcdStore)) {
            throw "BCD store tidak ditemukan setelah BCDBoot: $bcdStore"
        }
        Write-Log "BCD store verified: $bcdStore"

        $script:CurrentStage = "Final boot preparation"
        Set-Progress 90 "Final boot preparation..."

        # Remove stale unattend files created by older SSDDeploy builds.
        foreach ($uf in @(
            "${winLetter}:\Windows\Panther\unattend.xml",
            "${winLetter}:\Windows\Panther\Unattend\unattend.xml"
        )) {
            if (Test-Path $uf) {
                Remove-Item $uf -Force -ErrorAction SilentlyContinue
                Write-Log "Menghapus stale unattend: $uf"
            }
        }

        $script:CurrentStage = "Finalizing"

        if (-not $useMbr) {
            try {
                $efiPartition = Get-Partition -DiskNumber $disk.Number -PartitionNumber $efi.PartitionNumber
                if ($efiPartition.DriveLetter) {
                    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $efi.PartitionNumber -AccessPath "$($efiPartition.DriveLetter):\" -ErrorAction Stop
                    Write-Log "EFI drive letter removed."
                }
            }
            catch {
                Write-Log "WARNING: EFI drive letter cleanup gagal: $($_.Exception.Message)"
            }
        }

        Set-Progress 97 "Finalizing..."
        Write-Log "Sinkronisasi disk..."
        Start-Sleep -Seconds 2

        Dismount-IsoSafe

        Set-Progress 100 "DONE - Windows berhasil dipasang ke SSD."
        Write-Log "SELESAI."
        Write-Log "SELANJUTNYA: Shutdown PC, lepas SSD dari enclosure USB, lalu pasang SSD ke PC/laptop target."
        Write-Log "Boot PC target dari SSD tersebut. Windows akan menjalankan first boot/OOBE di hardware target."

        [System.Windows.MessageBox]::Show(
            "SSD berhasil dipersiapkan.`n`nShutdown PC, lepas SSD dari enclosure USB, pasang ke PC target, lalu boot dari SSD tersebut.",
            "SSDDeploy - DONE",
            "OK",
            "Information"
        ) | Out-Null
    }
    catch {
        Write-Log "ERROR [$script:CurrentStage]: $($_.Exception.Message)"
        Set-Progress 0 "ERROR"
        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            "SSDDeploy - ERROR",
            "OK",
            "Error"
        ) | Out-Null
    }
    finally {
        Dismount-IsoSafe
        $btnInstall.IsEnabled = $true
        $btnBrowse.IsEnabled = $true
        $btnRefresh.IsEnabled = $true
        Refresh-Disks
    }
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SSDDeploy 1.0.0"
        Height="700" Width="980"
        MinHeight="520" MinWidth="860"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        Background="#08111F"
        Foreground="#F4F8FF">
    <Window.Resources>
        <SolidColorBrush x:Key="CardBrush" Color="#101C31"/>
        <SolidColorBrush x:Key="CardBorder" Color="#1C3151"/>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#2388FF"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Height" Value="40"/>
            <Setter Property="Margin" Value="0"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#0C1729"/>
            <Setter Property="Foreground" Value="#EAF2FF"/>
            <Setter Property="BorderBrush" Value="#284365"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
        </Style>
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource CardBorder}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="14"/>
            <Setter Property="Padding" Value="18"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#0C1729" BorderBrush="#1B3151" BorderThickness="0,0,0,1" Padding="26,20">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="SSD" FontSize="30" FontWeight="Bold"/>
                        <TextBlock Text="Deploy" FontSize="30" FontWeight="Bold" Foreground="#45A3FF"/>
                    </StackPanel>
                    <TextBlock Text="Install Windows Langsung Ke SSD Tanpa Flashdisk"
                               Margin="0,5,0,0" Foreground="#90A9C9" FontSize="12"/>
                </StackPanel>
                <Border Grid.Column="1" Background="#142743" BorderBrush="#2E73BA" BorderThickness="1"
                        CornerRadius="10" Padding="13,7" VerticalAlignment="Center">
                    <TextBlock Text="1.0.0" FontWeight="Bold" Foreground="#7FC0FF"/>
                </Border>
            </Grid>
        </Border>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <Grid Margin="26,20,26,24">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="150"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Border Grid.Row="0" Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="1. WINDOWS ISO" FontWeight="Bold"/>
                        <Grid Margin="0,10,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="12"/>
                                <ColumnDefinition Width="120"/>
                            </Grid.ColumnDefinitions>
                            <TextBox Grid.Column="0" Name="txtIso" IsReadOnly="True" Height="40" VerticalContentAlignment="Center"/>
                            <Button Grid.Column="2" Name="btnBrowse" Content="PILIH ISO" Height="40"/>
                        </Grid>
                    </StackPanel>
                </Border>

                <Border Grid.Row="1" Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="2. TARGET SSD" FontWeight="Bold"/>
                        <Grid Margin="0,10,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="12"/>
                                <ColumnDefinition Width="120"/>
                            </Grid.ColumnDefinitions>
                            <ComboBox Grid.Column="0" Name="cmbDisk"/>
                            <Button Grid.Column="2" Name="btnRefresh" Content="REFRESH" Height="40"/>
                        </Grid>
                        <TextBlock Name="lblSystemDisk" Foreground="#FFB45D" FontSize="11"/>
                        <TextBlock Text="⚠ Target disk akan DIHAPUS TOTAL. Disk sistem Windows otomatis dilindungi."
                                   Margin="0,5,0,0" Foreground="#FF606A" FontSize="11"/>
                    </StackPanel>
                </Border>

                <Border Grid.Row="2" Style="{StaticResource Card}">
                    <StackPanel>
                        <Grid>
                            <TextBlock Text="3. WINDOWS EDITION" FontWeight="Bold"/>
                            <TextBlock HorizontalAlignment="Right" Text="Home / Pro / Education / Enterprise"
                                       Foreground="#7F98B8" FontSize="10"/>
                        </Grid>
                        <ComboBox Name="cmbEdition" Margin="0,10,0,0"/>
                        <TextBlock Text="Edition dibaca otomatis dari ISO yang dipilih."
                                   Margin="0,7,0,0" Foreground="#7F98B8" FontSize="10"/>
                    </StackPanel>
                </Border>

                <Border Grid.Row="3" Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="4. PARTITION MODE" FontWeight="Bold"/>
                        <StackPanel Orientation="Horizontal" Margin="0,10,0,10">
                            <RadioButton Name="rbAutoPartition" Content="Auto Partition" IsChecked="True"
                                         Foreground="#EAF2FF" Margin="0,0,28,0"/>
                            <RadioButton Name="rbCustomPartition" Content="Custom Partition" Foreground="#EAF2FF"/>
                        </StackPanel>
                        <Grid Name="gridCustomPartition" IsEnabled="False">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="170"/>
                                <ColumnDefinition Width="160"/>
                                <ColumnDefinition Width="24"/>
                                <ColumnDefinition Width="150"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Windows size (GB)" VerticalAlignment="Center" Foreground="#A9BAD2"/>
                            <TextBox Grid.Column="1" Name="txtWindowsSizeGB" Text="200" Height="38" VerticalContentAlignment="Center"/>
                            <TextBlock Grid.Column="3" Text="Data label" VerticalAlignment="Center" Foreground="#A9BAD2"/>
                            <TextBox Grid.Column="4" Name="txtDataLabel" Text="DATA" Height="38" VerticalContentAlignment="Center"/>
                        </Grid>
                        <Border Background="#0C1729" CornerRadius="8" Padding="10" Margin="0,10,0,0">
                            <TextBlock Name="lblPartitionPreview"
                                       Text="Preview: EFI 260 MB | MSR 16 MB | Windows = sisa seluruh SSD"
                                       Foreground="#8FA9C9" FontSize="10"/>
                        </Border>
                    </StackPanel>
                </Border>

                <Border Grid.Row="4" Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="5. PARTITION SCHEME" FontWeight="Bold"/>
                        <Grid Margin="0,10,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="24"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0">
                                <TextBlock Text="Partition scheme" Foreground="#A9BAD2"/>
                                <ComboBox Name="cmbScheme" Margin="0,6,0,0">
                                    <ComboBoxItem Content="GPT  (UEFI - modern)" IsSelected="True"/>
                                    <ComboBoxItem Content="MBR  (Legacy BIOS / UEFI-CSM)"/>
                                </ComboBox>
                            </StackPanel>
                            <StackPanel Grid.Column="2">
                                <TextBlock Text="Target system" Foreground="#A9BAD2"/>
                                <ComboBox Name="cmbTarget" Margin="0,6,0,0">
                                    <ComboBoxItem Content="UEFI (non CSM)" IsSelected="True"/>
                                    <ComboBoxItem Content="BIOS (or UEFI-CSM)"/>
                                </ComboBox>
                            </StackPanel>
                        </Grid>
                        <TextBlock Text="Kedua pilihan saling terikat otomatis: GPT = UEFI, MBR = BIOS (Legacy / UEFI-CSM)."
                                   Margin="0,8,0,0" Foreground="#7F98B8" FontSize="10" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>

                <Border Grid.Row="5" Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="6. WINDOWS 11 / OOBE OPTIONS" FontWeight="Bold"/>
                        <CheckBox Name="chkBypassHardware" Content="Prepare for unsupported Windows 11 hardware"
                                  Margin="0,10,0,5" Foreground="#EAF2FF"/>
                        <CheckBox Name="chkBypassOnline" Content="Enable Offline Setup / Local Account path"
                                  Margin="0,4,0,0" Foreground="#EAF2FF"/>
                        <TextBlock Text="Optional. Direct Apply tidak menjalankan compatibility check Windows Setup."
                                   Margin="0,8,0,0" Foreground="#7F98B8" FontSize="10"/>
                    </StackPanel>
                </Border>

                <Border Grid.Row="6" Background="#0C1729" BorderBrush="#1C3151" BorderThickness="1"
                        CornerRadius="12" Padding="15" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Name="lblStatus" Text="Ready."/>
                        <ProgressBar Name="pb" Height="12" Minimum="0" Maximum="100" Value="0" Margin="0,9,0,0"/>
                    </StackPanel>
                </Border>

                <TextBox Grid.Row="7" Name="txtLog" IsReadOnly="True" FontFamily="Consolas"
                         FontSize="11" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                         AcceptsReturn="True" Padding="12"/>

                <Grid Grid.Row="8" Margin="0,14,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="GPT/UEFI • MBR/BIOS • Run as Administrator" Foreground="#6E86A6" FontSize="10"/>
                        <TextBlock Text="Made with ❤️ by REZA" Foreground="#536B8A" FontSize="10" Margin="0,3,0,0"/>
                    </StackPanel>
                    <Button Grid.Column="1" Name="btnInstall" Content="START" Width="180" Height="48"
                            Background="#2388FF" FontSize="14" FontWeight="Bold"/>
                </Grid>
            </Grid>
        </ScrollViewer>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$btnBrowse   = $window.FindName("btnBrowse")
$btnRefresh  = $window.FindName("btnRefresh")
$btnInstall  = $window.FindName("btnInstall")
$txtIso      = $window.FindName("txtIso")
$cmbDisk     = $window.FindName("cmbDisk")
$cmbEdition  = $window.FindName("cmbEdition")
$lblSystemDisk = $window.FindName("lblSystemDisk")
$lblStatus   = $window.FindName("lblStatus")
$pb          = $window.FindName("pb")
$txtLog      = $window.FindName("txtLog")
$chkBypassHardware = $window.FindName("chkBypassHardware")
$chkBypassOnline   = $window.FindName("chkBypassOnline")
$rbAutoPartition   = $window.FindName("rbAutoPartition")
$rbCustomPartition = $window.FindName("rbCustomPartition")
$gridCustomPartition = $window.FindName("gridCustomPartition")
$txtWindowsSizeGB  = $window.FindName("txtWindowsSizeGB")
$txtDataLabel      = $window.FindName("txtDataLabel")
$lblPartitionPreview = $window.FindName("lblPartitionPreview")
$cmbScheme   = $window.FindName("cmbScheme")
$cmbTarget   = $window.FindName("cmbTarget")

$btnBrowse.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Windows ISO (*.iso)|*.iso"
    $ofd.Title = "Pilih Windows ISO"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:SelectedIso = $ofd.FileName
        $txtIso.Text = $ofd.FileName
        $lblStatus.Text = "Membaca edition dari ISO..."
        Load-Editions
    }
})

$btnRefresh.Add_Click({
    Refresh-Disks
    Write-Log "Daftar disk direfresh."
})

$btnInstall.Add_Click({
    try { Prepare-SSDForPC }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,"Error","OK","Error") | Out-Null
    }
})

function Update-PartitionPreview {
    $schemePrefix = "[GPT/UEFI] EFI 260 MB | MSR 16 MB | "
    $mbrWarning = ""
    if ($cmbScheme -and $cmbScheme.SelectedIndex -eq 1) {
        $schemePrefix = "[MBR/BIOS] "
        $mbrWarning = " | MBR: maksimal 2 TB per partisi"
        if ($cmbDisk.SelectedItem -and $cmbDisk.SelectedItem.Size -gt 2TB) {
            $mbrWarning = " | PERINGATAN: MBR tidak mendukung disk lebih dari 2 TB"
        }
    }

    if ($rbCustomPartition.IsChecked) {
        $size = $txtWindowsSizeGB.Text.Trim()
        $label = $txtDataLabel.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($label)) { $label = "DATA" }

        if ($cmbDisk.SelectedItem) {
            try {
                $diskObj = $cmbDisk.SelectedItem
                [double]$gb = 0
                if ([double]::TryParse($size, [ref]$gb)) {
                    $diskGB = [math]::Round($diskObj.Size / 1GB, 1)
                    $dataGB = [math]::Max(0, [math]::Round($diskGB - $gb - 0.3, 1))
                    $lblPartitionPreview.Text = "Preview: $schemePrefix Windows $gb GB | $label ~$dataGB GB$mbrWarning"
                    return
                }
            } catch {}
        }

        $lblPartitionPreview.Text = "Preview: $schemePrefix Windows $size GB | $label = sisa SSD$mbrWarning"
    }
    else {
        $lblPartitionPreview.Text = "Preview: $schemePrefix Windows = sisa seluruh SSD$mbrWarning"
    }
}

$rbAutoPartition.Add_Checked({
    $gridCustomPartition.IsEnabled = $false
    Update-PartitionPreview
})

$rbCustomPartition.Add_Checked({
    $gridCustomPartition.IsEnabled = $true
    Update-PartitionPreview
})

$txtWindowsSizeGB.Add_TextChanged({ Update-PartitionPreview })
$txtDataLabel.Add_TextChanged({ Update-PartitionPreview })
$cmbDisk.Add_SelectionChanged({ Update-PartitionPreview })

$script:SuppressSchemeSync = $false

$cmbScheme.Add_SelectionChanged({
    if ($script:SuppressSchemeSync) { return }
    $script:SuppressSchemeSync = $true
    try {
        if ($cmbScheme.SelectedIndex -eq 1) {
            $cmbTarget.SelectedIndex = 1
            $cmbTarget.IsEnabled = $true
        }
        else {
            $cmbTarget.SelectedIndex = 0
            $cmbTarget.IsEnabled = $false
        }
        Update-PartitionPreview
    }
    finally {
        $script:SuppressSchemeSync = $false
    }
})

$cmbTarget.Add_SelectionChanged({
    if ($script:SuppressSchemeSync) { return }
    $script:SuppressSchemeSync = $true
    try {
        if ($cmbTarget.SelectedIndex -eq 1) { $cmbScheme.SelectedIndex = 1 }
        else { $cmbScheme.SelectedIndex = 0 }
        Update-PartitionPreview
    }
    finally {
        $script:SuppressSchemeSync = $false
    }
})

$cmbTarget.IsEnabled = $false

$window.Add_Closing({
    Dismount-IsoSafe
})

# Fit the window to the available work area so the title bar (and its
# minimize/close buttons) can never be pushed off-screen on small or scaled
# displays, e.g. 1366x768 laptops.
$script:WorkArea = [System.Windows.SystemParameters]::WorkArea
$window.MaxHeight = $script:WorkArea.Height
$window.MaxWidth  = $script:WorkArea.Width
if ($window.MinHeight -gt $script:WorkArea.Height - 16) { $window.MinHeight = [Math]::Max(400, $script:WorkArea.Height - 16) }
if ($window.MinWidth  -gt $script:WorkArea.Width  - 16) { $window.MinWidth  = [Math]::Max(640, $script:WorkArea.Width  - 16) }
if ($window.Height    -gt $script:WorkArea.Height - 16) { $window.Height    = $script:WorkArea.Height - 16 }
if ($window.Width     -gt $script:WorkArea.Width  - 16) { $window.Width     = $script:WorkArea.Width  - 16 }
# CenterScreen centers on the full screen, not on the work area, so on short
# displays it can still push the window under the taskbar. Position manually
# inside the work area instead.
$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
$window.Left = $script:WorkArea.Left + [Math]::Max(0, [Math]::Round(($script:WorkArea.Width  - $window.Width)  / 2))
$window.Top  = $script:WorkArea.Top  + [Math]::Max(0, [Math]::Round(($script:WorkArea.Height - $window.Height) / 2))
Write-Log "Window: $([int]$window.Width)x$([int]$window.Height) (work area $([int]$script:WorkArea.Width)x$([int]$script:WorkArea.Height))"
Refresh-Disks
Update-PartitionPreview
Write-Log "SSDDeploy 1.0.0 ready."
Write-Log "Pilih ISO, pilih SSD target, pilih edition, lalu klik INSTALL."

$window.ShowDialog() | Out-Null
