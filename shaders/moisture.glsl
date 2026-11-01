//! what the moisture field's readers share (render/passes/moisture.zig): how long a step may be, how thick cloud must grow before it rains.

// the longest step taken at once (s), so a hitch never blows the field away
const float MOISTURE_MAX_STEP = 0.1;
// a frame's step `dt` (s) as the field takes it
float moistureStep(float dt) { return clamp(dt, 0.0, MOISTURE_MAX_STEP); }
// how thick cloud must grow before it rains (moisture.frag); the air draws
// cloud this thick as heavy as it comes (air.glsl)
const float MOISTURE_RAIN_AT = 1.6;
