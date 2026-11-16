# Create your own Google Drive client ID

**Why:** out of the box, rclone signs in to Google with a client ID shared by every rclone user. Google rate-limits it heavily. In the original migration, uploads crawled at about 2 Mbps on a connection that could do 80, and one stretch stalled for 40 minutes. With a personal client ID, the same connection ran at 25–100 Mbps. rclone also warns that the shared client ID is being retired.

It takes about 10 minutes and is free. Use the Google account that owns the Drive you're copying to.

## Steps

1. Go to <https://console.cloud.google.com>, accept the terms, and use the project picker at the top to **create a new project** (for example `rclone`).
2. In the top search bar, find **Google Drive API**, open it and click **Enable**.
3. Open **Google Auth Platform** (older screens call it *OAuth consent screen*) and click **Get started**:
   - App name: `rclone`; support email: your Gmail.
   - Audience: **External**.
   - Contact email: your Gmail. Agree, then click **Create**.
4. Go to **Audience**:
   - If you can, click **Publish app**. Published apps stay signed in indefinitely.
   - If **Publish app is greyed out**, which is common, add yourself under **Test users** instead. That works fine, but Google **signs rclone out after 7 days** while the app is in testing. For a longer migration, see *After 7 days* below.
5. Go to **Clients → Create client**, choose application type **Desktop app**, name it `rclone`, and click **Create**.
6. Copy the **Client ID** (`…apps.googleusercontent.com`) and the **Client secret** (`GOCSPX-…`).

## Use it in rclone

Create a new remote, or switch an existing one over:

```powershell
# New remote
rclone config create gdrive drive scope drive client_id YOUR_ID client_secret YOUR_SECRET

# Existing remote: switch it, then sign in again
rclone config update gdrive client_id YOUR_ID client_secret YOUR_SECRET
rclone config reconnect gdrive:
```

When signing in, Google shows **"Google hasn't verified this app"**. That's expected, because it's your own app. Click **Continue** (or *Advanced → Go to rclone*).

Check the speed with a 10 MB test upload:

```powershell
rclone copyto somefile.bin gdrive:speedtest.bin -P
rclone deletefile gdrive:speedtest.bin
```

## After 7 days (testing-mode apps)

If uploads start failing with `invalid_grant` or `token expired`:

```powershell
rclone config reconnect gdrive:
```

Sign in again, then run `start.cmd` again. Finished months are kept.

## Keep it private

The client secret isn't a password, but don't publish it. It lives only in rclone's own config file (`rclone config file` shows where), which this project never reads or commits.
