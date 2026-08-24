# AdGuard filtering

System-wide ad and tracker filtering state and control for
[AdGuard for Linux](https://adguard.com/en/adguard-linux/overview.html) on the Omarchy
bar.

The shield sits in the bar and dims when filtering stops. Open it for the day's block
count, the protection and HTTPS filtering switches, and a row per filter list.

## Features

- **Blocked today**, counted from AdGuard's own access log.
- **Protection switch.** Starts and stops the AdGuard proxy. Right click the bar mark to
  toggle it without opening the panel.
- **HTTPS filtering switch**, the escape hatch when a certificate-pinned site refuses to
  load through the filter.
- **A row per filter list**, each one enabled or disabled in place.
- **Update filters**, which runs AdGuard's own update check.
- **Tailscale exit node warning.** AdGuard's transparent proxy and a Tailscale exit node
  cannot both be on: the proxy opens its own outbound connection and the exit node's
  default route sends it back into the tunnel, so the machine loses internet. The panel
  says so when it sees both.

## Requirements

- `adguard-cli` on `PATH`, activated and configured. The widget removes itself from the
  bar when AdGuard is not installed.
- `proxy_mode` set to `auto`, otherwise AdGuard filters nothing and the panel will
  honestly report a running proxy that is doing no work:

  ```bash
  adguard-cli config set proxy_mode auto
  ```

- `tailscale` on `PATH` is optional. Without it the exit node warning never appears.

## Install

```bash
omarchy plugin add https://github.com/thisisgm/omarchy-adguard.git --enable
omarchy bar put io.github.thisisgm.adguard
omarchy restart shell
```

## Keyboard

The panel is keyboard-first. Accelerators work whenever the panel has focus.

| Key | Action |
|---|---|
| `j` / `k` / arrows | move between rows |
| `enter` / `space` | toggle the row under the cursor |
| `t` | toggle protection |
| `s` | toggle HTTPS filtering |
| `u` | update filters |
| `r` | refresh |
| `esc` | close |

Left click opens the panel, right click toggles protection, middle click refreshes.

## Settings

| Setting | Default | Range |
|---|---|---|
| Refresh interval (seconds) | 30 | 5 to 3600 |

## IPC

```bash
omarchy-shell adguard open
omarchy-shell adguard toggle
omarchy-shell adguard protection
omarchy-shell adguard update
omarchy-shell adguard refresh
```

## How it works

The panel is strictly a display. Everything that touches AdGuard lives in
`bin/omarchy-adguard`, which prints one JSON object and always exits 0, so the panel can
always render something:

```bash
bin/omarchy-adguard status
{"ok":true,"installed":true,"running":true,"httpsFiltering":true,"blockedToday":78, ...}
```

`adguard-cli` exits 0 even when it refuses a request, so the helper never reads an exit
code. Every action re-reads the state afterwards and reports what it actually observed.

The helper never calls `adguard-cli license`, and no field it prints carries the licence
key.

## Adding a filter list

The panel toggles the lists already added. Adding a new one from AdGuard's catalogue of
roughly sixty stays a command-line job, so that the panel does not become a package
manager:

```bash
adguard-cli filters list --all
adguard-cli filters add 18
```

## Uninstall

```bash
omarchy plugin remove io.github.thisisgm.adguard
```

The plugin writes no state of its own, so nothing is left behind. AdGuard's own
configuration is untouched.

## Support

If this saved you an afternoon, you can
[buy me a coffee](https://buymeacoffee.com/thisisgm).

## Licence

MIT. See [LICENSE](LICENSE).
