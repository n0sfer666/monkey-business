# Growing the SD card's ext4 partition from macOS

**English** | [Русский](sd-expand-macos.ru.md)

A stock ImmortalWrt image for the NanoPi R2S leaves a rootfs of a few hundred MB regardless of how
big your SD card is. Add xray-core (~25 MB) and the two geo `.dat` files (~30 MB) and the overlay
gets tight — `apk` starts failing with "no space left on device".

The usual fix is to grow the partition on a Linux box. `scripts/expand-sd.sh` does it **natively on
macOS**, using the system's `diskutil`/`fdisk`/`gpt` plus Homebrew `e2fsprogs`. No Linux VM, no
Docker.

> Only **ext2/3/4** can be grown this way. If your image uses **f2fs** as the overlay, this script
> cannot help — macOS has no f2fs resize tool.

---

## Before you start

1. **Back up the card.** The script edits the partition table. It refuses to run without an explicit
   confirmation, but it does *not* make a backup for you. A full image (`dd if=/dev/rdiskN of=…`) or
   at least the first MB is cheap insurance.
2. **Install e2fsprogs** — it's keg-only, so nothing lands in your `PATH`; the script looks in the
   Homebrew prefixes on its own:
   ```sh
   brew install e2fsprogs
   ```
   The script **installs nothing** — it only checks and tells you what's missing.
3. **Power the router off, take the card out, put it in your Mac** and find its device node:
   ```sh
   diskutil list
   ```
   You want the whole device (`/dev/disk14`), **not** a slice (`/dev/disk14s2`). Read the
   `Removable Media` / `Media Name` lines carefully — passing an internal disk is the one mistake the
   script cannot catch for you.

---

## Run it

```sh
sh scripts/expand-sd.sh /dev/disk14
```

It prints the plan, then asks you to type the slice name (`disk14s2`) to confirm. Anything else
aborts. `sudo` is required (raw reads, table edit, filesystem ops) and you'll be prompted for your
password.

> **The script's output is in Russian** — its prompts, progress notes and errors. The quotes below
> are given as they appear, with a translation.

What it does, in order:

1. Detects the scheme (MBR or GPT) and picks the **largest partition** — that's the rootfs/overlay.
2. Verifies a **primary** ext superblock actually sits at the partition's start. It checks the
   `0xEF53` magic *and* that `s_block_group_nr == 0`, so a backup superblock can't fool it. If the
   table's start doesn't match the real filesystem, it scans the card (1 MB steps) for the true
   start and repairs the table — a broken offset is the usual reason a card "won't mount" after a
   botched resize elsewhere.
3. Unmounts the disk, grows the partition to the end of the card, then runs `e2fsck -fy` and
   `resize2fs`. Note the `-y`: repairs are applied without asking.
4. Verifies with `dumpe2fs` that the filesystem now fills the partition.

### It may ask you to eject and re-run — this is normal

macOS caches the partition table. If the kernel hasn't re-read it after the table edit, the script
stops cleanly and tells you:

```
>> ИЗВЛЕКИ И ВСТАВЬ карту, затем запусти скрипт снова — он доделает только ФС.
   (Eject and re-insert the card, then run the script again — it will finish the filesystem.)
```

Eject (`sudo diskutil eject /dev/disk14`), physically re-insert the card, and run the same command
again. The second pass sees the corrected table and only does the filesystem half. The same applies
if the final check reports that the filesystem didn't fill the partition (`ФС НЕ заняла весь
раздел`).

### Environment overrides

| Variable | Default | When you need it |
|----------|---------|------------------|
| `MB_START` | — | Force the partition start (in sectors). Use when the scan can't find the primary superblock and you know where it is; the script still verifies a primary superblock is there and refuses if it isn't. |
| `MB_SCAN_MB` | `512` | How far into the card to scan for the superblock, in MB. Widen it if the scan comes up empty. |

```sh
MB_START=131072 sh scripts/expand-sd.sh /dev/disk14
MB_SCAN_MB=1024 sh scripts/expand-sd.sh /dev/disk14
```

```nu
# nushell
with-env { MB_START: "131072" } { sh scripts/expand-sd.sh /dev/disk14 }
with-env { MB_SCAN_MB: "1024" } { sh scripts/expand-sd.sh /dev/disk14 }
```

---

## Afterwards

Put the card back in the R2S, boot it, and confirm the space is there:

```sh
# df -h /            # rootfs should now reflect the card size
# df -h /overlay
```

Then carry on with [the install guide](install-nanopi.md) — or just re-run `make deploy`, which will
now be able to fetch xray-core and the geo databases.

---

## Known limits

- **The target partition is chosen automatically** (the largest one). You can't point the script at
  a different partition.
- **There is no dry-run and no `--yes`.** The typed confirmation is the only gate — and the only
  thing standing between a typo in the device name and an internal disk with an ext partition on it.
- **It never touches a backup superblock as if it were the primary**, but it also won't repair a
  filesystem that is genuinely corrupt beyond what `e2fsck -fy` handles.
