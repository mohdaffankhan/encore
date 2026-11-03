# Encore on the AUR (`encore-music-bin`)

The AUR package installs the Linux tar.gz of a published GitHub release.
CI builds and installs it on Arch for every release (the `aur` job), and
`tool/release_check.sh` checks it again on the draft's files.

## Setting up (once, by the owner)

1. Make an account at https://aur.archlinux.org/register.
2. Make an SSH key for it, if you don't want to use your usual one:
   `ssh-keygen -t ed25519 -f ~/.ssh/aur -C aur`
3. On https://aur.archlinux.org, under My Account, paste the public key
   (`~/.ssh/aur.pub`) into "SSH Public Key" and save.
4. Tell SSH to use it for the AUR, in `~/.ssh/config`:

   ```
   Host aur.archlinux.org
     IdentityFile ~/.ssh/aur
     User aur
   ```

5. Next to this repository, clone the package (the name is free if this
   creates an empty repository; pushing to it creates the package):
   `git clone ssh://aur@aur.archlinux.org/encore-music-bin.git ../aur-encore-music-bin`

## Each release

After the GitHub release is published:
`sh tool/aur_update.sh <version> --push` sets the version and checksum in
PKGBUILD, writes .SRCINFO, and pushes both to the AUR (it publishes the
update). Without `--push` it only prepares them, to look at first.
