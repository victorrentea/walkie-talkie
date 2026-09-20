# projectM 4.1.7, prebuilt for the native MilkDrop halo

`lib/libprojectM-4.a` + `lib/libprojectM_eval.a` are built from the upstream
`libprojectM-4.1.7` source tarball (github.com/projectM-visualizer/projectm,
tag v4.1.7) with one patch, `target-fbo.patch`: 4.1.7 hard-binds framebuffer 0
for its final pass, and this app has no default framebuffer — it renders off
screen. The patch makes the engine bind whatever `PROJECTM_TARGET_FBO` names.

Build (macOS 15, Apple clang 17, arm64):

```
tar xf libprojectM-4.1.7.tar.gz && cd libprojectM-4.1.7
patch -p0 < ../target-fbo.patch
cmake -S . -B build-static -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_PLAYLIST=OFF -DENABLE_SDL_UI=OFF -DENABLE_SYSTEM_GLM=OFF \
  -DENABLE_SYSTEM_PROJECTM_EVAL=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_INSTALL_PREFIX=$PWD/prefix-static
cmake --build build-static -j && cmake --install build-static
cp prefix-static/lib/libprojectM-4.a build-static/vendor/projectm-eval/projectm-eval/libprojectM_eval.a lib/
cp -R prefix-static/include/projectM-4 ../../Sources/CProjectM/include/
```

The headers under `Sources/CProjectM/include/projectM-4` are the same install's.
`Package.swift` links both archives statically (`-DPROJECTM_STATIC_DEFINE`),
plus `c++`, OpenGL and IOSurface. Nothing is fetched at build time.
