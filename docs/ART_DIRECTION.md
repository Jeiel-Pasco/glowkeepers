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
