# Encore on Flathub

Flathub builds Encore itself from the manifest in this folder, which
downloads the Linux tar.gz of a published GitHub release (and mpv's sources).
The manifest is made from `../flatpak/io.github.mohdaffankhan.Encore.yml` by
`tool/flathub_update.sh <version>`: edit that one, not this copy.

Checked before each submission or update (Flathub's own linter):

```sh
docker run --rm -v "$PWD/linux/packaging:/p:ro" ghcr.io/flathub/flatpak-builder-lint manifest /p/flathub/io.github.mohdaffankhan.Encore.yml
docker run --rm -v "$PWD/linux/packaging:/p:ro" ghcr.io/flathub/flatpak-builder-lint appstream /p/io.github.mohdaffankhan.Encore.metainfo.xml
```

## First submission (once, by the owner)

Flathub's reviewers check every new app; it usually takes a few days.

1. Publish the GitHub release (tool/release_check.sh), then run
   `sh tool/flathub_update.sh <version>` and commit the manifest it writes.
2. Fork https://github.com/flathub/flathub on GitHub. Create a branch from its
   `new-pr` branch (not `master`).
3. Put `io.github.mohdaffankhan.Encore.yml` from this folder at the top of
   that branch, commit, and open a pull request against `new-pr`, titled
   "Add io.github.mohdaffankhan.Encore".
4. Answer the reviewers there. The app id is under `io.github.mohdaffankhan`,
   so Flathub verifies it through your GitHub account (the `mohdaffankhan`
   account must own github.com/mohdaffankhan/encore).
5. Once merged, Flathub makes a repository `flathub/io.github.mohdaffankhan.Encore`
   that you are given write access to: updates go there.

## Each release after that

Run `sh tool/flathub_update.sh <version>`, copy the manifest into your clone
of `flathub/io.github.mohdaffankhan.Encore`, commit and push (or open a pull
request there). Flathub builds and publishes it.
