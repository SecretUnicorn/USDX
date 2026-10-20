# UltraStar Deluxe

[![Build Status](https://github.com/UltraStar-Deluxe/USDX/actions/workflows/main.yml/badge.svg)](https://github.com/UltraStar-Deluxe/USDX/actions/workflows/main.yml)
[![License](https://img.shields.io/badge/license-GPLv2-blue.svg)](LICENSE)

Official Project Website: https://usdx.eu/

![UltraStar Deluxe Logo](https://github.com/UltraStar-Deluxe/USDX/blob/master/icons/ultrastardx-icon_256.png)


### 1. About
UltraStar Deluxe (USDX) is a free and open source karaoke game. It allows up to six players to sing along with music using microphones in order to score points, depending on the pitch of the voice and the rhythm of singing.
UltraStar Deluxe is a fork of the original UltraStar (developed by corvus5).
Many features have been added like party mode, theme support and support for more audio and video formats.
The improved stability and code quality of USDX enabled ports to Linux and macOS.

### 2. Installation
Currently, the following installation channels are offered:
- installer (or portable version) for [the latest release](https://github.com/UltraStar-Deluxe/USDX/releases/latest)
- flatpak from [flathub](https://flathub.org/apps/eu.usdx.UltraStarDeluxe)
- Arch Linux [AUR](https://aur.archlinux.org/packages/ultrastardx-git)

### 3. Configuration
- To set additional song directories change your config.ini like this:
```ini
  [Directories]
  SongDir1=C:\Users\My\Music\MyUSDXSongs
  SongDir2=F:\EvenMoreUSDXSongs
  SongDir...=... (some more directories)
```
- To enable joypad support change config.ini `Joypad=Off` to `Joypad=On`
- To enable 2 or 3 player each on 2 screens, disable the full screen mode, extend your desktop horizontally and set the resolution to fill one screen. Then, in the config.ini set `Screens=2` and restart the game.
- The primary folder for songs on macOS is `$HOME/Music/UltraStar Deluxe`, which is created when UltraStar Deluxe is run for the first time.
- On macOS, by default the `config.ini` file is created in `$HOME/Library/Application Support/UltraStarDeluxe` when UltraStar Deluxe is run for the first time.
- When running in borderless fullscreen mode, the monitor it runs on can be configured by setting `Graphics.PositionX/Y` to an offset in pixels.
- If installed via the flatpak package, the primary song folder is `~/.var/app/eu.usdx.UltraStarDeluxe/.ultrastardx/songs/` and the config.ini is located in `~/.var/app/eu.usdx.UltraStarDeluxe/.ultrastardx/` by default. To configure additional song directories, they first need to be made accessible to the flatpak app using the command: `flatpak override eu.usdx.UltraStarDeluxe --filesystem=/your/new/songfolder` - Afterwards, the directory can be added to the config.ini file as usual.

### 4. Song requests from the local network
Guests can browse the song collection and queue songs from their phone while the
game keeps running on the host machine.

Enable it in your `config.ini`:
```ini
  [WebQueue]
  Enabled=On
  Port=8080
  Overlay=On
  Address=
```
On the next start the game opens a small web server on that port and shows the
address to open (for example `http://192.168.1.20:8080`) in the queue overlay at
the bottom left of the screen. Everyone on the same network can open that page,
search the song list and add songs to the queue; entries can be reordered or
removed from the page again. Songs that carry medley in/out tags also offer a
green **½** button next to the **+**, which queues only the tagged part of the
song; those entries are marked SHORT in the queue.

If the configured port is already taken by another program, the next free port
is used and the overlay shows the address that actually works.

`Address` overrides the address shown in the game and in the QR code, for
machines that have several network interfaces or a nicer host name. It accepts a
host (`karaoke.local`), a host with port (`karaoke.local:8080`) or a complete URL
(`http://karaoke.local:8080`); without a port the one the server listens on is
appended. Leave it empty to detect the address automatically.

In the game:
- `Ctrl+N` sings the next song of the queue. If a song is running it is stopped
  first. The very first time it opens the player setup, because the sing screen
  is built there - confirm the players once, then `Ctrl+N` starts songs directly.
- `Ctrl+L` shows/hides the queue overlay. `Overlay=Off` hides it by default.
- `Ctrl+Q` shows/hides a big QR code of the address for guests to scan.
- `Ctrl+M` turns the queue into a medley: it lists the queued songs, marks the
  ones USDX has medley data for, and `Left`/`Right` pick how many of them to
  sing. `Enter` starts, `Esc` closes. The queue itself is kept.

The song list can be sorted by artist, title, year, length or how often a song
has been sung, each ascending or descending, or shuffled into a random order - the random order is new on every
page load and the button next to the selector reshuffles it, so the same songs
do not end up on top all evening. Every entry says how often it has been sung,
taken from the same statistics the game shows, so *Times sung* with *Least
first* finds the songs nobody has picked yet. Every entry shows its length, is
marked TODAY while it has already been sung today and QUEUED while it waits in
the queue. The search tolerates typos, so *metalica* still finds Metallica.

**Shuffle** above the queue mixes it so that nobody sings three songs in a row,
as far as the queue allows that at all.

If a song is not in the collection, searching for it offers **Request this
song**. Requests are appended to `song-requests.txt` next to `config.ini` with
the time and the name of whoever asked, to read through after the party.

The request page can show the songs as a plain list, as a list with covers or as
a grid of covers. Covers are scaled down once and cached in the `webcovers`
folder of your UltraStar directory, so phones do not download the full size
images.

The server only serves the request page, its JSON endpoints and those cover
thumbnails, it never exposes other files. It has no authentication, so only enable it on a network you trust.

If a phone refuses to open the address, let it scan the QR code instead of typing
the address: Chrome's "Always use secure connections" turns a typed IP into an
`https://` address, which this server does not speak. The QR code contains the
full `http://` address and is not affected.

#### Changing the players while a song runs
`http://<the same address>/players` is a second page for the host. It lists the
players of the running song with the colour of their microphone, their current
score, and a field for the name. A name typed there is applied immediately: the
sing screen shows it, and the score at the end of the song is stored under it -
useful when the microphones change hands mid-party. Without a running song the
names are kept for the next one.

The page is not linked from the request page, but it is not protected either,
so anybody on the network who knows the address can rename the players.

### 5. Measuring the microphone delay
Wireless speakers add a lot of delay, which makes singing score badly because
the game hears the music later than it plays it. In *Options -> Game*, `C` plays
five short clicks and measures how long each one takes to come back through the
microphone of player 1. That is the whole round trip, speakers plus microphone,
so *Audio/Video Delay* is subtracted from the median before the rest is written
to *Microphone Delay*. Set *Audio/Video Delay* first, then measure.

The background music is paused while the clicks play, otherwise it masks them.
Put the microphone where it will be sung into, keep the room quiet during the
measurement, and redo it whenever you change speakers. Repeated measurements can
differ by up to about 50 ms because the capture buffer aligns differently each
time; if the result looks off, run it again.

### 6. Merging the scores of older versions
Every version keeps its own settings directory (`UltraStarDeluxe<version>` in
your user data folder), high scores and statistics included, so after an update
the statistics tab starts at zero again. `tools/merge-score-dbs.py` merges the
databases of all installed versions into one:

```
python3 tools/merge-score-dbs.py           # list what would be merged
python3 tools/merge-score-dbs.py --apply   # merge, after backing the target up
```

It merges into the most recently used database, matches songs by artist and
title and skips scores that are already there, so start the new version once
before running it, and running it twice does no harm.

### 7. Further documentation
The [documentation](https://usdx.eu/docs/) contains more information on:
* [Command-line parameters](https://usdx.eu/docs/command-line-parameters/)
* [Controls](https://usdx.eu/docs/controls/)
* [Customization](https://usdx.eu/docs/customization/)

### 8. Compiling
The game has an Autotools-based buildsystem and can be compiled by running `./autogen.sh && ./configure [--enable-debug] && make`. The executable will be `game/ultrastardx[.exe]`.

For extended information, dependencies, OS-specific notes and configure flags, see [COMPILING.md](COMPILING.md).

### 9. Making a release
See [RELEASING.md](RELEASING.md)

Other useful documents for maintainers: [pipeline info](PIPELINE.md).
