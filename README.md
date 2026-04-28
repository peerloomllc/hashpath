# HashPath

Bitcoin mining profitability calculator. Single HTML file. No build system, no servers, no accounts, no tracking.

HashPath models a mixed-fleet ASIC operation and projects net profit, ROI, and break-even across a configurable horizon. Halving-aware, difficulty-growth-aware, and honest about variance from your payout model.

## Features

- Mixed-fleet projections with built-in ASIC presets and a "save as preset" workflow for custom rigs
- Multi-site support: per-site CapEx, electricity rate, uptime, and maintenance
- Halving-aware month-by-month model with difficulty growth, BTC price growth, and energy-cost inflation
- Sell-as-mined vs. HODL strategy toggle (drives headline KPIs, charts, and scenarios)
- Payout-model variance band: FPPS / PPS, PPLNS / TIDES, or Solo, with a 90% confidence range on net profit derived from Poisson math
- Live BTC price (CoinGecko, Coinbase fallback), network difficulty + next-adjustment ETA (mempool.space), halving countdown
- Cumulative profit chart, three sensitivity charts (price, difficulty growth, power cost), and a difficulty-history-vs-assumption overlay
- Scenario save / compare with overlay chart and quick Bear / Status Quo / Bull presets
- CSV export of the full monthly projection
- JSON backup / restore, full state cleared on demand
- Dark and light themes (orange-forward, Bitcoin-themed)
- PWA install + offline support via a tiny service worker
- All inputs and saved scenarios live in your browser's `localStorage`. Never leave your device.

## Getting started

```bash
git clone https://github.com/peerloomllc/hashpath.git
cd hashpath
xdg-open hashpath.html    # Linux
open hashpath.html        # macOS
start hashpath.html       # Windows
```

Or just double-click `hashpath.html`. No install required.

For PWA install + offline use, serve over HTTPS (or `localhost` for testing):

```bash
python3 -m http.server     # then visit http://localhost:8000/hashpath.html
```

Edits don't auto-save. Hit the **Save** button in the bottom bar (or `Ctrl/Cmd+S`) to persist. The gold dot on the Save button shows when there are unsaved changes.

## Mining yield formula

```
BTC/day = (hashrate × 86400 × block_reward) / (difficulty × 2^32)
```

Hashrate in hashes per second. The model applies your `Long-term diff growth %/yr` and `BTC price growth %/mo` monthly across the projection, drops the block reward to 1.5625 BTC at the projected halving date, and pulls the next retarget forward using the live `nextAdjustment %` from mempool.space.

## How it works

All data stays on your device. The only outbound network calls are:

| Request | Purpose |
|---|---|
| CoinGecko / Coinbase API | BTC/USD price |
| mempool.space `/api/v1/mining/hashrate/3d` | Network difficulty |
| mempool.space `/api/v1/difficulty-adjustment` | Next-retarget % and ETA |
| mempool.space `/api/blocks/tip/height` | Halving countdown |
| mempool.space `/api/v1/mining/difficulty-adjustments` | Historical difficulty (for the assumption-overlay chart) |
| jsdelivr.net | Chart.js bundle (cached by the service worker after first load) |

Live data is fetched once on page load. Refresh the page to update.

### Persistence

- `hashpath-v1` in `localStorage` - your full state as plain JSON. Inputs are hypotheticals, not financial data, so it's stored unencrypted.
- Live data (BTC price, difficulty, halving countdown) is ephemeral and never persisted.
- Legacy save shapes from earlier versions are migrated transparently on load.

### Architecture

Everything lives in one file (`hashpath.html`, ~3400 lines):

| Section | Purpose |
|---|---|
| CSS | Dark and light themes, grid layout, modals, tooltips, animations |
| HTML | Ticker bar, three views (Calculator / Charts / Scenarios), Settings + About modals |
| JS state, persistence | Global state, dirty tracking, migrations, JSON import/export |
| JS live data | CoinGecko + mempool.space fetches, ticker rendering |
| JS calc core | `fleetTotals()`, `project()` - the month-by-month iteration |
| JS renderers | Results table, charts, scenarios |
| JS Chart.js wiring | Cumulative profit, sensitivity charts, difficulty-history overlay, scenarios overlay |
| JS input wiring | All event listeners, tab switching, master `recalcAndRender` |
| JS PWA setup | Inline manifest, service worker registration, install prompt capture |
| qrcode-generator (kazuhikoarase, MIT) | Inlined for the Donate BTC QR |

`sw.js` (~50 lines) is an optional service worker that precaches `hashpath.html` and Chart.js, then serves them stale-while-revalidate. Live API hosts are passed through so BTC price and difficulty never go stale silently.

## Dependencies

- [Chart.js 4.4.1](https://www.chartjs.org/) - cumulative profit + sensitivity + difficulty-history charts (CDN)
- [qrcode-generator 1.4.4](https://github.com/kazuhikoarase/qrcode-generator) (MIT) - inlined for the Donate BTC QR

That's the full list. No frameworks, no bundler, no package manager.

## Sister projects

HashPath shares its design language with two other single-HTML-file calculators:

- [Cache](https://github.com/peerloomllc/cache) - personal wealth ledger with AES-256-GCM encryption
- [Cache Flow](https://github.com/peerloomllc/cacheflow) - cash-flow / budgeting calculator

## License

Copyright PeerLoom LLC. All rights reserved.
