! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Program Specific Information (PSI) decoder for Program Association Table (PAT)
! and Program Map Table (PMT) with ISO/IEC 13818-1 CRC-32 integrity verification.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.order sequences vectors venturi.common.crc venturi.common.utils
venturi.mpegts.constants venturi.mpegts.packet ;
IN: venturi.mpegts.psi

! Program Association Table entry mapping program number to its PMT PID.
TUPLE: pat-entry
    { program-number integer read-only }
    { pmt-pid integer read-only } ;

: <pat-entry> ( program-number pmt-pid -- entry )
    pat-entry boa ;

! Elementary stream entry in the Program Map Table.
TUPLE: pmt-stream
    { stream-type integer read-only }
    { elementary-pid integer read-only }
    { descriptors byte-array read-only } ;

: <pmt-stream> ( stream-type pid desc -- stream )
    pmt-stream boa ;

! Complete Program Map Table structure for a single broadcast service.
TUPLE: pmt-info
    { program-number integer read-only }
    { pcr-pid integer read-only }
    { streams vector read-only } ;

: <pmt-info> ( program-number pcr-pid streams -- info )
    pmt-info boa ;

! Extracts the section byte slice from a TS payload, handling pointer_field.
:: extract-psi-section ( payload pusi? -- section-bytes/f )
    payload length 4 < [ f ] [
        0 :> start-off!
        pusi? [
            0 payload nth :> ptr-field
            1 ptr-field + start-off!
        ] when

        start-off payload length 3 - < [
            start-off payload nth :> table-id
            payload start-off 1 + read-be16 0x0FFF bitand :> section-len
            start-off section-len 3 + + :> section-end

            section-end payload length <= [
                start-off section-end payload subseq-safe :> sec-bytes
                sec-bytes verify-mpeg2-crc [ sec-bytes ] [ f ] if
            ] [ f ] if
        ] [ f ] if
    ] if ;

! Parses a Program Association Table (PAT) section.
:: parse-pat-section ( section-bytes -- pat-entries )
    V{ } clone :> out
    section-bytes length 12 < [ out ] [
        0 section-bytes nth TABLE_ID_PAT = not [ out ] [
            8 :> curr!
            section-bytes length 4 - :> loop-end  ! exclude 4-byte CRC
            [ curr 4 + loop-end <= ] [
                section-bytes curr read-be16 :> prog-num
                section-bytes curr 2 + read-be16 0x1FFF bitand :> pmt-pid
                prog-num zero? not [  ! ignore network PID (prog 0)
                    prog-num pmt-pid <pat-entry> out push
                ] when
                curr 4 + curr!
            ] while
            out
        ] if
    ] if ;

! Parses a Program Map Table (PMT) section.
:: parse-pmt-section ( section-bytes -- pmt-info/f )
    section-bytes length 16 < [ f ] [
        0 section-bytes nth TABLE_ID_PMT = not [ f ] [
            section-bytes 3 read-be16 :> prog-num
            section-bytes 8 read-be16 0x1FFF bitand :> pcr-pid
            section-bytes 10 read-be16 0x0FFF bitand :> prog-info-len

            12 prog-info-len + :> es-start!
            section-bytes length 4 - :> es-end
            V{ } clone :> streams

            [ es-start 5 + es-end <= ] [
                es-start section-bytes nth :> s-type
                section-bytes es-start 1 + read-be16 0x1FFF bitand :> e-pid
                section-bytes es-start 3 + read-be16 0x0FFF bitand :> es-info-len

                es-start 5 + :> desc-start
                desc-start es-info-len + es-end min :> desc-end
                desc-start desc-end section-bytes subseq-safe :> desc-bytes

                s-type e-pid desc-bytes <pmt-stream> streams push
                desc-end es-start!
            ] while

            prog-num pcr-pid streams <pmt-info>
        ] if
    ] if ;

! High-level PAT extractor from a TS packet.
:: parse-pat-packet ( packet -- entries )
    packet pid>> PID_PAT = [
        packet payload>> packet pusi>> extract-psi-section [
            parse-pat-section
        ] [ V{ } clone ] if*
    ] [ V{ } clone ] if ;

! High-level PMT extractor from a TS packet given expected PMT PID.
:: parse-pmt-packet ( packet expected-pid -- pmt/f )
    packet pid>> expected-pid = [
        packet payload>> packet pusi>> extract-psi-section [
            parse-pmt-section
        ] [ f ] if*
    ] [ f ] if ;
