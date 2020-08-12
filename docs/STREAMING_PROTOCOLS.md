# Streaming Protocols: RFC 8216 HLS & ISO/IEC 23009-1 DASH

This document specifies the manifest structure, syntax, and live sliding window synchronization implemented by Venturi for HTTP Live Streaming (HLS) and Dynamic Adaptive Streaming over HTTP (DASH).

---

## 1. RFC 8216 HTTP Live Streaming (HLS)

Venturi authors Version 7 HLS playlists incorporating CMAF byte-range and fragmented MP4 indexing.

### 1.1 Multivariant Master Playlist (`master.m3u8`)
The master playlist coordinates adaptive bitrate variants:

```m3u8
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS

#EXT-X-STREAM-INF:BANDWIDTH=4500000,AVERAGE-BANDWIDTH=4000000,RESOLUTION=1920x1080,FRAME-RATE=30.000,CODECS="avc1.640028,mp4a.40.2"
v1080p/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,AVERAGE-BANDWIDTH=2200000,RESOLUTION=1280x720,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2"
v720p/stream.m3u8
```

Key tags:
* `#EXT-X-INDEPENDENT-SEGMENTS`: Guarantees that every segment starts with a keyframe and can be decoded independently.
* `CODECS`: Informs the client decoder of exact SPS profile/level constraints without probing data bytes.

### 1.2 Media Playlist (`stream.m3u8`)

#### VOD Profile
```m3u8
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:1
#EXT-X-MAP:URI="init.mp4"

#EXTINF:2.000,
chunk-1.m4s
#EXTINF:2.000,
chunk-2.m4s
#EXT-X-ENDLIST
```

#### Live Sliding Window Profile
In live mode, `#EXT-X-PLAYLIST-TYPE:VOD` and `#EXT-X-ENDLIST` are omitted. As new segments arrive, older segments roll off the top of the playlist, and `#EXT-X-MEDIA-SEQUENCE` increments monotonically:

```m3u8
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:4
#EXT-X-MAP:URI="init.mp4"

#EXTINF:2.000,
chunk-4.m4s
#EXTINF:2.000,
chunk-5.m4s
#EXTINF:2.000,
chunk-6.m4s
```

---

## 2. ISO/IEC 23009-1 DASH MPD

Venturi authors dynamic (Live) and static (VOD) XML Media Presentation Descriptions.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
     profiles="urn:mpeg:dash:profile:isoff-live:2011,urn:com:dashif:ingest:2017"
     type="static"
     mediaPresentationDuration="PT60.000S"
     minBufferTime="PT2.0S">
  <Period id="1" start="PT0.0S">
    <AdaptationSet id="1" contentType="video" mimeType="video/mp4">
      <SegmentTemplate media="chunk-$Number$.m4s"
                       initialization="init.mp4"
                       timescale="90000"
                       startNumber="1">
        <SegmentTimeline>
          <S t="0" d="180000" r="29" />
        </SegmentTimeline>
      </SegmentTemplate>
      <Representation id="v1" bandwidth="4500000" width="1920" height="1080" codecs="avc1.640028" />
    </AdaptationSet>
  </Period>
</MPD>
```

### 2.1 SegmentTimeline Run-Length Compression
Rather than listing 10,000 separate `<S>` tags for an extended live event, Venturi groups consecutive segments of identical duration using the repeat count attribute `r`:

```xml
<SegmentTimeline>
  <S t="0" d="180000" r="299" />
</SegmentTimeline>
```
This achieves over 99% reduction in manifest payload size, minimizing network overhead for edge delivery.
