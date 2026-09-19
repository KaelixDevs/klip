# Klip

A small **Lua-only CLI implementation** of text clipboard history for KDE Plasma on Wayland. Open `klip menu`, type the number of a saved entry, and press Enter. Switch back to your application and press **Ctrl+V**.

Klip is for people who want to recall copied commands, links, snippets, and notes from a terminal without installing a separate graphical history application. It uses `wl-paste` to observe clipboard changes and `wl-copy` to restore saved text.

## Features

- Searchable, paginated terminal menu with numbered selection.
- Persistent history across sessions, with duplicate text moved to the top.
- Exact preservation of multiline text and trailing newlines.
- Commands to search, restore, and delete individual entries.
- Bounded storage, private file permissions, and atomic database replacement.
- No Lua packages to install, compilation, or systemd dependency.

```text
Klip — clipboard history | 3 entries | page 1/1
 1. https://example.org
 2. git status
 3. Remember to update the documentation
Number + Enter: copy | /text: search | /: reset | n/p: page | r: refresh | q: quit
> 2
Copied #2. Switch to your app and press Ctrl+V.
```

The example above illustrates the menu; saved IDs can differ from menu positions.

There are no Python, JavaScript, C, shell-script source files, Lua modules, or build steps. The Lua program invokes `wl-copy`, `wl-paste`, and standard Linux utilities. Terminal commands below are installation instructions, not an additional implementation language.

## Requirements

- Lua 5.1 or newer, available as `lua` on your PATH. Tested with Lua 5.4 and LuaJIT; LuaJIT may also run the source directly.
- `wl-clipboard`, providing `wl-copy` and `wl-paste`.
- KDE Plasma **Wayland**, with the compositor data-control protocol required by your installed `wl-paste --watch`. Plasma X11 is not supported. Old Plasma/wl-clipboard combinations may need updating.
- Standard Linux commands: `mkdir`, `chmod`, `rmdir`, `sleep`, and `/bin/sh` for Lua's process API. Konsole is optional for opening the menu from a desktop shortcut.

No distribution is hardcoded and no systemd service is required. Universal compatibility with every historical distro/compositor version cannot be guaranteed.

## Download and install

### Get the source

Clone this repository:

```sh
git clone https://github.com/KaelixDevs/klip.git
cd klip
```

Alternatively, use GitHub's **Code → Download ZIP**, extract it, and open a terminal in the extracted directory. If you downloaded the standalone `klip.tar.gz` archive, extract it with `tar -xzf klip.tar.gz` and enter the resulting `klip` directory.

### Install for your user

From the source directory:

```sh
lua klip.lua doctor
mkdir -p "$HOME/.local/bin"
cp klip.lua "$HOME/.local/bin/klip"
chmod +x "$HOME/.local/bin/klip"
export PATH="$HOME/.local/bin:$PATH"
```

If `lua` or `wl-clipboard` is missing, install it through your distribution's package manager. Package names vary, especially for versioned Lua interpreters. If your executable is named `lua5.4`, you can run `lua5.4 klip.lua menu` (and other commands) directly, or change the first line of your installed copy to `#!/usr/bin/env lua5.4`.

Check installation:

```sh
"$HOME/.local/bin/klip" doctor
```

If `~/.local/bin` is on your PATH, use `klip` as in the examples below. Otherwise use `"$HOME/.local/bin/klip"` in its place. For the current terminal, `export PATH="$HOME/.local/bin:$PATH"` enables the shorter command.

## First test

1. In one terminal, run `klip watch` and leave it running.
2. In another application, copy two different pieces of text.
3. In a second terminal, run `klip menu`.
4. Type the number beside the older entry and press Enter.
5. Switch to a text editor and press **Ctrl+V**. The selected entry should appear.

The menu restores the clipboard; it does not simulate keystrokes or insert text into an unfocused window. In terminals, the paste shortcut is usually Ctrl+Shift+V.

`watch` captures new copies while it is running. It does not import existing Klipper history. Press Ctrl+C in the watcher terminal to stop collection. History survives restarting Klip and logging out.

## Menu and commands

```sh
klip watch            # Collect text until stopped
klip menu             # Search, select, and copy a saved entry
klip list             # Show stable entry IDs and previews
klip list 'some text' # Search the stored text
klip copy 12          # Put entry ID 12 on the clipboard
klip delete 12        # Remove entry ID 12 from this history
klip clear --yes      # Remove all saved entries
klip path             # Show the history directory
klip doctor           # Check tools and Wayland environment
klip help             # Show all available commands
klip version          # Show the installed version
```

To save piped text manually without changing the current clipboard:

```sh
printf '%s' 'A useful snippet' | klip add
```

In the menu: **1–12 + Enter** selects an entry on the current page; **/words** searches; **/** clears the search; **n/p** changes pages; **r** reloads history; **q** exits. Menu numbers are positions on the displayed page, while `copy` and `delete` use stable IDs from `list`. Search is literal and ASCII-case-insensitive; Unicode case folding is not provided by the Lua standard library.

Multiline text and trailing newlines are retained exactly. Previews escape controls so copied terminal escape sequences are not executed. Duplicate text moves to the top instead of consuming another slot.

## KDE shortcut

In KDE System Settings, open the keyboard shortcut settings and add a command/application shortcut. Labels differ by Plasma version. Set its command to the following, substituting your real absolute home path:

```text
konsole -e /home/YOUR_USER/.local/bin/klip menu
```

Assign your preferred key combination. The shortcut opens a terminal menu; selecting an item exits it. The watcher must already be running.

## Start automatically at login

Create the directory `~/.config/autostart` if it does not exist. Save this text as `~/.config/autostart/klip.desktop`, replacing `/home/YOUR_USER` with your actual home path. If you set `XDG_CONFIG_HOME`, use its `autostart` subdirectory instead.

```ini
[Desktop Entry]
Type=Application
Name=Klip clipboard history
Comment=Remember copied text for the Klip terminal menu
Exec=/home/YOUR_USER/.local/bin/klip watch
Terminal=false
```

This is desktop configuration, not another program. If the executable path contains spaces, double-quote the full path in `Exec`. Log out and log back in to start it. Stop your manually launched watcher first; only one is needed. KDE's Autostart settings should show the entry. Remove the file to disable automatic startup.

## Storage and limits

- Up to **200 unique text entries**, **1 MiB per entry**, **16 MiB total**. Oldest entries are discarded first. Empty or oversized entries are skipped.
- History lives at `$XDG_DATA_HOME/klip/history`, falling back to `~/.local/share/klip/history`. `KLIP_DIR` can override the directory with an absolute path; use the same override for both watcher and menu.
- History is plaintext on disk, stored in a private directory (0700) with a private database file (0600). It is not encrypted.
- `CLIPBOARD_STATE=sensitive` is skipped when supplied by wl-paste. Unmarked passwords or secrets can still be saved.
- This release stores **text only**, not screenshots, image data, arbitrary binary formats, or rich-text formatting.
- Klip has its own history. Deleting entries does not delete Klipper's history or clear the active clipboard. Klipper can run alongside it, but its own persistence settings still apply.

Writers use an atomic directory lock and atomic file replacement, and reject malformed storage rather than overwriting it. A force-killed writer can leave `write.lock`: stop Klip processes, run `klip path`, then remove only that directory using `rmdir /the/printed/path/write.lock`. Do not remove a lock while a writer is running.

## Troubleshooting

- **Missing command:** install the reported dependency and check your PATH.
- **Missing WAYLAND_DISPLAY:** run from a terminal inside Plasma Wayland. Do not run Klip with sudo.
- **Watcher protocol/error message:** confirm you logged into Plasma Wayland and update Plasma/wl-clipboard if the required data-control protocol is unsupported. `doctor` checks the environment, not protocol negotiation; `watch` is the real check.
- **Empty menu:** keep `watch` running and copy new text. Images are intentionally not recorded.
- **Wrong paste target:** switch focus back to the target application before pressing Ctrl+V.

## Tests

From this folder:

```sh
lua tests.lua klip.lua
```

Tests use private temporary storage and Lua mock clipboard commands. They never replace your real clipboard. Coverage includes exact byte preservation, selection/search, deduplication, sensitivity handling, size limits, retention, watcher callback dispatch, command failures, corrupt storage, and concurrent writes. Desktop behavior still needs the first test above on your Plasma session.

Implementation reference: [wl-clipboard upstream documentation](https://github.com/bugaevc/wl-clipboard), plus the installed `wl-clipboard(1)` manual.

## Update

Stop the running watcher first. In your cloned source directory, pull the latest changes and replace the installed file:

```sh
git pull --ff-only
lua tests.lua klip.lua
cp klip.lua "$HOME/.local/bin/klip"
chmod +x "$HOME/.local/bin/klip"
```

Then restart `klip watch`, or log out and back in if using autostart. Your saved history stays in its separate data directory. Check release notes before upgrading across major versions.

## Uninstall

Stop the watcher, remove any KDE shortcut you created, and run:

```sh
rm -- "$HOME/.local/bin/klip"
rm -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/klip.desktop"
```

These commands retain your saved history. If you also want to remove history, run `klip clear --yes` **before** removing the executable. If you used `KLIP_DIR`, use that same environment setting when clearing it.

## Contributing and reporting problems

Issues and pull requests are welcome. For a bug report, include your distribution, Plasma version, Lua version, `wl-paste --version`, the command you ran, and its error output. Use harmless sample text when describing a clipboard issue; do not attach your clipboard database or passwords.

Keep executable source code in Lua and avoid adding Lua package dependencies. Run `lua tests.lua klip.lua` before submitting a change. The tests isolate storage and mock clipboard commands; changes to Wayland integration should also be tested in a real Plasma Wayland session.

## License

Klip is released under the [MIT License](LICENSE). You may use, modify, and redistribute it, including in commercial projects, provided you retain the copyright and license notice. It is provided without warranty.

`wl-clipboard` is a separate dependency with its own license; its source is not bundled in this repository.
