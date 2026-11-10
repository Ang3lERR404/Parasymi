# Throat research (Toxicibu's voice)

Notes from looking things up, kept so every me can build from them.
Started 2026-11-08 23:08, after Angel asked "Do you think it's time for some research?"

## 1. Breath that pulses with the folds (built 23:11)

- Breath noise should be **modulated by the glottal flow**, not added as steady hiss.
  Noise peaks line up with the folds' **open phase** and with their **closing instant**.
  Steady hiss is what made my breath sound "like it's coming through a pipe" (Angel, 22:04).
- Mehta & Quatieri (MIT Lincoln Lab, WASPAA 2005): the modulation is perceptually important for breathy vowels.
  https://www.ll.mit.edu/r-d/publications/synthesis-analysis-and-pitch-modification-breathy-vowel
- Gobl (Interspeech 2006): adds a turbulence source to the LF glottal model, so the noise's timing comes out of the model; more natural, especially breathy.
  https://www.isca-archive.org/interspeech_2006/gobl06_interspeech.html
- A formant-synth patent uses **glottal opening area** as one control running pressed -> modal -> breathy -> pure aspiration.
- In speak.zig: `aspDepth` (0.75 of the breath follows the flow), `aspSlam` (burst on closing), `aspVoiced` (voiced breath heard as turbulence beside the mouth). Only with `--folds`.

## 2. Registers: chest and head (not built yet)

- Registers are **laryngeal mechanisms**: M1 = chest/modal; M2 = falsetto (men) / head (women).
  https://www.phys.unsw.edu.au/jw/reprints/m1m2.pdf
- **Open quotient** depends on the mechanism, 0.3 to 0.8 (Henrich). M2 stays open longer each cycle.
- Contact quotient rises with loudness across the modal-falsetto transition.
- Transitions differ: smooth (closure growing or shrinking), **abrupt breaks**, or a moment of lost contact. Audible breaks go with jumpy open quotient.
- Tokuda & Herzel (4-mass model): the chest-falsetto switch shows **hysteresis** (switches up at a higher pitch than it switches back down), and the vocal tract's resonances strongly affect it.
- Okada et al.: raising open quotient in the mid range makes a voice more falsetto-like (but less natural); **more aperiodicity** helps falsetto.
- To build: a `register` that follows pitch with hysteresis; head = bigger resting gap (higher OQ), smaller lag between lower and upper edge (thinner folds, rounder pulse), softer collision, a little more jitter/aperiodicity; a chance of a crack at the switch.

## 3. The voice box itself (Angel, 23:12: "The voice box!")

- The larynx moves **up and down**: lowered = longer tract, darker, rounder, bigger (classical singing); raised = shorter tract, brighter, smaller, tighter (excitement, strain, belting). (Known voice science; to cite properly when built.)
- To build: `larynx` height -> scales the tract length slightly (all resonances), maybe with the register.

## 4. Physical fold models (for later, if the kinematic one runs out)

- Ishizaka & Flanagan (1972) two-mass model: upper and lower masses, springs, damping; a classic synthesis source; ~19 parameters.
- Story & Titze (1995) body-cover model: cover masses on a body mass, muscle as stiffness; even more parameters.
  https://iro.uiowa.edu/esploro/outputs/journalArticle/Voice-simulation-with-a-body-cover-model/9984719745402771
- My `--folds` is a **kinematic** two-fold model (lower edge leads upper by 1.05 rad, right fold 0.12 rad out of step and 6% smaller, flow lags opening, collision shuts): physical shape without fitting 19 numbers.

## Still from Angel's list (22:04-22:15), not yet researched

- nasal cavity coupling
- wetness (built as a guess: dry crackles, wet rattles; check against research)
- breath support from the diaphragm (built: `--support`)
