//! what the moisture field's passes share (render/passes/moisture.zig): how long a step may be.

// the longest step taken at once (s), so a hitch never blows the field away
const float MOISTURE_MAX_STEP = 0.1;
// a frame's step `dt` (s) as the field takes it
float moistureStep(float dt) { return clamp(dt, 0.0, MOISTURE_MAX_STEP); }
