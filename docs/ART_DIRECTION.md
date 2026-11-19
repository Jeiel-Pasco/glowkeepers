# Art direction

Every built thing (homes, fences, stations, decorations, props) follows these rules so it sits
in the same forest as the low-poly trees.

## The rule

1. **Low poly, few pieces.** A model is 3–15 chunky parts: blocks, wedges, the forest pack's
   meshes. Shapes read from 30 studs away; nothing is there that only shows up close.
2. **Not boring:** each model has one idea that makes it charming (a crooked roof, a lantern
   on a hook, a moss cap), not ten.
3. **No AI-generated meshes, no painted textures.** Surfaces are flat colour on matte
   materials: Wood, Slate/Rock, Grass, Fabric, Plastic. No SmoothPlastic or Neon on large
   surfaces (Neon only for small light sources: a lantern pane, a crystal tip, a rune).
4. **Muted, from the forest.** Colours come from the palette below. Saturation stays under
   about 55%; nothing brighter than the leaves except light sources.
5. **One silhouette per tier.** Bigger means taller and wider, not busier.

## Palette

| Name | RGB | Use |
|---|---|---|
| leaf | 78, 138, 70 | foliage, moss |
| leaf deep | 52, 98, 62 | pine, shadows of foliage |
| bark | 105, 72, 50 | posts, trunks, dark wood |
| plank | 150, 112, 78 | floors, boards |
| plank light | 178, 142, 104 | trim, signs |
| stone | 118, 114, 112 | walls, rings |
| stone light | 150, 144, 136 | cobbles, caps |
| thatch | 168, 146, 98 | roofs (straw) |
| roof | 120, 84, 70 | roofs (shingle) |
| cloth moss | 96, 120, 78 | banners, awnings |
| cloth ember | 168, 102, 70 | banners, awnings |
| cloth dusk | 84, 94, 128 | banners, awnings |
| cloth lilac | 140, 126, 168 | spirit things |
| lantern | 240, 196, 130 | light panes only (Neon) |
| spirit | 150, 210, 200 | spirit tree, crystals (Neon tips only) |

The code copy of this palette is `Shared.Palette`.

## Glowlings (the exception)

Glowlings are the product, so they follow the Design & Asset Bible's species art (figures 3.1 and
3.2), not the low-poly prop rules above. `GlowlingBodies` sculpts one chibi body per species
from smooth ellipsoids:

- **Chibi proportions:** a big round head on a small body with stubby legs, or one round body
  that is also the head.
- **One shared face:** big glossy eyes with two white highlights, a tiny mouth and soft blush.
  Some species get coloured eyes (owl, lynx, cat, fox) or glowing eyes (raven).
- **One signature glowing feature per species,** in its family's glow colour: Glimmermouse's
  bulb tail, Puffwick's candle, Mushpup's cap spots, Antlerlight's lanterns.
- **Material:** SmoothPlastic. Glass is used for slime, jelly and wing membranes; Neon is used
  only for the glowing feature and the eye highlights.
- **Rarity:** the renderer dresses the accent zones (ears, wings, fins): a rim at Uncommon,
  glass at Rare+, gold at Legendary. It places crowns, wings and inlays from the anchors each
  body returns.
