# CMAF Packaging Principles & Media Chunking Architecture

This document describes the Common Media Application Format (ISO/IEC 23000-19) packaging workflows, temporal alignment algorithms, and low-latency delivery strategies implemented in Venturi.

---

## 1. Single-Encode Dual-Delivery Pipeline

Historically, streaming architectures maintained separate packaging pipelines for Apple HLS (MPEG-2 TS segments) and MPEG-DASH (fragmented MP4 segments), doubling storage costs and cache footprint at the edge.

CMAF unifies both formats around fragmented MP4:

```
[ Broadcast TS / MP4 Ingest ]
              |
              v
[ Venturi Transmux Engine ]
              |
              v
+-------------------------------+
|  Shared CMAF Media Fragments  |
|   (init.mp4, chunk-*.m4s)     |
+-------------------------------+
         /              \
        /                \
       v                  v
[ HLS Master/Media ]  [ DASH MPD ]
 (master.m3u8)       (manifest.mpd)
       |                  |
       +---------+--------+
                 |
                 v
   [ Venturi Edge HTTP Server ]
```

A single set of `.m4s` fragments on disk or in the memory ring buffer services both Safari/iOS devices (via HLS) and Chrome/Android/SmartTV devices (via DASH).

---

## 2. Keyframe-Aligned Temporal Chunking

Chunking video without keyframe alignment produces visual corruption, macroblocking, and playback freezes because inter-frame codecs (H.264/H.265) use temporal prediction across frame boundaries.

### 2.1 The Chunking Invariant
Venturi enforces a strict invariant:
> Every media fragment MUST begin with a closed Instantaneous Decoding Refresh (IDR) keyframe.

```
Timeline:
[ IDR 0 ] [ P 1 ] [ B 2 ] ... [ P 29 ] | [ IDR 30 ] [ P 31 ] ... | [ IDR 60 ] ...
|<------- Fragment 1 (2.0s) --------->|<------- Fragment 2 --------->|
```

### 2.2 Audio/Video Cadence Alignment
Video frames arrive at discrete frame intervals (e.g. 33.33 ms for 30 fps, 16.66 ms for 60 fps), while AAC audio frames arrive at discrete sample counts (1024 samples at 44.1 kHz = 23.22 ms per frame).

Because audio and video frame durations are incommensurate, naive slicing produces clock drift. Venturi computes:

$$\text{chunk\_start\_ms} = \text{rescale\_time}(\text{video\_start\_pts}, 90000, 1000)$$
$$\text{chunk\_end\_ms} = \text{chunk\_start\_ms} + \text{rescale\_time}(\text{video\_dur}, 90000, 1000)$$

Audio samples whose presentation times fall into $[\text{chunk\_start\_ms}, \text{chunk\_end\_ms})$ are grouped with the corresponding video chunk. Over continuous 24/7 streams, drift remains strictly bounded under a single audio frame ($< 23 \text{ ms}$).

---

## 3. 64-Bit Timeline Management

Broadcasters frequently encounter timestamp discontinuities caused by:
1. Ad insertion and upstream splicers.
2. Hardware encoder restarts.
3. 33-bit hardware clock wrapping.

Venturi tracks continuity by establishing a monotonic anchor:

$$\text{continuous\_pts}_{n} = \text{continuous\_pts}_{n-1} + \Delta\text{pts}$$

When $\Delta\text{pts} < 0$ (e.g. clock rollover from $2^{33}-1$ to 0):

$$\Delta\text{pts}_{\text{compensated}} = \Delta\text{pts} + 2^{33}$$

This ensures that the `baseMediaDecodeTime` in `tfdt` is strictly non-decreasing, fulfilling the requirements of modern media player decoders.
