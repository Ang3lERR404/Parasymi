# Game Project — Context File

## The core idea
**Parasymi**, a game all focused around plants (and mushrooms) intermingled with magic that have only gained sentience and sapience through eons of evolutions where humans and animals have all gone extinct, they yearn for the stars and more, and to get there, rely heavily on the first iteration of the player's character, who only came to life after a long development period, he does not know why the factory **must grow**, but it claws at him, it's his instinct, the very core of his being. The player's character is an anthropomorphic, plant + mushroom based hyena, his design is heavily intertwined with vines, flowers, leaves, branches, sap and more.

## The core concept
Parasitic vs Symbiotic, where these two eventually converge, stay within that convergant state and evolve into the celestial

## The divergent Designs (current design kits in mind):
- **Symbiotic**: Contributory, lush greenery with beautiful flowers and elegant designs
- **Neutral**: Purely for the sake of merging the two, design is TBD.
- **Parasitic**: Self-explanatory, uncanny symmetry, cage like designs, writhing, alien (not hostile)

## Who I Am
- I am Ang3l404ERR, I have been an artist since 2011.
- (personal) I am kinky and I do not shy away from sexual expression. I **embrace** it, the way I see it: Humans ***are*** animals, we should be able to express ourselves in any way that is never harmful towards anyone else, no harm? no fowl, why hide or punish something that is innate to our nature?.
- I have been programming since 2016 and I am 26 years old.
- I have ADHD, math is not intuitive for me. I learn best with ELI5-style explanations.
- I need to see the "why" before the "what." No "trust me, the formula is X."
- The only math I'm good with is: addition, subtraction and some multiplication.
- I work in Zig 0.16.0. I am NOT switching to C++ (footguns), NOR Rust. I'm fully committed to Zig and eventually GLSL.
- I want to exploit Zig's metaprogramming, comptime, generics, and expressiveness to the fullest extent.
- GLSL is NOT my strongsuit, I would like to get to the point of a professional.
- I like hacky (validated) workarounds that do not sacrifice on the games core fundementals, functionality or speed.

## The Project
- A fully procedural, asset-free, 3D game (plus it's engine) (Factorio-like)
- Everything is computed: geometry, animation, textures, world layout
- Speed-critical: procedural animation, world gen, tile + chunk, high fidelity
- Target platform: Windows (WASAPI for audio)
- Rendering: Vulkan
- Windowing: GLFW

## absolutely 0 dependencies outside of the given:
- std
- zig-wasapi
- Vulkan-zig
- zglfw

## Hardware
- GPU: GIGABYTE RTX 4060 Ti 16GB
- System RAM: 32GB
- CPU: Ryzen 5

## Learning Plan (Phase 0 → 5)
- **Phase 0 (current):** Setup of windowing and basic rendering
- **Phase 1:** Vectors, matrices, quaternions, chunk coordinate math
- **Phase 2:** SDFs, marching cubes, raymarching
- **Phase 3:** Noise (Perlin/Simplex/FBM/domain warp), Poisson disk, cellular automata
- **Phase 4:** Splines, slerp, IK (CCD/FABRIK), blend trees
- **Phase 5:** Spatial hashing, LOD, SIMD, data-oriented design
- **Phase 6:** Making the game based off of a planned idea.
- **Phase 7:** Designing the ui, controls, synthesized audio, visuals and more.

### Where I Am Right Now
- **Phase 0**
- Every function gets a `zig test` with known-correct values

## Project rules + styling
- get it CORRECT and OPTIMIZED first.
- absolutely NO snake_case, SCREAMINGCASE, `zig fmt`, useless-newlines, nested if's.. it compromises readability, 4 spaces, tabs.
- ONLY 2 spaces, `if (...) return EXPRESSION;` where-ever applicable
- every file must be/assisting the launch point for every new one.
- `this`,`This` is better than `self`.
- every declaration must be abbreviated up until the last word: `thisDeclIsLong` -> `tDILong`.
- absolutely unforgiving towards the communities code styling/conventions, it's "ugly", and it "wastes time".
- Documentation is non-negotiable.
- Art design is non-negotiable.

## Key Conventions (to be filled in as I decide)
- Matrix layout: TBD
- Coordinate system: TBD
- Unit system: TBD
- Quaternion convention: TBD
- Event system: TBD

## What "Done" looks like
- `Vec(N)` comptime-generic with dot, cross, normalize, lerp, length, distance
- `Mat(N,C)` with translate, rotate (axis-angle + quaternion), scale, multiply, transpose, inverse
- Quaternion type with fromAxisAngle, toMat3, toMat4, slerp, multiply
- Chunk coordinate transforms (world ↔ chunk ↔ local),
- footprint, footprintless, structures that can either occupy 1x1 or 6x6 or 0,
- randomly seeded world generation,
- beautifully animated and modular UI, inventories, grand structures, modular structures, "mega-bases", "power" networks, player centric bootstraping -> intense automation
- blueprints, beauty AND function
- impressive visuals, synthesized audio and more
- a proper Day and Night cycle
- proper fluid dynamics + a weather system that the player initiates themselves
- research triggered World events, evolutions/upgrades
- meta-progression
- All tested with known values via `zig test`
- The actual plants that the player seeds to eventually all the grand designs must grow, animate and respond to various things