Network connector assets

rclone.zip is the unmodified official rclone v1.75.2 Linux ARM64 archive from:
https://github.com/rclone/rclone/releases/tag/v1.75.2
Archive SHA256: 7e1e8d69654941b7b7df84ee74c5f7fb09cce7d5496947fb7bf16b55ff427d10
The archive contains its MIT license and third-party notices. The app verifies the extracted binary hash before installation.

fusermount3 is compiled from fusermount3.c using Android NDK 28.2, aarch64-linux-android30-clang -O2 -Wall -Wextra -Werror.
It is a root-only helper restricted to the PUBG app's network-games directory and its data/user/0 alias. It does not modify SELinux policy.
