# Jottacloud → Google Drive, step by step

This guide follows the migration this project was built for: about 47,000 photos and videos (≈400 GiB) from Jottacloud's photo timeline into a Google Drive folder, on Windows.

## 1. Install rclone (no admin rights needed)

1. Download the Windows zip from <https://rclone.org/downloads/> (`rclone-vX.Y.Z-windows-amd64.zip`).
2. Extract `rclone.exe` to a folder, e.g. `%LOCALAPPDATA%\Programs\rclone`, and add that folder to your **user** PATH (Settings → System → About → Advanced system settings → Environment Variables → *User variables* → Path).
3. Open a **new** terminal and check that it works: `rclone version`.

Alternatively, put `rclone.exe` next to `migrate.ps1`. The scripts look there too.

## 2. Check that your network allows it

Work laptops often route all traffic through a company VPN or security agent (Palo Alto GlobalProtect, Zscaler, Netskope, …), and these commonly block personal cloud storage such as Jottacloud, **even on your home Wi-Fi**.

Test before you start:

```powershell
rclone lsd jotta:     # after step 3; or open https://www.jottacloud.com in a browser
```

If you get an HTML page titled "Web Page Blocked", or `HTTP error 503`, your network is blocking it. Use a computer and network that allow it. Don't try to get around your employer's security controls.

## 3. Connect Jottacloud

1. In the Jottacloud web app, go to **Settings → Security → Personal login token** and generate a token.
   The token expires quickly (it stopped working within a few days in testing), so use it straight away.
2. Create the remote, using your token in place of `PASTE_TOKEN`:

   ```powershell
   rclone config create jotta jottacloud config_type standard config_login_token PASTE_TOKEN
   ```

### Where are my photos?

Jottacloud has several "mountpoints", and **photos are not in the default one**:

| Mountpoint | What's in it | rclone path |
|---|---|---|
| Archive | rclone's default; often empty | `jotta:` |
| Sync | Files from the desktop sync folder | `jotta,device=Jotta,mountpoint=Sync:` |
| **Photos** | **The photo timeline (phone backups)** | `jotta,device=Jotta,mountpoint=Photos:` |
| Shared, Contacts | Shared folders, contact backups | `...mountpoint=Shared:` etc. |

Look around before you copy:

```powershell
rclone about jotta:                                           # total storage used
rclone lsd  "jotta,device=Jotta,mountpoint=Photos:"           # years
rclone size "jotta,device=Jotta,mountpoint=Photos:" --fast-list
```

> **The month folders in Photos are *upload* dates, not *taken* dates.** `Photos/2022/12/` can contain a photo named `20220710_...jpg` (taken in July 2022) because it was uploaded in December 2022. Your first month is often huge, because that's when the whole phone was first backed up.

## 4. Connect Google Drive, with your own client ID

Follow **[Create your own Google Drive client ID](google-drive-client-id.md)** first. Then:

```powershell
rclone config create gdrive drive scope drive client_id YOUR_ID client_secret YOUR_SECRET
```

A browser opens. Sign in, accept the "Google hasn't verified this app" warning (it's your own app), and allow access. Then check it works:

```powershell
rclone lsd gdrive:
rclone about gdrive:     # make sure there's enough free space
```

> **Google Photos vs Google Drive.** The files go into **Google Drive**, not the Google Photos app. Since 31 March 2025, Google no longer lets outside apps such as rclone read or upload to your Google Photos library. As a result, nothing can automatically check which photos are already in Google Photos. If you started backing up to Google Photos from a certain month, use `To` to stop the migration before that month.

## 5. Configure and run

```powershell
copy config.example.psd1 config.psd1
notepad config.psd1
```

```powershell
@{
    Source      = 'jotta,device=Jotta,mountpoint=Photos:'
    Destination = 'gdrive:From Jottacloud/Photos'
    Layout      = 'YearMonth'
    From        = ''
    To          = '2026-06'      # e.g. the month before you switched to Google Photos
    Transfers   = 8
    Checkers    = 16
}
```

```powershell
.\migrate.ps1 -DryRun     # preview
.\start.cmd               # run (double-click works too)
```

Keep the computer **plugged in, with the lid open, connected, and off any VPN** that blocks Jottacloud. If it stops for any reason, run `start.cmd` again and it carries on from where it stopped.

**Other folders:** run it again for the Sync folder with a different state folder, so progress isn't mixed:

```powershell
.\migrate.ps1 -Source 'jotta,device=Jotta,mountpoint=Sync:' -Destination 'gdrive:From Jottacloud/Documents' -Layout Single -StateDir .\state-sync -ConfigFile none
```

## 6. Verify

```powershell
.\verify.ps1
```

Expected result:

```
Matching files:          46798
Missing at destination:  0
Different:               0
Copied without checksum: 1   (source checksum was wrong; open these to confirm they're fine)
    2023/06/23/20230623_101500.mp4

All files verified.
```

Open anything listed under *Copied without checksum* to confirm it plays. Then spot-check a few months in Google Drive before you cancel Jottacloud.

## Real-world numbers from the original run

| | |
|---|---|
| Library | 49,785 files / 430 GiB (46,805 files / 403 GiB in the chosen range) |
| Connection | 80 Mbps upload on paper; 10–100 Mbps in practice, with several drops |
| Throughput | 2–7 Mbps with rclone's shared Google client, 25–100 Mbps with a personal client ID |
| Duration | About 3 days of wall-clock time, including restarts |
| Problems hit | Corporate VPN block, folder name with a trailing space, Google throttling, Wi-Fi drops (4), one file with a wrong stored checksum. See [troubleshooting](troubleshooting.md). |
