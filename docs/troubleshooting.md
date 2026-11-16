# Troubleshooting

Every problem below happened during the original Jottacloud → Google Drive migration.

## "Web Page Blocked" / HTTP 503 when connecting to the source

**Cause:** a company VPN or security agent (GlobalProtect, Zscaler, Netskope, …) routes your traffic through a firewall that blocks personal cloud storage. This happens even on home Wi-Fi, because the agent runs on the laptop itself.

**Check:** `Get-NetAdapter | ? Status -eq Up` shows a VPN adapter (e.g. "PANGP Virtual Ethernet Adapter").

**Fix:** run the migration from a computer and network that allow it. Don't try to get around your employer's security controls. If the VPN reconnects in the middle of a run, the script waits and resumes once both clouds answer again.

## Jottacloud: `Illegal trailing whitespace in name of file/path`

**Cause:** a folder at the source is named with a trailing space (e.g. `"documents "`). Jottacloud stores it, but rejects requests for it.

**Fix:** rename the folder in the Jottacloud web app to remove the space, then run again.

## Jottacloud: `invalid_grant` / `Invalid user credentials` when creating the remote

**Cause:** the personal login token has expired.

**Fix:** generate a new one (Settings → Security → Personal login token) and use it straight away.

## Jottacloud remote looks empty, but `rclone about` shows hundreds of GB used

**Cause:** rclone's default mountpoint is *Archive*. Phone photos are in *Photos*.

**Fix:** use `jotta,device=Jotta,mountpoint=Photos:` (see [the guide](jottacloud-to-google-drive.md#where-are-my-photos)).

## Uploads to Google Drive are far slower than your connection

**Cause:** rclone's shared Google client ID is rate-limited. Signs of it:
- the log shows a notice about the shared client_id
- a speed test (speed.cloudflare.com) shows much higher upload than rclone achieves
- rclone sits idle with only one or two connections open

**Fix:** [create your own client ID](google-drive-client-id.md). This made the biggest difference of anything in the original run.

If it's *still* slow, your internet's upload speed is the limit. It varied 10× by time of day during the original run.

## `corrupted on transfer: md5 hashes differ` on the same file, again and again

**Cause:** the source cloud has the wrong checksum recorded for that file. Every download returns identical data, but it never matches the recorded checksum, so rclone treats every upload as damaged and deletes it.

**What the script does:** after 3+ failures where the destination computed the *same* hash every time, it copies that file once with `--ignore-checksum`, then lists it in `state\checksum-skipped.txt` and the log. If the destination hash changes between attempts, that's real damage in transit, and it keeps retrying normally.

**What you should do:** open each listed file at the destination and confirm it opens or plays. A wrong recorded checksum can also mean the file was already damaged at the source; the copy is identical to what the source gives out.

## `dial tcp: lookup ...: no such host` / thousands of errors in a few seconds

**Cause:** the internet or DNS dropped briefly. Every file in progress failed at the same moment.

**What the script does:** rclone retries the month's failed files (3 passes). If the month still fails, the script waits until both clouds are reachable and runs the month again. Nothing is needed from you.

## Many `404` errors after the laptop slept or changed networks

**Cause:** Google Drive upload sessions expired while the laptop was asleep or offline.

**Fix:** restart it. Close the window and run `start.cmd`. Files already uploaded are skipped.

## Errors such as `failed to set directory modtime: directory not found`

**Cause:** a side effect of other failed uploads: rclone tried to set a date on a folder whose files hadn't arrived yet.

**Fix:** none needed. It clears up when the retry copies those files.

## The script stopped and the computer had restarted

Windows Update can restart the computer outside your "active hours". Before a multi-day run, pause updates (Settings → Windows Update → Pause for 1 week) and keep the laptop plugged in with the lid open. Then run `start.cmd` again. If a VPN reconnected after the restart, disconnect it first.

## I want to redo a month

Delete that month's line from `state\done.txt` and run again. Only missing or changed files are copied.
