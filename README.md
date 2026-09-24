# Pixel Physics Sandbox

Android-first 2.5D pixel-physics sandbox built without a 3D engine.

## Visual invariant

The room art is the supplied reference composition, preserved as a nearest-neighbour 256×256 WebP so the app stays visually locked to the original pixel-art scene. Dynamic bodies are rendered on top in the same raster/isometric language.

## Physics model

Bodies live on a 2D floor plane `(u, v)` plus scalar height `z`. Projection is isometric-like:

- `x = originX + (u-v) * isoX`
- `y = originY + (u+v) * isoY - z * isoZ`

This gives depth, jumps, shadows and ordering without a 3D mesh/scene engine.

## Controls

- Drag an object: move it on the floor plane.
- Release after dragging: throw it.
- Tap empty floor: spawn a cube.
- Hold empty floor: spawn a ball.
- Double-tap an object: jump impulse.

## Build

GitHub Actions builds `app-debug.apk` and uploads it as the `pixel-physics-apk` artifact.
