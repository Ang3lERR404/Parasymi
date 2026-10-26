#version 450
//! shadow casters write depth alone.
// a shadow caster writes depth alone (render/light.zig): nothing to shade.
// What casts no shadow is left out by its vertex shader (SHADOW).
void main() {}
