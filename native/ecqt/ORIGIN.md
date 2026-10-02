Vendored from https://github.com/havoksahil/ecqt at 85b1010bf400c32f846f49d780d51a820d2b2877
PFFFT pinned at d7a4c0206a29423478776d6b23a37bbb308f21d5 (license in source).
Local corrections: scan all N frequency bins when sparsifying, destroy kernel FFT setup, rename cabs to avoid C built-in collision.
Kernels are centered in their common FFT buffer so all pitches refer to the same playback time.
Raised nonzero capacity from 32767 to 4194304 (indices already int) to avoid silently dropping lower-note kernels. Corrected WTYPE macro spelling.
