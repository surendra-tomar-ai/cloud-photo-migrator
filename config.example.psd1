# Copy this file to config.psd1 and edit it. config.psd1 is ignored by git.
# Any setting can also be passed on the command line, e.g.  .\migrate.ps1 -To 2026-06
@{
    # rclone path to copy FROM. Must be a remote you created with 'rclone config'.
    # Jottacloud photos (the timeline) live in the built-in 'Jotta' device, 'Photos' mountpoint:
    Source      = 'jotta,device=Jotta,mountpoint=Photos:'

    # rclone path to copy TO. Folders are created as needed.
    Destination = 'gdrive:From Jottacloud/Photos'

    # 'YearMonth' - the source contains YYYY/MM folders; copy one month at a time, oldest first.
    # 'Single'    - copy the whole source in one go (still resumable and self-healing).
    Layout      = 'YearMonth'

    # Optional month range (YearMonth only), inclusive, 'YYYY-MM'. Leave empty for everything.
    # Example: stop before the month you started backing up to Google Photos directly.
    From        = ''
    To          = ''

    # Parallelism. 8/16 suits a 50-100 Mbps upload; use 4/8 on slow links.
    Transfers   = 8
    Checkers    = 16
}
