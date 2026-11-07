# Tools

Python scripts that make the addon's art and sounds (WoW doesn't use this folder).

Needs: `pip install numpy scipy pillow soundfile pyloudnorm`

```
python tools/art.py media prev          # textures -> media/*.tga, PNG copies -> prev/
python tools/compose.py prev docs       # docs/preview.png and docs/logo.png from those PNGs
python tools/sound.py media snd         # reads media/ready.ogg, writes the sound packs to snd/
```

Copy the `.ogg` files from `snd/` into `media/` when you're happy with them. Sounds are matched
to the original chime's loudness: -14.5 LUFS for the 7-stack sounds, -13.8 for the 10-stack ones.
