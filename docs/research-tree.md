# The research tree

The gardener's understanding, drawn as a living tree. Press **T** and it
fills the screen, the world paused behind it. It starts as a tiny sprout
in the soil, and every study known grows it, crown and roots alike, until
it stands full. The code is `src/game/hud/research.zig`; the painting and
the node looks are distance fields in `engine/shaders/ui.frag`.

## What it should feel like
Cozy, magical, bright and calm: a small world of its own you tend and
watch grow. A look at it tells how far the garden has come.

## The stage
- **Full screen**, paused. Drag to look round (the orbit button anywhere,
  or the use button on the backdrop; the left stick on a pad); the wheel
  or the zoom keys zoom about the cursor.
- Until it is moved by hand, the view fits what has grown, easing as it
  grows, the title band along the top kept clear. Opening it again fits
  it afresh.
- **Background**: a flat painting in the main menu's style. The dark laid
  in broad strokes, a warm light pooled over the soil as over the sleeping
  wolf, the moon low behind. Petals, small whole flowers, seeds on their
  fluff, leaves and pollen drift down through it. Below a tufted moss
  line, the earth in strata and pebbles.

## The shape
Nothing is placed by hand. Every rule works from the prerequisites, so a
new study needs no layout.

- **Host**: a study grows from its deepest prerequisite (the first among
  equals), or off the trunk if it has none. Its **ring** is how many
  limbs out from the trunk it is.
- **Crown**: a dome over the trunk's top. Each study fills a sector of it
  as wide as the tips it carries, its children splitting that sector
  between them; it stands at its ring's distance out.
- **Limbs** leave their host part way along it (the trunk's limbs low at
  the dome's sides, high for the one straight up), set out along the
  host's heading, curve to their tips, and twist a little. A limb's
  children leave it in turn, the one nearest upright lowest, so none
  crosses another.
- **Roots** match the crown: every study grown sends a root down under
  the soil, mirroring its limb, as far below as the limb reaches above.
- **Growth**: the whole tree scales from a sprout to full size with the
  share of studies known (faster early). Limbs thicken with all they
  carry (the pipe rule: a limb's area is the sum of its children's), bark
  turning from young green to old brown; the trunk flares into its roots.

## The studies on it
Each is drawn as its **lineage** (taken from what it lets be woven, else
from its host; a study's def can set it outright):

| Lineage | Its node |
|---|---|
| symbiotic | a flower: a bud in green sepals opening into five petals round its stamens |
| parasitic | a gall: a veined, breathing bladder ringed with hooked thorns, its mouth parting on a glow and teeth |
| radiant | light gathered, never grown: crystal fragments settling one by one round a core of light |
| convergent | a braided ring: a green strand and a violet one, over and under, a bloom in its heart once it closes |

Big studies (new structures, species, an event) are drawn larger.

| State | How it shows |
|---|---|
| known | its limb and root fully grown, its node fully open |
| studied | its limb grows out with progress, its node opening at the tip |
| open | a faint shoot to where its tip will be, a closed bud there in a gold glow: the next growth comes out here |
| dormant | the same bud dimmed in mist, once its host is known |
| further | nothing yet |

## Pointing and choosing
Hovering a study names it beside its node. Clicking one studies it and
flies the view to it, its card beside it: the icon of what it lets be
woven, its name and what it does, what each unit eats and how long, its
progress, or what it still waits for. A click on the backdrop lets the
card go.

## Not yet
- The constellate lineage has no studies, so no node look yet.
