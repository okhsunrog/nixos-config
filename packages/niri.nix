{ niri-upstream, system }:
niri-upstream.packages.${system}.niri.overrideAttrs (old: {
  # The upstream fileset omits docs, which are included in the feature patch.
  src = niri-upstream;
  patches = (old.patches or [ ]) ++ [
    ../patches/niri/transparent-screen-capture.patch
    ../patches/niri/hide-private-resize-snapshots.patch
    ../patches/niri/hide-private-tab-indicators.patch
  ];
})
