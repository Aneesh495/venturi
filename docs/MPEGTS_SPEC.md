# MPEG-2 Transport Stream Specification Reference

This document describes the ISO/IEC 13818-1 MPEG-2 Systems specification implemented by the Venturi demuxer and stream analysis engine.

---

## 1. 188-Byte Packet Structure

MPEG-2 Transport Stream data is segmented into fixed 188-byte packets:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   Sync 0x47   |T|P|S|       PID (13 bits)     |TSC|AFC|  CC   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  Adaptation Field (Optional)                  |
~                                                               ~
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  Payload Data (up to 184 bytes)               |
~                                                               ~
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 1.1 Header Fields
* **Sync Byte (8 bits)**: Constant value `0x47` (`71` decimal).
* **Transport Error Indicator (TEI, 1 bit)**: Set by physical demodulator when uncorrectable bit errors occur. Venturi drops packets with TEI set.
* **Payload Unit Start Indicator (PUSI, 1 bit)**:
  * For PSI tables: Indicates the payload begins with a 1-byte `pointer_field`.
  * For PES packets: Indicates the packet contains the first byte of a PES header (`0x000001`).
* **Transport Priority (1 bit)**: Stream priority indicator.
* **PID (13 bits)**: Identifies the elementary stream or signaling table.
  * `0x0000`: Program Association Table (PAT).
  * `0x0001`: Conditional Access Table (CAT).
  * `0x0002`: Transport Stream Description Table (TSDT).
  * `0x0010` to `0x1FFE`: Program Map Tables and Elementary Streams.
  * `0x1FFF`: Null packet (stuffing byte padding).
* **Transport Scrambling Control (TSC, 2 bits)**: Scrambling status (`00` for cleartext unencrypted).
* **Adaptation Field Control (AFC, 2 bits)**:
  * `01`: Payload only.
  * `10`: Adaptation field only.
  * `11`: Adaptation field followed by payload.
* **Continuity Counter (CC, 4 bits)**: Increments from 0 to 15 per PID, wrapping to 0. Used to detect packet loss.

---

## 2. Program Specific Information (PSI) Tables

### 2.1 Program Association Table (PAT)
The PAT is transmitted on PID `0x0000`. It lists all broadcast programs within the multiplex:

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| Table ID (0)  |S|0|R|   Section Length        | Transport ID  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|R| Version |C|N|  Section Num  | Last Sec Num  | Program Num   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|R|R|R|         PMT PID (13 bits)               | CRC32 (4 B)   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 2.2 Program Map Table (PMT)
The PMT maps elementary streams to their respective codecs:
* **Stream Types**:
  * `0x1B`: AVC / H.264 Video.
  * `0x24`: HEVC / H.265 Video.
  * `0x0F`: ISO/IEC 13818-7 Audio (AAC ADTS).
  * `0x15`: Timed Metadata (ID3v2 tags).
* **PCR PID**: Specifies which stream carries the reference system clock.

### 2.3 ISO/IEC 13818-1 CRC-32 Checksum
PSI sections conclude with a 4-byte CRC-32 to protect table integrity.
* Generator polynomial: `0x04C11DB7`.
* Initial shift register: `0xFFFFFFFF`.
* Output: unreflected, no final XOR.
Venturi verifies each section CRC before parsing elementary stream descriptors.

---

## 3. Clock Recovery and 33-Bit Timestamps

MPEG-2 Systems defines a 27 MHz System Time Clock (STC):
* **Program Clock Reference (PCR)**:
  $$\text{PCR} = \text{PCR}_{\text{base}} \times 300 + \text{PCR}_{\text{ext}}$$
  where $\text{PCR}_{\text{base}}$ is a 33-bit counter clocked at 90 kHz, and $\text{PCR}_{\text{ext}}$ is a 9-bit counter clocked at 27 MHz.
* **Presentation Time Stamp (PTS) & Decode Time Stamp (DTS)**:
  33-bit counters clocked at 90 kHz ($1 \text{ tick} = 11.11 \mu\text{s}$).
  Encode format in PES header:

```
Byte 0: [ 0 0 1 0 ] [ PTS 32..30 ] [ 1 ]
Byte 1: [ PTS 29..22 ]
Byte 2: [ PTS 21..15 ] [ 1 ]
Byte 3: [ PTS 14..7 ]
Byte 4: [ PTS 6..0 ] [ 1 ]
```
Venturi decodes these 5 bytes into a 64-bit integer, tracking 33-bit rollover (occurring at $2^{33} / 90000 \approx 95443.7 \text{ seconds} \approx 26.5 \text{ hours}$).
