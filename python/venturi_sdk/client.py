"""
Venturi Edge Streaming HTTP Client for HLS and DASH.
Copyright (C) 2026 Aneesh Krishna.
See LICENSE for copyright and license details.
"""

import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from typing import Dict, List, Any, Optional, Tuple


class VenturiStreamClient:
    """Client for probing, fetching, and validating Venturi HTTP/1.1 media streams."""

    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")

    def _http_get(self, path: str, headers: Optional[Dict[str, str]] = None) -> Tuple[int, Dict[str, str], bytes]:
        url = f"{self.base_url}/{path.lstrip('/')}"
        req = urllib.request.Request(url, headers=headers or {})
        try:
            with urllib.request.urlopen(req) as resp:
                status = resp.status
                resp_headers = {k.lower(): v for k, v in resp.headers.items()}
                body = resp.read()
                return status, resp_headers, body
        except urllib.error.HTTPError as e:
            resp_headers = {k.lower(): v for k, v in e.headers.items()}
            body = e.read()
            return e.code, resp_headers, body

    def fetch_hls_master(self, path: str = "master.m3u8") -> Dict[str, Any]:
        """Fetches and parses an RFC 8216 HLS Multivariant Master Playlist."""
        status, headers, body = self._http_get(path)
        if status != 200:
            raise RuntimeError(f"Failed to fetch HLS master: HTTP {status}")

        text = body.decode("utf-8")
        lines = [line.strip() for line in text.split("\n") if line.strip()]

        variants = []
        i = 0
        while i < len(lines):
            line = lines[i]
            if line.startswith("#EXT-X-STREAM-INF:"):
                inf = line[len("#EXT-X-STREAM-INF:"):]
                uri = lines[i + 1] if i + 1 < len(lines) else ""
                variants.append({"info": inf, "uri": uri})
                i += 2
            else:
                i += 1

        return {
            "status": status,
            "raw_text": text,
            "version": 7 if "#EXT-X-VERSION:7" in text else None,
            "variants": variants
        }

    def fetch_hls_media(self, path: str = "stream.m3u8") -> Dict[str, Any]:
        """Fetches and parses an RFC 8216 HLS Media Playlist."""
        status, headers, body = self._http_get(path)
        if status != 200:
            raise RuntimeError(f"Failed to fetch HLS media playlist: HTTP {status}")

        text = body.decode("utf-8")
        lines = [line.strip() for line in text.split("\n") if line.strip()]

        segments = []
        init_uri = None
        target_duration = 0
        media_sequence = 1
        is_vod = "#EXT-X-PLAYLIST-TYPE:VOD" in text

        for i, line in enumerate(lines):
            if line.startswith("#EXT-X-TARGETDURATION:"):
                target_duration = int(line.split(":")[1])
            elif line.startswith("#EXT-X-MEDIA-SEQUENCE:"):
                media_sequence = int(line.split(":")[1])
            elif line.startswith("#EXT-X-MAP:URI=\""):
                init_uri = line.split("\"")[1]
            elif line.startswith("#EXTINF:"):
                dur_str = line.split(":")[1].rstrip(",")
                uri = lines[i + 1] if i + 1 < len(lines) else ""
                segments.append({"duration": float(dur_str), "uri": uri})

        return {
            "status": status,
            "is_vod": is_vod,
            "target_duration": target_duration,
            "media_sequence": media_sequence,
            "init_uri": init_uri,
            "segments": segments,
            "concluded": "#EXT-X-ENDLIST" in text
        }

    def fetch_dash_mpd(self, path: str = "manifest.mpd") -> Dict[str, Any]:
        """Fetches and parses an ISO/IEC 23009-1 DASH MPD XML manifest."""
        status, headers, body = self._http_get(path)
        if status != 200:
            raise RuntimeError(f"Failed to fetch DASH MPD: HTTP {status}")

        root = ET.fromstring(body.decode("utf-8"))
        # Strip XML namespaces for simplified traversal
        for elem in root.iter():
            if "}" in elem.tag:
                elem.tag = elem.tag.split("}", 1)[1]

        mpd_type = root.attrib.get("type", "static")
        duration = root.attrib.get("mediaPresentationDuration", "")

        adaptation_sets = []
        for period in root.findall("Period"):
            for adapt in period.findall("AdaptationSet"):
                content_type = adapt.attrib.get("contentType", "")
                mime_type = adapt.attrib.get("mimeType", "")
                reps = []
                for rep in adapt.findall("Representation"):
                    reps.append({
                        "id": rep.attrib.get("id"),
                        "bandwidth": int(rep.attrib.get("bandwidth", 0)),
                        "width": int(rep.attrib.get("width", 0)) if "width" in rep.attrib else None,
                        "height": int(rep.attrib.get("height", 0)) if "height" in rep.attrib else None,
                        "codecs": rep.attrib.get("codecs", "")
                    })
                adaptation_sets.append({
                    "content_type": content_type,
                    "mime_type": mime_type,
                    "representations": reps
                })

        return {
            "status": status,
            "type": mpd_type,
            "duration": duration,
            "adaptation_sets": adaptation_sets
        }

    def fetch_byte_range(self, path: str, start: int, end: int) -> Tuple[int, bytes, str]:
        """Performs an RFC 7233 Byte-Range request against the edge server."""
        headers = {"Range": f"bytes={start}-{end}"}
        status, resp_headers, body = self._http_get(path, headers)
        content_range = resp_headers.get("content-range", "")
        return status, body, content_range
