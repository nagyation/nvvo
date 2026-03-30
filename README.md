# nvvo.el — Not VVO: Dresden Public Transport for Emacs

Query Dresden public transport (VVO/DVB) stops and departures from Emacs, with a live mode-line monitor.

Uses the [VVO WebAPI](https://github.com/kiliankoe/vvo/blob/main/documentation/webapi.md) — no API key required.

## Features

- **Stop search** — find stops by name or street
- **Departure monitor** — view upcoming departures in a buffer (press `g` to refresh)
- **Mode-line monitor** — live departure info in your mode line, auto-refreshing every 2 minutes
  - Filter by line and direction
  - Walking time offset (skip departures you can't catch)
  - Delay highlighting (yellow) with real-time data
  - Grouped departures per line/direction

## Installation


If you have version emacs 30+, you could install it directly using use-packge:

```elisp
(use-package nvvo
  :vc (:url  "https://github.com/nagyation/nvvo")
  :config
  (setq nvvo-modeline-stop-id "33000016")       ;; your stop ID
  (setq nvvo-modeline-filters '(("11" "")))      ;; line 11, any direction
  (setq nvvo-modeline-walk-time 5)               ;; 5 min walk to stop
  (nvvo-modeline-mode))

```

Copy `nvvo.el` to your load path and add to your init:

```elisp
(use-package nvvo
  :ensure nil
  :config
  (setq nvvo-modeline-stop-id "33000016")       ;; your stop ID
  (setq nvvo-modeline-filters '(("41" "")        ;; line 41, any direction
                                 ("11" "")))      ;; line 11, any direction
  (setq nvvo-modeline-walk-time 5)               ;; 5 min walk to stop
  (nvvo-modeline-mode))
```

## Finding Your Stop ID

Run `M-x nvvo-search-stop`, type a street or stop name, and pick from the results. The stop ID is shown in the selection list and in the departure buffer header.

## Configuration

| Variable                   | Description                                      | Default |
|----------------------------|--------------------------------------------------|---------|
| `nvvo-modeline-stop-id`    | Stop ID to monitor                               | `nil`   |
| `nvvo-modeline-filters`    | List of `(LINE DIRECTION)` to show               | `nil`   |
| `nvvo-modeline-walk-time`  | Walking time to stop in minutes                  | `0`     |
| `nvvo-modeline-interval`   | Refresh interval in seconds                      | `120`   |

### Filter examples

```elisp
;; Show all lines at the stop (not recommended)
(setq nvvo-modeline-filters nil)

;; Only tram 41 towards Zschertnitz and tram 11 any direction
(setq nvvo-modeline-filters '(("41" "Zschertnitz") ("11" "")))
```

All variables are available via `M-x customize-group RET nvvo`.

## Interactive Commands

| Command                   | Description                                    |
|---------------------------|------------------------------------------------|
| `nvvo-search-stop`        | Search stops, pick one, open departure monitor |
| `nvvo-departure-monitor`  | Show departures for a stop ID                  |
| `nvvo-modeline-mode`      | Toggle mode-line departure monitor             |
| `nvvo-modeline-debug`     | Show all departures with filter match status   |

## Mode-line Display

```
🚋[41→Zschertnitz 6m,16m,26m | 11→Zschertnitz 3m,13m,23m]
```

- Times in yellow indicate delays (using real-time data)
- Departures for the same line+direction are grouped
- Sorted by earliest departure

## Acknowledgements

API documentation by [kiliankoe/vvo](https://github.com/kiliankoe/vvo).
