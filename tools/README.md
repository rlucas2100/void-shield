# Tools

Scripts that make the addon's art and sounds and package it. None of this goes into the game.

Needs Python with: `pip install numpy scipy pillow soundfile pyloudnorm`

Run them from the project root:

```
python tools/art.py VoidShieldVortex/media/art docs/textures   # textures (.tga) + PNG copies for the docs
python tools/compose.py docs/textures docs                    # docs/preview.png and docs/logo.png
python tools/sound.py VoidShieldVortex/media/sounds snd       # renders the soundboard into snd/ to listen to
python tools/package.py                                       # builds VoidShieldVortex-<version>.zip
python tools/package.py --install                             # ...and installs it into your AddOns folder
```

Soundboard files live in `VoidShieldVortex/media/sounds/` as `<pack>_ready.ogg` (your threshold,
7 by default) and `<pack>_max.ogg` (10 stacks). Copy new renders from `snd/` over them when you're
happy. Cues are matched to the original chime's loudness: -14.5 LUFS for ready, -13.8 for max.
