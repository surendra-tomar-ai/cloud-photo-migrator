# cloud-photo-migrator

Move a large photo and video library from one cloud to another (for example **Jottacloud → Google Drive**) without babysitting it for a week.

It's a thin, battle-tested wrapper around [rclone](https://rclone.org). rclone does the copying; these scripts make a multi-day migration over a home internet connection survive the things that actually go wrong: Wi-Fi drops, a VPN coming back on, a laptop restart, throttled uploads, and the odd file whose checksum is wrong at the source.

It was built during a real migration of **~47,000 photos and videos (≈400 GiB)** from Jottacloud to Google Drive, and every feature below exists because that migration needed it. After it finished, the verifier confirmed every file at the destination against the source.

## What it does

- **Copies month by month, oldest first.** It works through `YYYY/MM` folders (the way Jottacloud and many photo apps store photos) one at a time, so you can see progress and stop at any month. You can also copy a whole folder in one go.
- **Resumes where it left off.** Finished months are recorded. Run it again after a restart and it skips them, and rclone never re-uploads files that are already there.
- **Heals itself after outages.** If the connection drops, it waits until both clouds are reachable again and retries the month. You don't have to be there.
- **Checks every file.** rclone compares checksums on every upload. If a file keeps failing because the *source* cloud has the wrong checksum recorded for it, the script spots that and copies the file anyway. It lists the file for you to review rather than retrying forever.
- **Keeps Windows awake** while it runs.
- **Verifies the result.** `verify.ps1` compares every file at the destination with the source (name, size and checksum) and lists anything missing or different.

## Requirements

- [rclone](https://rclone.org/downloads/) 1.65 or newer.
- PowerShell: Windows PowerShell 5.1 (built into Windows 10/11) or PowerShell 7+ on Windows, macOS or Linux.
- Accounts on both clouds, connected in rclone (`rclone config`).

## Quick start

```powershell
# 1. Get the scripts
git clone https://github.com/surendra-tomar-ai/cloud-photo-migrator.git
cd cloud-photo-migrator

# 2. Connect your clouds in rclone (one-time; see the guides below)
rclone config

# 3. Configure
copy config.example.psd1 config.psd1     # then edit Source / Destination / From / To

# 4. Preview, then run
.\migrate.ps1 -DryRun
.\start.cmd                              # or: .\migrate.ps1

# 5. When it says ALL UNITS FINISHED
.\verify.ps1
```

On Windows you can just double-click **`start.cmd`** to start or resume.

## Guides

- **[Jottacloud → Google Drive, step by step](docs/jottacloud-to-google-drive.md)**: the full walkthrough, including where Jottacloud keeps your photos and how to connect both accounts.
- **[Create your own Google Drive client ID](docs/google-drive-client-id.md)**: do this before a big upload. rclone's shared Google client is heavily throttled; in the original migration, switching to a personal client ID made uploads about 8× faster.
- **[Troubleshooting](docs/troubleshooting.md)**: every problem hit during the original migration, with the fix for each.

## Settings

Put settings in `config.psd1`, or pass any of them on the command line (the command line wins).

| Setting | Default | Meaning |
|---|---|---|
| `Source` | (required) | rclone path to copy from, e.g. `jotta,device=Jotta,mountpoint=Photos:` |
| `Destination` | (required) | rclone path to copy to, e.g. `gdrive:From Jottacloud/Photos` |
| `Layout` | `YearMonth` | `YearMonth`: the source has `YYYY/MM` folders, copied one month at a time. `Single`: copy the whole source as one unit. |
| `From` / `To` | (empty) | Inclusive month range, `YYYY-MM`. For example, set `To` to the month before you started backing up to the new cloud directly. |
| `Transfers` / `Checkers` | `8` / `16` | Parallel uploads and comparisons. Use `4` / `8` on slow connections. |
| `ChunkSize` | `32M` | Google Drive upload chunk size. Other backends ignore it. |
| `MaxAttempts` | `100` | Attempts per month before giving up. |
| `StateDir` | `.\state` | Where the log and progress files are kept. |
| `Rclone` | auto | Path to rclone if it isn't on your PATH. |

Run `.\migrate.ps1 -DryRun` to see what would be copied without copying anything.

## Files it creates

All in `state\` (git ignores this folder):

| File | What it's for |
|---|---|
| `migrate.log` | Full rclone log, plus `===== START / DONE / FAILED` markers for each month. |
| `done.txt` | Months that finished cleanly. Delete a line to make it redo that month. |
| `checksum-skipped.txt` | Files copied without the checksum check because the source's stored checksum is wrong. Open them at the destination to make sure they're fine. |
| `verify-*.txt` | Results from `verify.ps1`: missing, different and matching files. |

## How long will it take?

Roughly your **upload** speed, because every file is downloaded and then uploaded by your computer. Some useful numbers:

| Upload speed | Per day (approx.) | 400 GiB takes |
|---|---|---|
| 6 Mbps | 60 GiB | ~7 days |
| 25 Mbps | 250 GiB | ~2 days |
| 80 Mbps | 700 GiB* | ~14 hours |

\* Google Drive caps uploads at **750 GB per account per day**. rclone stops cleanly at the cap; run it again the next day.

Measure your real upload speed first, for example at speed.cloudflare.com. Then **create your own Google client ID**, because the shared one can be far slower than your connection.

## Running the tests

```powershell
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

The unit tests cover path handling and the checksum-mismatch detector. The end-to-end test migrates a fake local photo library, re-runs it to prove that resume works, and then checks that `verify.ps1` catches a deleted file. Needs only rclone.

## Safety

- It only ever **copies**. It never deletes or moves anything at the source, and never deletes anything at the destination except a failed partial upload, which rclone removes itself.
- Your cloud logins live in rclone's own config file, never in this project. `config.psd1` holds only folder names. Both it and `state\` are git-ignored.
- **Don't delete your old cloud** until `verify.ps1` reports *All files verified* and you've opened a few photos and videos at the destination.

## License

[MIT](LICENSE)
