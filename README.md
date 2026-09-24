# cinegrain 2 - Let's make some more noise!

<p align="left"><img src="images/filmgrain_microscope.jpg"></p>

Realistic film grain for [mpv](https://mpv.io), with a five-zone equalizer that shapes the grain over the brightness range, the way real film stock does.

> **cinegrain 2 replaces [cinegrain](https://github.com/mr-berndt/cinegrain).** The original shader still works, but it is no longer developed.

---

## Why a second version

Watching films with the original cinegrain, I kept running into films whose grain looked very different from mine. The difference was easy to spot once I looked for it: **Aliens** is outright dirty in the lower brightness region and almost clean above mid brightness, while the TV show **Lost** has grain all the way up into the brightest parts of the picture and is rather clean at the bottom end.

| Aliens (1986): heavy grain in the shadows, clean highlights | Lost (2004): grain right up to the white sky |
|---|---|
| [![Aliens, full frame](images/aliens-1986-original.png)](images/aliens-1986-original.png) | [![Lost, full frame](images/lost-s01e24-original.png)](images/lost-s01e24-original.png) |
| [![Aliens, 1:1 detail](images/aliens-1986-crop-bright.png)](images/aliens-1986-crop-bright.png) | [![Lost, 1:1 detail](images/lost-s01e24-crop-sky.png)](images/lost-s01e24-crop-sky.png) |

*Top: full 1080p frames. Bottom: 1:1 crops, no scaling. Both without any synthetic grain. Click an image to see it at full size.*

Analyzing some more films showed what was going on: the intensity of real grain varies wildly along the brightness axis. The reasons are well known once you dig into it: different film stocks, and different ways of exposing and developing them. Here are the approximate grain curves of six films. They have little in common:

[![Grain amplitude over luma for six films](images/grain-curves-six-films.png)](images/grain-curves-six-films.png)

Fun fact: Flashdance and Aliens match very closely!

The same six curves rendered as grain on a grey staircase, from black on the left to white on the right:

[![Six grain characters on a grey staircase](images/greystair-six-films.png)](images/greystair-six-films.png)

A single bell curve with a peak and a width, which is what cinegrain 1 had, cannot follow shapes like these.

## The equalizer

So cinegrain 2 has a graphic equalizer with five zones:

| Zone | Brightness |
|---|---|
| Black | 0 % |
| Shadow | 13 % |
| Mid | 30 % |
| High | 60 % |
| White | 100 % |

Each zone raises or lowers the grain at its brightness, and the shader blends smoothly from one zone to the next. At 0 every zone gives the same amount of grain; −1 removes the grain in that zone completely, positive values add up to four times as much.

The equalizer sits as an overlay over the running picture and is operated with the arrow keys. A built-in grey staircase shows at any time how the grain behaves over the whole brightness range:

| Fine grain up into the highlights | Coarse grain over the whole range | Heavy in the shadows, clean on top |
|---|---|---|
| [![Fine grain](images/menu-greyramp-fine.png)](images/menu-greyramp-fine.png) | [![Coarse grain](images/menu-greyramp-coarse.png)](images/menu-greyramp-coarse.png) | [![Shadow grain](images/menu-greyramp-shadows.png)](images/menu-greyramp-shadows.png) |

## Restoring grain that encoding took away

Most Blu-rays and many other releases still show some of their original grain, but it has visibly suffered in the encode. With the equalizer and the on/off toggle, you set size and intensity per zone until the synthetic grain exactly matches what is left of the original, and fills in what was lost. That takes about 30 seconds and brings back the original look remarkably closely.

It also works wonders on DVDs. The grain acts as dither: the picture looks crisper, and compression artefacts are masked. DVDs become pretty watchable even on large screens and projectors.

## Simpler synthesis, predictable controls

With cinegrain 1 I could imitate most grain patterns by playing with the controls, but I could not simply make the grain larger or softer and keep its character. cinegrain 2 uses a simpler synthesis: white noise, shaped by a Gaussian blur for the grain size, with an optional softening on top. Size and softness now behave predictably, and the grain still looks real. While comparing, I more than once mixed up which grain was real and which was synthetic. Under a microscope there are certainly differences.

---

## Installation

cinegrain 2 consists of one shader and one control script. Tested with mpv 0.40 and 0.41, with `vo=gpu-next` and `vo=gpu`.

1. Copy `shader/cinegrain2.glsl` to `~/.config/mpv/shaders/`.
2. Copy `scripts/cinegrain2-control.lua` to `~/.config/mpv/scripts/`.
3. Add the shader to `mpv.conf`, as the **last** shader in the chain:

   ```ini
   glsl-shaders-append="~~/shaders/cinegrain2.glsl"
   ```

On Windows the folder is `%APPDATA%\mpv\` instead of `~/.config/mpv/`.

The script finds the shader in the shader list by its file name, so the file may be renamed, as long as the name starts with `cinegrain2`. If the shader is missing, the overlay says so.

## Operation

| Keys | Action |
|---|---|
| `Alt+q` | grain on / off, to compare with the original |
| `Alt+←` / `Alt+→` | select the next control |
| `Alt+↑` / `Alt+↓` | change the selected control |
| `Alt+,` / `Alt+.` | previous / next preset |
| `Alt+d` | test picture: off → 50 % grey card → grey staircase |

The overlay shows all eight controls in one row, the selected one in green. It appears with the first key press and disappears 8 seconds after the last one.

### Controls

| Control | Range | Step | Meaning |
|---|---|---|---|
| Level | 0 … 5 | 0.01 | overall grain strength |
| Size | 0 … 3 | 0.05 | grain size (0 = single-pixel 35 mm grain, ~2.5 = 8 mm clumps) |
| Soft | 0 … 10 | 0.1 | softens the grain without changing its size |
| Black, Shadow, Mid, High, White | −3 … +3 | 0.05 | grain in that zone, relative to the others (−1 = none) |

Size is calibrated for 4K output and scales with the output resolution, so a setting looks the same at 1080p and 4K.

### Presets

| Preset | Level | Size | Soft | Black | Shadow | Mid | High | White | Reference |
|---|---|---|---|---|---|---|---|---|---|
| flat | 0.200 | 0.40 | 0.0 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | neutral, same grain everywhere |
| 35mm std | 0.114 | 0.40 | 0.0 | −0.81 | −0.26 | 0.00 | −0.76 | −1.00 | Westworld (2016) |
| 35mm high | 0.075 | 0.75 | 0.0 | −0.90 | −0.59 | −0.04 | 0.00 | −0.95 | Lost (2004) |
| 16mm std | 0.102 | 1.25 | 0.0 | −0.78 | −0.34 | 0.00 | −0.58 | −1.00 | First Man (2018) |
| 16mm low | 0.106 | 1.50 | 0.0 | 0.00 | −0.01 | −0.12 | −0.82 | −1.00 | Leaving Las Vegas (1995) |
| Aliens | 0.240 | 0.50 | 0.8 | +3.00 | +0.90 | −0.15 | −0.45 | −0.95 | Aliens (1986) |

A preset is a starting point: as soon as a control is touched, the overlay shows `[custom]`.

### Sidecars, per film and per series

When you change the grain while a local file is playing, the settings are stored next to the video when it closes, in a small text file:

- films: `<file name>.grain`, e.g. `Aliens (1986).grain`
- series (file names with `S01E02`): `<series>.grain` for the whole series, and optionally a handmade `<series> S01.grain` for one season, which takes precedence

The next time the film or an episode is played, its grain comes back by itself. Videos you only watch get no sidecar, and streams never do. Files without a sidecar start with the last settings used.

### Options

In `~/.config/mpv/script-opts/cinegrain2-control.conf`:

```ini
# store and load .grain sidecars next to the videos
sidecars=yes
# seconds the overlay stays after the last key press
osd_timeout=8
```

### Tips for matching

1. Pause on a calm shot with a wide range of brightness: sky, faces, dark corners.
2. Switch the grain off (`Alt+q`) and look at what is left of the original.
3. Switch it on, set **Size** first, then **Level**, then shape the zones: pull down the zones where the original is clean, raise those where it is heavy.
4. Toggle on and off until you cannot tell where the original ends.
5. Check the result on the grey staircase (`Alt+d` twice).

## How it works

At the resolution of a 4K scan, every pixel covers hundreds of silver-halide crystals. By the central limit theorem, their sum is simply Gaussian noise; simulating the individual crystals, as physical grain models do, gives the same result at a far higher cost. cinegrain 2 therefore takes the shortcut:

```
crystal field        →  noise, new for every frame
optical integration  →  separable Gaussian blur, its width is Size
exposure             →  applied in the density domain: color × exp(Level × zone weight × grain)
```

- **Grain size.** Size is the width (sigma) of the blur in pixels at 2160p. It scales with the output height, so a setting looks the same at 1080p and 4K. The grain is rendered at output resolution, after all scaling, so it stays pixel-sharp whatever the source resolution.
- **Colour.** Film has three emulsion layers, each with its own grain. The shader blurs one noise field and samples it at three widely separated offsets, which gives red, green and blue independent grain without blurring three times. Red is slightly coarser and blue slightly finer, as in real stock. The control script mixes this towards monochrome grain; colour grain stays subtle.
- **Density domain.** Grain changes the density of the silver, so it acts multiplicatively on the light. Applying it as `exp()` instead of adding it keeps blacks black and gives highlights the right amount of sparkle.
- **Zones.** The zone weight is interpolated with smoothstep between the five zones, so the curve has no overshoot and each zone value is exactly what you get at that brightness. Black and White sit at the very ends, so −1 there removes the grain completely.
- **Soft.** An optional 8-tap ring blur with a random rotation per pixel softens the grain without making it larger, like the optical softening of small grain projected large.

### Calibration

The blur width was calibrated against ProRes 4K DCI scans of real film. The measure is the correlation between neighbouring pixels (ac1), which captures how clumpy the grain is:

| Format | Size | ac1 scan | ac1 cinegrain 2 |
|---|---|---|---|
| 35 mm | 0.00 | −0.006 | +0.000 |
| 35 mm heavy | 0.69 | +0.572 | +0.570 |
| 16 mm | 1.13 | +0.821 | +0.820 |
| 16 mm heavy | 1.64 | +0.910 | +0.909 |
| 8 mm | 2.54 | +0.961 | +0.959 |
| 8 mm heavy | 2.57 | +0.962 | +0.961 |

35 mm at Size 0 is pure white noise: that *is* what a 35 mm scan looks like at 4K. The table is also a good starting point for Size when you know the format of a film.

What the shortcut does not reproduce: real grain is very slightly skewed towards bright values, and 8 mm, with only about five crystals per pixel, is not quite Gaussian. Both are hard to see.

## License

MIT
