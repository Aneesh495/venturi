# ISO Base Media File Format & CMAF Specification Reference

This document outlines the ISOBMFF (ISO/IEC 14496-12) and CMAF (ISO/IEC 23000-19) box structures, layouts, and constraints implemented by the Venturi media engine.

---

## 1. Box Container Architecture

Every ISOBMFF atom conforms to the base 8-byte box header:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           Box Size                            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           Box Type (FourCC)                   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                     Extended Size (if size == 1)              |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           Payload Data                        |
~                                                               ~
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

FullBoxes extend standard boxes by prepending a 1-byte version and 3-byte flag bitmask:

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    Version    |                     Flags                     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

---

## 2. CMAF Track Initialization Segment (`init.mp4`)

A valid CMAF Initialization Segment must contain exactly one `ftyp` box and one `moov` box, with no media data (`mdat`) boxes.

```
+-- ftyp (File Type Box)
|     major_brand = 'cmf2'
|     minor_version = 0
|     compatible_brands = ['cmf2', 'iso6', 'mp41']
|
+-- moov (Movie Container Box)
      +-- mvhd (Movie Header Box, Version 0/1)
      |     timescale, duration, next_track_id
      |
      +-- mvex (Movie Extends Box)
      |     +-- mehd (Movie Extends Header Box, optional)
      |     +-- trex (Track Extends Defaults for Track 1)
      |     +-- trex (Track Extends Defaults for Track 2)
      |
      +-- trak (Video Track)
      |     +-- tkhd (Track Header: width, height, track_id=1)
      |     +-- mdia (Media Information)
      |           +-- mdhd (Media Header: timescale, language)
      |           +-- hdlr (Handler Reference: handler_type='vide')
      |           +-- minf (Media Information Container)
      |                 +-- vmhd (Video Media Header)
      |                 +-- dinf (Data Information Container with dref/url)
      |                 +-- stbl (Sample Table Container)
      |                       +-- stsd (Sample Description: avc1/hev1 + avcC/hvcC)
      |                       +-- stts (Empty Decoding Time-to-Sample)
      |                       +-- stsc (Empty Sample-to-Chunk)
      |                       +-- stsz (Empty Sample Sizes)
      |                       +-- stco (Empty Chunk Offsets)
      |
      +-- trak (Audio Track)
            +-- tkhd (Track Header: track_id=2, volume=1.0)
            +-- mdia
                  +-- mdhd (Media Header: timescale=48000, language)
                  +-- hdlr (Handler Reference: handler_type='soun')
                  +-- minf
                        +-- smhd (Sound Media Header)
                        +-- dinf
                        +-- stbl
                              +-- stsd (Sample Description: mp4a + esds)
                              +-- stts / stsc / stsz / stco (Empty tables)
```

---

## 3. CMAF Media Fragment Segment (`.m4s`)

Each media segment encapsulates exactly one CMAF fragment consisting of `styp`, `moof`, and `mdat`:

```
+-- styp (Segment Type Box)
|     major_brand = 'cmf2'
|     minor_version = 0
|     compatible_brands = ['cmf2', 'iso6', 'msdh', 'msix']
|
+-- moof (Movie Fragment Box)
|     +-- mfhd (Movie Fragment Header: sequence_number)
|     +-- traf (Track Fragment Box)
|           +-- tfhd (Track Fragment Header: track_id, flags)
|           +-- tfdt (Track Fragment Decode Time: baseMediaDecodeTime)
|           +-- trun (Track Fragment Run: sample_count, data_offset, sample_table)
|
+-- mdat (Media Data Box)
      [Raw sample bytes: NAL units prefixed by 4-byte lengths or raw AAC frames]
```

### 3.1 Track Fragment Decode Time (`tfdt`)
The `tfdt` box establishes continuous playback across segment boundaries without gaps or overlaps. Venturi emits Version 1 (64-bit unsigned integer) decode times to prevent 32-bit rollover during live broadcasts:

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   Version (1) |                     Flags (0)                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|             baseMediaDecodeTime (High 32 bits)                |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|             baseMediaDecodeTime (Low 32 bits)                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 3.2 Track Fragment Run (`trun`)
The `trun` box contains individual sample metadata. Venturi optimizes storage by selectively enabling table flags:
* `0x000001` (`data-offset-present`): Points to the payload start inside `mdat`.
* `0x000100` (`sample-duration-present`): Custom per-sample durations.
* `0x000200` (`sample-size-present`): Exact byte length of each sample.
* `0x000400` (`sample-flags-present`): Keyframe and dependency markers (`is_difference_sample`).
* `0x000800` (`sample-composition-time-offsets-present`): Signed PTS minus DTS delta for B-frame presentation reordering.
