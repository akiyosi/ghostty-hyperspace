# hyperspace

A custom terminal shader for **Ghostty** and **Zonvie**: you coast through a
realistic starfield, and every so often the ship makes a Star Wars–style
lightspeed jump — the stars stretch into radial starlines, blaze, and snap into
a brand‑new sky on the far side.

It is a background shader: the terminal text stays crisp on top (opaque‑safe
compositing, so no transparency setting is required).

https://github.com/ — drop your own demo gif/video here.

## What it does

- **Cruise** — a still, uniform starfield with realistic variety:
  - blackbody star colours with a cool‑weighted (realistic) temperature spread,
  - a rare *nearby* star that is a touch larger with a soft halo,
  - a very rare special star with a thin diffraction cross,
  - 0–1 (rarely 2) **dazzling suns** with a hot core, airy glow and 4‑point
    diffraction spikes,
  - on ~half of the locations, an edge‑on **galactic disk**: a band where stars
    bunch up, with a faint diffuse dust glow.
- **Jump** — tails grow outward from each star (a gentle ~0.7 s onset, then
  full), a flash swaps in the destination field, and the new sky's starlines
  converge to points (the bright suns' spikes then extend in over a couple of
  seconds).
- **Per‑location variety** — each jump reseeds the whole sky: different star
  positions, colours, galaxy orientation/presence, and bright‑sun count/positions.

> Note: the streaking starlines are the *cinematic* look, not the physically
> correct one (real relativistic travel concentrates light into a forward
> blue‑shifted disc — McKinley & Doherty 1979). This shader goes for the films.

## Install

Use an **absolute path** to the `.glsl` file.

### Ghostty (`~/.config/ghostty/config`)

```
custom-shader = /path/to/hyperspace/hyperspace.glsl
custom-shader-animation = true
```

Reload with `Cmd+Shift+,`.

### Zonvie (`config.toml`)

```toml
[shaders]
paths = ["/path/to/hyperspace/hyperspace.glsl"]
```

Only `iResolution`, `iTime`, `iChannel0` and `iDate` are used — all supplied by
both platforms, so the same file runs unmodified on either.

## Tuning

Edit the constants at the top of `hyperspace.glsl`.

### Warp timing

| Constant | Default | Meaning |
|---|---|---|
| `WARP_INTERVAL` | `16.0` | Cruise seconds between warps. **`0` = never warp** (a permanently static sky). |
| `ENTRY_DUR` | `4.0` | Length of the entry (tails grow outward). |
| `EXIT_DUR` | `4.0` | Length of the exit (lines converge to points). |
| `SLOW_T` / `SLOW_FRAC` | `0.7` / `0.08` | The gentle slow start of the entry: tails creep to `SLOW_FRAC` of full length over `SLOW_T` seconds before extending the rest. |
| `EMAX` | `1.1` | How far entry tails extend outward. |
| `CONV` | `0.96` | How far the exit's inward tails reach toward the centre (`<1`). |
| `KMAX` / `EL` | `20` / `18` | Motion‑blur sample count and per‑sample radial stretch (keeps streaks continuous). |

### Starfield

| Constant | Default | Meaning |
|---|---|---|
| `DENS` | `1.0` | Cruise field density (star count ≈ `DENS²`). |
| `STAR_GAIN` | `1.45` | Overall brightness. |
| `STAR_PX` | `0.0007` | Star/line half‑width (thin points and lines). |
| `WARP_GLOW` | `5.0` | Extra streak brightness toward the climax. |
| `REVEAL` | `0.10` | How visible the faint background suns are in cruise (they brighten during the jump). |

### Bright "dazzling" suns

| Constant | Default | Meaning |
|---|---|---|
| `HERO_GAIN` | `2.3` | Their brightness. |
| `SPIKE_TIME` | `2.2` | Seconds for their cross spikes to extend in after arrival. |

Count distribution (in `heroStars`): ~62% none, ~36% one, ~2% two, never three.
Edit the `hn < …` thresholds to change how often a bright sun appears.

### Rare star variations

| Constant | Default | Meaning |
|---|---|---|
| `NEAR_RARE` | `0.991` | Rarity of a slightly‑larger "nearby" star (higher = rarer). |
| `NEAR_GLOW` | `0.12` | Its soft halo brightness (no spikes). |
| `CROSS_RATE` | `0.9999` | ~0.01% of points carry a thin diffraction cross (higher = rarer). |
| `CROSS_AMP` / `CROSS_LEN` | `0.22` / `0.025` | That cross's brightness / arm length. |

### Galaxy

| Constant | Default | Meaning |
|---|---|---|
| `GAL_WIDTH` | `0.22` | Thickness of the galactic band. |
| `GAL_DENS` | `3.5` | Extra star density along the disk plane. |
| `GAL_GLOW` | `1.4` | Diffuse dust‑glow brightness. |

A disk appears in ~50% of locations (see the `galOn = step(0.5, …)` in
`fieldStars`/`mainImage`).

### Compositing

```glsl
#define BLEND_ALPHA 0      // 0: luminance key (default, opaque-safe). 1: alpha blend (transparent Ghostty only)
const float BG_LEVEL = 0.12;  // background brightness; raise to just above your theme's bg so code stays readable
const float BG_SOFT  = 0.10;  // glyph-edge softness of the key
```

## Notes

- The shader is deterministic in `iTime`; a per‑launch offset from `iDate`
  randomises the *first* sky between launches without affecting the per‑jump
  reseed. If your platform's `iDate` is unstable you can drop that offset (see
  the `launch` line in `mainImage`).
- Performance scales with `KMAX` (warp only) and `DENS`. Lower `KMAX` if the
  jump frames feel heavy; raise `DENS` for more stars (cheap).
