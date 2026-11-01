//! what the moisture field's readers share (render/passes/moisture.zig): how long a step may be, how thick cloud must grow before it rains, how deep pooled water stands.

// the longest step taken at once (s), so a hitch never blows the field away
const float MOISTURE_MAX_STEP = 0.1;
// a frame's step `dt` (s) as the field takes it
float moistureStep(float dt) { return clamp(dt, 0.0, MOISTURE_MAX_STEP); }
// how thick cloud must grow before it rains (moisture.frag): more than one
// nebularbor's leaves breathe, a grove's; the air draws cloud this thick as
// heavy as it comes (air.glsl)
const float MOISTURE_RAIN_AT = 1.4;
// how deep a unit of pooled water stands (world units): the field's alpha
// past 1 is water pooled on the ground (moisture.frag), the ground wet
// through under it
const float MOISTURE_POOL_DEPTH = 0.08;
// the ground's wetness at `a` (the field's alpha), 0 dry .. 1 wet through
float moistureWet(float a) { return min(a, 1.0); }
// how deep the water pooled on it stands at `a` (world units)
float moisturePool(float a) { return max(a - 1.0, 0.0) * MOISTURE_POOL_DEPTH; }
