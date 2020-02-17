! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Declarative stack-based ISOBMFF box serializer, FullBox generators,
! and hierarchical container assembly combinators.

USING: byte-arrays byte-vectors kernel locals math math.order
sequences venturi.common.utils venturi.isobmff.constants ;
IN: venturi.isobmff.box-writer

! Serializes a standard Box header followed by its raw payload bytes.
:: serialize-box ( fourcc payload -- box-bytes )
    payload length 8 + :> total-size
    total-size <byte-vector> :> buf
    buf total-size push-be32
    buf fourcc push-be32
    buf payload push-bytes
    buf >byte-array ;

! Serializes a 64-bit largesize Box header for payloads exceeding 4 GiB.
:: serialize-large-box ( fourcc payload -- box-bytes )
    payload length 16 + :> total-size
    total-size <byte-vector> :> buf
    buf 1 push-be32
    buf fourcc push-be32
    buf total-size push-be64
    buf payload push-bytes
    buf >byte-array ;

! Serializes an ISO FullBox with 8-bit version and 24-bit flags.
:: serialize-full-box ( fourcc version flags payload -- box-bytes )
    payload length 12 + :> total-size
    total-size <byte-vector> :> buf
    buf total-size push-be32
    buf fourcc push-be32
    buf version push-u8
    buf flags push-be24
    buf payload push-bytes
    buf >byte-array ;

! Serializes a structural container box by concatenating serialized child boxes.
:: serialize-container-box ( fourcc children-bytes-seq -- box-bytes )
    children-bytes-seq concat :> concatenated
    fourcc concatenated serialize-box ;

! File Type Box (ftyp) builder.
:: build-ftyp-box ( major-brand minor-version compatible-brands -- box-bytes )
    compatible-brands length 4 * 16 + <byte-vector> :> payload
    payload major-brand push-be32
    payload minor-version push-be32
    compatible-brands [ payload swap push-be32 ] each
    FOURCC_FTYP payload >byte-array serialize-box ;

! Segment Type Box (styp) builder for CMAF and DASH segments.
:: build-styp-box ( major-brand minor-version compatible-brands -- box-bytes )
    compatible-brands length 4 * 16 + <byte-vector> :> payload
    payload major-brand push-be32
    payload minor-version push-be32
    compatible-brands [ payload swap push-be32 ] each
    FOURCC_STYP payload >byte-array serialize-box ;

! Media Data Box (mdat) builder wrapping sample payload chunks.
:: build-mdat-box ( sample-data -- box-bytes )
    FOURCC_MDAT sample-data serialize-box ;

! Free/Skip Space Box builder creating padding blocks.
:: build-free-box ( total-size -- box-bytes )
    total-size 8 - 0 max <byte-array> :> padding
    FOURCC_FREE padding serialize-box ;
