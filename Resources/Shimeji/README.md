# Shimeji resource pack

`shimeji_nwero.zip` is the character pack the iOS app downloads at runtime for
the Shimeji experiment. It is **not** bundled into any target — no Xcode group
references this directory — so it adds nothing to the app binary.

The app fetches it from `main` over raw.githubusercontent.com; the URL lives in
`ShimejiResourceManager.packURL`.

## Updating the pack

Replace the zip and merge to `main`. The new pack is live immediately, with no
app release: clients pick it up the next time they download it. Existing
installs keep the copy they already extracted until it is removed from the
Shimeji settings screen and downloaded again.

The archive must satisfy the reader in `ShimejiZipReader`:

- `manifest.json` at the archive root, with `formatVersion` matching the value
  the app accepts (currently `1`). A newer number is rejected with "This pack
  needs a newer version of the app."
- Entries compressed with **store (0) or deflate (8)** only — no zip64, no
  encryption, no other compression method.
- Character frames under `Characters/<folder>/`, matching each character's
  `folder` and the frame names in its `actions`.

`zip -r shimeji_nwero.zip manifest.json Characters` produces a conforming
archive.
