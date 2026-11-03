# More radiant plants (notes, not built)

The radiant lineage designed with the gardener, one question at a time.
Nothing here is in the game yet.

## What every radiant thing keeps
- **Gathered, never grown.** Rigid fragments flying in to a heart, held by
  threads of light (`radiantKit`). No stems, no growth splines, nothing
  scaled in.
- **Pearl with a soap-bubble film.**
- **Act 1 only.** The unforming shatters every one into the strange seed.

## What the lineage is about: light as a field that powers things
Radiance was always meant to power structures. It is the garden's power
grid.
- **Local only.** A structure takes light only from the relays near it;
  a network's blooms do not pool their light.
- **A budget.** Each light source gives so much; every structure drawing
  from it takes a share. Too many on one source and they all slow down.
- **Strength by distance.** Light is strongest close to its relay and
  fades to the field's edge; a structure in the bright middle works
  faster.

## Who does what
- **The gatherer makes light.** Nothing else does.
- **Blooms are relays** (small poles): they carry light, they make none.
- **The diamond is a big relay**: the same, wider and further (its field
  is already 7 tiles to a bloom's 3.5). It no longer stands alone.
- The **driftwisp** (symbiotic) already makes starlight as an item, so no
  radiant plant does that.

## The solcyriphon: the gatherer (new radiant plant)
Named by the gardener: sol (the sun) + Halcyra + siphon.
It drinks starlight straight from the sky. The sun is a star too, so it
works all day and night, but differently:
- **By day:** it gathers widely and spreads decent light round itself.
- **By night:** it focuses its light into one beam, straight down onto
  whatever is directly under it. It hangs high, so something can stand
  beneath it.

What the night beam does depends on what it strikes:
- **A relay** (bloom or diamond): the relay takes the whole beam and
  shares it out through its field.
- **A plant:** overdrive. It grows and yields much faster, and now and
  then yields something rare of its kind; but the beam slowly kills it.
- **Bare moss:** an extremely small chance, each night, that the moss
  turns into a ley line.
- **Bare ground of any other kind:** nothing (to settle).

### Its look (the gardener's pick; built as `radiantKit.solcyriphon`)
A lens, a flower facing up, and a touch of jellyfish:
- **Lens:** a flat ring of facets round a glowing heart.
- **Flower:** petals rising round the lens, open to the sky.
- **Jellyfish:** loose threads of light trailing beneath.
- **By day:** petals wide open, threads drifting loose, light spread round
  it in scattered motes.
- **By night:** the petals fold up tight, the threads draw in under the
  lens, the heart burns brighter and smaller, and one beam falls straight
  down from it onto what is below.

## What draws on the light
- **The vesper** still needs radiance to live, and takes its share of the
  budget like any structure.
- **The arsthraxia needs light to study.** It is the one structure that
  lives on past the unforming and needs it before; once the unforming has
  evolved it into a convergent structure, it is freed and studies without
  light.
- Almost everything else dies at the unforming too (symbiotic and
  parasitic alike wither), so the symbiotic and parasitic structures may
  lean on radiance freely. The convergent ones (polyp, weftstone,
  driftbraid, monfris, Vultrixi) live on and never need it.

## How a powered structure shows it
Every boosted structure wears the same sign:
- **A halo crown** of radiant fragments gathers over it while it is
  powered and comes apart in the dark. There are a few set designs; each
  structure is given one at random when it is put down.
- **Ley-blue leaves:** the brighter its light, the more of its leaves
  turn the magical blue of the ley lines, from the crown downward.

Settled in the build ([visual.md](visual.md#the-sign-of-light)): four
crown designs (diadem, circlet, orrery, lotus), picked by the structure's
seed. Crowned and blue: germinator, root-digger, loomfern, gathering
crown, sap cache, arsthraxia (until it evolves), sporecaster (having no
leaves, its fronds turn), lithophage (its crystals glow blue from the top
down, and the blue creeps out along its runners and their cracks toward
the nodes; its crown rises as its coral grows on, `crownAt`). Blue only:
conduits and braided conduits. A structure that only looks lit (`.looks`:
the sap cache, the conduits) draws no light, and is lit wherever light
reaches it.

## The structures, one by one
- **Germinator:** a boost: it weaves faster in light (it comes before
  any light, so it can never need it). The first to wear the sign.
- **Root-digger:** a boost: it digs faster in light.
- **Loomfern:** a boost: it weaves fibre faster in light.
- **Gathering crown:** a boost: it gathers its bed faster in light.
- **Lithophage:** a boost: it drains faster in light. The gardener finds
  it basic as it is, look and work alike, and is reworking it: it is the
  root-digger's upgrade. It sends tendrils out over a radius, each
  digging into a node and pulling from it, and refines what comes up its
  roots so each unit drawn yields more than the root-digger's would.
  It grows: it starts reaching a little way and reaches further the
  longer it lives, its body getting bigger as it does (grown on along
  its skeleton, never scaled up whole). It never stops: like the mist
  tree, it grows slower and slower forever.
  Its look: **stone coral**, a branching pale growth half plant, half
  mineral, spreading wider as it grows, crystals budding on its
  branches. Light bounces off the crystals and through them, so it is
  lovely in the sun and in its own halo's light. Its tendrils leave it
  under the ground (a line of cracks, a faint glow showing through) and
  surface further out, creeping over the ground as pale coral runners
  with small crystals budding along them, to dig into each node.
  Powered, it wears the halo crown; having no leaves, its ley-blue goes
  to its crystals (glowing blue from the top down, the brighter its
  light) and out along its runners toward the nodes.
- **Ganglion:** untouched by light; works as it does. Its look is to
  change: **a brain**, a folded pale knot with the items it holds seen
  inside, glowing as they travel, its nerves branching out to its
  neighbours like a neuron's.
- **Sporecaster:** needs light at both ends: it casts no spores in the
  dark, and spores land only in a lit sporecaster; over a dark one they
  hang and wait for its light.
- **Conduit, braided conduit, sap cache:** untouched in function. In
  light they still take on the look, for beauty alone: conduits and
  braided conduits only turn ley-blue (no halo over a line of them); the
  sap cache wears the halo crown too.

## Overdrive's rare yields
The plants a beam can find in act 1: lumenroot, thornleech, hollowheart,
driftwisp, vesper, confluence (blooms are relays; the mire lily and moss
creeper come after the unforming, when the beam is gone).
- **Most give a sunlit version of their usual yield** (sunlit essence,
  sunlit convergence essence): worth several of the plain kind, good
  wherever it is.
- **The driftwisp and the vesper give something of their own**, the two
  nearest the sky:
  - **Driftwisp: starglass**, clear crystal, needed to weave the greater
    radiant things (diamonds, a new radiant plant's seed).
  - **Vesper: evening silk**, threads of light, woven into the radiant
    structures' halos and a new radiant plant.
- **A research on the side** lets a plant under the beam live longer
  before overdrive kills it: a buffer, never a cure (the light guard is
  the cure).

## Three more radiant plants
The grid has a maker (solcyriphon), carriers (bloom, diamond) and users.
Three more fill what is missing: one **stores** light, one **shapes** it,
one **guards** it.

### The astrocyme: the light store
Named for a cyme, a flower cluster that blooms in order, one flower after
another, as it fills.
- Fills whenever its relays have light to spare, and gives it back
  whenever the structures near it are short, day or night.
- **Look: a spiral bouquet** (built as `radiantKit.astrocyme`). Several flowers fan up from one point,
  winding round a thread of light at rising heights; each flower is one
  share of what it holds. Empty, each flower's petals drift loose round
  it; filling, one flower at a time, from the bottom up, gathers its
  petals and opens; full, all are in bloom. Giving light back, they come
  apart again from the top down.

### The heliocyra: the light shaper
Named helio (the sun) + Halcyra: it turns to the sun's way.
Fields are round; rows want lines. It is turned like a conduit, and:
- **Standing in a field**, it casts that light on as a strip, a tile
  wide, the way it faces.
- **Struck by another shaper's strip**, it bends it round a corner, so
  shapers chain into paths of light.
- **Under a solcyriphon at night**, it takes the falling beam and turns
  it sideways into a strip, far stronger than a field's.
- **Look: a heliotrope** (built as `radiantKit.heliocyra`) with a cut crystal heart: a flower head on a
  neck of light, turning to face the way it sends its strip as a
  sunflower follows the sun; the strip leaves the crystal.

### The halcyra: the light guard
Named for halcyon: calm, sheltered.
- **Stops overdrive from killing.** A plant it guards takes the
  solcyriphon's beam, growing and yielding in overdrive, and never dies of
  it. The research only buys time (a buffer); the guard is the true way.
- **Whom it guards:** put down right beside a plant, it guards that one
  alone. Put down with no plant next to it, it guards every plant within
  a few tiles instead.
- **Look: veil, shield and shepherd in one** (built as `radiantKit.halcyra`). A small radiant flower,
  hooded by a see-through veil like a jellyfish's bell, broad crystal
  petals at the veil's edge tilting into the beam and scattering it off
  as sparkles. Beside a plant it leans over it, its thread of light
  wound round that plant. Alone, the thread opens into a net of light
  spread over the plants round it.

## The numbers (a first balance, to tune in play)
Measured against what is in the game, with the day the gardener wanted:
twice the old one: 600 s a day and night (`sky.dayLen`), stars fall
in about the darkest third of it, a bloom seed is 3 starlight + 1 ley
shard + 2 essence, a driftwisp yields 0.06, a root-digger digs one every
4 s, a branch research is 20 units.

Light is counted in **glow**: one glow runs one small structure at full
boost.

### Making and carrying
| Thing | Light | Reach |
|---|---|---|
| Solcyriphon, by day | 6 glow, shared among the relays within its field and lighting that field itself | 3 tiles |
| Solcyriphon, by night | a 12 glow beam into what is under it | one tile |
| Bloom (relay) | carries up to 4 glow | 3.5 tiles (as now) |
| Diamond (big relay) | carries up to 16 glow | 7 tiles (as now) |
| Astrocyme | holds 720 glow-seconds (6 flowers of 120), takes or gives up to 4 glow | 3 tiles |
| Heliocyra strip | takes up to 3 glow from its field, or the whole 12 glow beam; carries it 8 tiles, losing 10% at each bend | 1×8 tiles |

- **Distance:** a structure gets full light within a tile of its relay,
  fading evenly to a quarter at the field's edge.
- **Budget:** a relay's light is shared out by draw. If its users want
  more than it carries, each gets the same share (carried ÷ wanted).
- **Halcyra:** alone, it guards every plant within 2 tiles.

### Drawing
| User | Draws | In light |
|---|---|---|
| Vesper | 1 | lives (below a quarter of its draw it withers, as now) |
| Germinator | 2 | boost |
| Root-digger | 1 | boost |
| Loomfern | 1 | boost |
| Gathering crown | 2 | boost |
| Lithophage | 3, +1 per tile it reaches past 2 | boost |
| Sporecaster | 2 at each end | needs it |
| Arsthraxia | 3 | needs it (until it evolves) |
| Conduits, sap cache | 0 | looks only |

- **Boost:** full light (strength × share = 1) makes a structure work
  1.5× as fast; less light, less boost, straight down to none.
- **Needing it:** a structure that needs light works at the speed its
  light allows and stops below a quarter.

### Overdrive (the night beam on a plant)
- Grows 3× as fast, yields 3× as much.
- One yield in ten is rare: **sunlit essence** (counts as 3 essence in
  any recipe), **sunlit convergence essence** (counts as 3), **starglass**
  from a driftwisp, **evening silk** from a vesper.
- It costs the plant 0.004 HP a second under the beam, so an unguarded
  plant dies over about a night and a half.
- **Tempered Light** (research, 15 units of 1 starlight + 1 essence,
  opened by the first overdrive) halves the harm: about three nights.
- **Moss:** a 1% chance each night that a mossy tile under the beam
  becomes a ley line. **Any other bare ground:** nothing.

### The lithophage's reach
Grown, it reaches 2 tiles. It reaches one tile further each time its
age triples: 3 tiles after 5 days (50 minutes), 4 after 15, 5 after 45,
and so on, forever. Each unit its tendrils draw refines to 2 (a root-digger's gives
1); a ley shard still gives 3 grit.

### Seeds and research
| Seed | Costs | Opened by |
|---|---|---|
| Solcyriphon | 4 starlight, 2 ley shard, 2 fibre | open from the start (see below) |
| Heliocyra | 1 starglass, 2 starlight, 1 ley shard | **Bent Light**: 15 units of 2 starlight + 1 ley shard, after the first starglass |
| Halcyra | 2 evening silk, 2 essence, 1 fibre | **Halcyon Veil**: 15 units of 1 evening silk + 1 essence, after the first evening silk |
| Astrocyme | 2 starglass, 1 evening silk, 2 essence | **Held Light**: 20 units of 2 starlight + 1 essence, after Bent Light and Halcyon Veil (a branch) |

- **The solcyriphon must be open from the start**, like the bloom: the
  arsthraxia needs light to study, so without one no research can begin.
  It costs more than a bloom, so the first is a real step.
- **The order this makes:** solcyriphon and blooms first; then a
  driftwisp under the beam for starglass (the heliocyra); vespers under
  it for evening silk (the halcyra); both open the astrocyme. The first
  starglass and silk cost a driftwisp's and a vesper's lives, since nothing
  guards them yet.

## Still to decide
- Whether these numbers feel right in play.
