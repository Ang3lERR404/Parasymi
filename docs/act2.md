# Act 2, as the gardener shaped it

What the gardener decided for act 2 and the constellate lineage, in the
order it was decided, with why. [design.md](design.md#act-2-the-star-hyena)
says how the game does it now; [tendril.md](tendril.md) has the tendril's
exact numbers. Where this and the code disagree, the gardener's word here
is what the code must come back to.

## When it happens
- Act 2 comes **only after the unforming** ([unforming.md](unforming.md)).
  The wolf, with the convergent lineage alone, makes the world rain and
  storm, then roots himself into the garden's tree. Not built yet: the
  rooting itself. `--act2` starts there (the unforming run through, the
  fallen strange seed in his keeping).
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
