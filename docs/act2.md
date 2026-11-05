# Act 2, as the gardener shaped it

What the gardener decided for act 2 and the constellate lineage, in the
order it was decided, with why. [design.md](design.md#act-2-the-star-hyena)
says how the game does it now; [tendril.md](tendril.md) has the tendril's
exact numbers. Where this and the code disagree, the gardener's word here
is what the code must come back to.

## When it happens
- Act 2 comes **only after the unforming** ([unforming.md](unforming.md)).
  The wolf, with the convergent lineage alone, makes the world rain and
  storm, then takes root and becomes a tree himself, the garden's tree:
  already made of wood and vines, he does not merge into some other tree,
  he *becomes* one (the gardener). Not built yet: the rooting itself, and
  how it is set off in play (still to shape). `--act2` starts there (the
  unforming run through, the fallen strange seed in his keeping).
- **The transformation, step by step** (the gardener's):
  1. The wolf digs into the ground with his claws and plants his feet
     into the new holes.
  2. Slowly but surely he morphs, and morphs, growing more tree-like by
     the second, his own design fading away.
  3. Once not a single trace of his design is left, fragments float from
     his leaves: no beating, still, as light.
  4. They begin to beat, faster and faster, until they converge,
     building the star hyena.
  5. The hyena takes the place the wolf once filled.
  The star hyena is no stranger replacing the wolf: he is born from him,
  the stilled light of the wolf-tree's leaves finding its heartbeat again
  (the gardener: "exactly on point").
- **What sets it off** (the gardener's): the storm. The convergent trees
  the wolf plants bring back the rain, and the storm spire (the
  ionizer's kin, made for storms) brings the storm. Once the storm has
  come, the player chooses when the wolf plants himself, and the choice
  is offered without saying what will happen: "It lets the player
  choose, but it does not tell them what is about to occur on purpose."
- **How the choice is offered** (the gardener: "Something innocent is the
  best illusion"): during a storm, one quiet prompt, innocent on its face
  (say `{@action} rest here`), that says nothing of what follows. The
  exact words are still the gardener's to pick.
- **The wolf is not the player in act 2.** Never write "the wolf" as the
  one who plants, builds or draws tendrils there.

## The star hyena (the new gardener)
- A living constellation: an **anthropomorphic hyena made of stars**
  (he/him), a **dense** constellate web. A new animal, not the wolf.
- **Upright like a person**, whole legs **dangling**. He **never walks**:
  he hovers over the ground, leaning into his motion; his steps are silent.
- A few **convergent flowers in his "hair"** (his mane).
- Like the wolf: **pectorals, a gut and rear lobes**, as big as the wolf's
  for his height, made of constellate webs.
- **Small points** so his shape reads finely; a **short muzzle**.
- The first sketch was "a really rough sketch"; what fixed it: real hyena
  anatomy, a smoother body (28 curved limbs, skinned, one bone each), less
  glare (each limb's lights dimmed where they crowd) and idle drift.
- Look: `--samples=constellateHyena`; in play, `--act2`.
- **Convergent flowers turn to face him** as he drifts past, like
  sunflowers to the sun (the gardener: "that is perfect"). Not built yet.

## The convergent lineage: his hands
- The convergent lineage serves the star hyena as **his hands**: its
  weavers (the monfris and kin) weave for him what he cannot by hand.
- **Constellate things never feed on convergent essence.** The
  gardener: "the constellate are the stars given form, their sacrecy is
  unimposed by usual challenges" (*sacrecy*: their own word for
  scarcity and sacredness at once).

## The dish: gathering the scattered starlight
- At the unforming the starlight dispersed thin across the sky, so
  something must gather it: a new constellate part, **the dish**, cupped
  like an arctic poppy's flower (which tracks the sun and focuses its
  warmth). Alone it does nothing, as every constellate part.
- **Combo: dish + stem + core** makes a light-gathering plant (the core is
  merely a flower's base, its head): the stem lifts it, it slowly follows
  the stars through the night, focusing their faint scattered light into
  the core. Tendrils carry that light out to the other constellate things.
- *Its name* (the gardener): **Halnoctsidirfilharactuum** (hal- halo,
  noct- night, sidir- star, fil- phial or dish by sound).
- Not part of the star caller. Still to shape: ~~its name~~, its numbers
  and look.

## The strange seed
- Its first model was a placeholder. It is a **crystal husk with a web
  inside** (a see-through `husk` part, clear glass with glowing cracks).
- Planted by the hyena (put down by his hand), it makes **enough fragments
  for a core and four petals**: one yielder. The first pace was too slow;
  it is now **one fragment every 3 s**, 50 in all.

## Building and parts
- **He builds, then snaps:** he gathers fragments (a click takes one),
  builds a part from **ten fragments** in his own hands (the belly shows
  his recipes, not the wolf's), puts it down, and parts join by their
  combo rules.
- **Every constellate part is a placeable structure** (core, petal, leaf,
  bud, stem). Each stands on its own and has combo rules.
- A core put down **stands alone**, and its placement preview shows the
  core alone (it once showed the whole yielder: wrong).
- **Petals** can be put down on their own; within 4 tiles of a core short
  of petals they **drift over and merge** with it. Four make **the
  yielder** (four, not five).
- **The sprig:** a stem has three joints. Leaves put down near it fasten
  at its lowest, then highest joint; a bare stem put down after fastens at
  its middle as its branch.
- **Four buds on a bare stem make the heart.**
- Animation as parts drift over and merge is **polish, for later**
  ("feels decent, there needs to be animation though").

## The heart
- Its story plays out (bound, rising, blooming into its layered rose),
  then it **waits for four petals**; with them its chain reaction runs and
  it **settles into a builder**.
- **Fragments are its material:** fed ten, it forms a whole part on top of
  its rose (petal, leaf, bud, core, stem in turn), which rests there until
  taken.

## The flow: tendrils
- "The flow" is **tendrils only**, drawn by **dragging a path** (hold V,
  sweep from one structure to another, or back to himself).
- Braided of fragments, they carry what their start hands over to their
  end, one at a time.
- **The look is the tendril sketch, exactly**
  (`--samples=constellateTendril,constellateTendrilGround,constellateTendrilArc`,
  numbers in [tendril.md](tendril.md)). Twice a version drawn tile by tile
  was rejected ("it still compromises on the look of the path"). The rule
  from the gardener's reference:
  - **One continuous flow, like a current of water**, along the whole
    path. **No per-tile animation.**
  - **Any height.** Each tile of the path can start and end at any height,
    and the whole curve adjusts through them, rising or falling. While
    drawing, the wheel sets the tile under the cursor and those swept
    after it.
  - **Never below the ground**: that would look strange. On the ground is
    the lowest.
- Accepted: "looks right" (2026-11-02).

## The star caller (being shaped with the gardener, 2026-11-04)
At the unforming each starlight patch shoots its light into the sky, where
it becomes stars, and the patch stays dark. The star caller calls it back:
a grand constellate structure, unlocked by a great deal of research, that
pulls the stars down into a dark patch. Planned step by step, as the heart
was; nothing here is built.
- **Modular, a formation:** constellate modules laid out in a set pattern
  round the dark patch, and a **key** at its centre that decides what the
  whole does (the calling key relights the patch; other keys may come
  later). Inspired by a multiblock with a swappable centre piece; the look
  is wholly constellate (star-web, plexus fragments, its blue).
- **It grows in stages** once the formation is complete and the key set,
  an event watched through a night like the heart's story.
  1. **Awakening:** the formation links up.
  2. **Unravelling:** the modules untangle themselves into long strands
     that rise into the air between the ground and the sky.
  3. **The weaving:** the strands circle round the patch, and as they spin
     they weave together into one shape: **a ring of flowing energy, a
     halo almost**, one half turning clockwise and the other
     counter-clockwise, constellate flowers blooming among its rungs. Both
     ways at once: an inner and an outer ring turning against each other,
     rungs of light between them, and an upper and a lower layer of that
     turning against each other too.
  4. **The gathering:** a single petal from each flower drifts to the
     centre of the halo, more and more of them, until they almost make
     light; they spin faster and faster, exponentially, as they almost
     unfurl, but they never combine into one.
  5. **The beam:** just then light comes down from the heavens into the
     centre, a faint thin beam at first that quickly intensifies into one
     condensed beam crashing down into the patch, and the patch relights.
- **Afterwards everything stays standing:** the formation, the turning
  halo with its flowers, the petals spinning at its centre and the beam,
  for as long as the patch is lit.
- Still to shape: its name, its modules and their pattern, its key, its
  research and cost, its sound, and the numbers.

## Not built yet
In [todo.md](todo.md#act-2).
