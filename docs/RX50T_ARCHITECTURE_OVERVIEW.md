# RX50T Architecture Overview

## 1. Overall Architecture

The current `RX50T` architecture is a trimmed pure-`PL` design, not a continuation of the original `AX7020/Zynq` heterogeneous SoC structure.

Main datapath:

```text
UART RX
-> Parser
-> 8-rule BRAM-backed ACL
-> Crypto Bridge
-> AES/SM4 Core
-> UART TX
```

Auxiliary control/visibility path:

```text
Parser / Top Control
-> Protocol Check
-> Counters
-> Stats Response
-> UART TX
```

## 2. Module Relationships

### UART RX

Role:
- receive bytes from the host PC
- turn asynchronous UART input into an internal synchronous byte stream

Feeds:
- `Parser`

### Parser

Role:
- detect frame header
- parse payload length
- output payload bytes one by one
- raise `frame_done / error`

Feeds:
- `ACL`
- top-level protocol logic

### ACL

Role:
- apply a minimal rule match on the first payload byte
- decide pass-through or block
- currently uses an `8`-entry BRAM-backed rule table

Feeds:
- `Crypto Bridge`

### Crypto Bridge

Role:
- pack incoming `8-bit` data into `128-bit` blocks
- buffer plaintext blocks in a BRAM-backed ingress FIFO
- trigger a single-block crypto worker
- buffer ciphertext blocks in a BRAM-backed egress FIFO
- scatter `128-bit` ciphertext back into `8-bit` UART bytes
- bypass encryption for short control frames
- currently verifies `1 / 2 / 4 / 8` consecutive `128-bit` blocks

Feeds:
- `UART TX`

### AES/SM4 Core

Role:
- perform fixed-key block encryption

Current cores:
- `AES-128`
- `SM4-128`

### UART TX

Role:
- send processed data back to the PC

### Top Control / Counters

Role:
- detect invalid mode selectors
- maintain `total / acl / aes / sm4 / err`
- generate the stats response frame

## 3. Current Protocol Design

Base frame format:

```text
SOF(0x55) + LEN + PAYLOAD
```

### Default SM4 Mode

- `LEN = 16`
- payload is one `SM4` plaintext block

- `LEN = 32`
- payload is two consecutive `SM4` plaintext blocks

- `LEN = 64`
- payload is four consecutive `SM4` plaintext blocks

- `LEN = 128`
- payload is eight consecutive `SM4` plaintext blocks

### Explicit AES Mode

- `LEN = 17`
- payload byte `0` = `0x41 ('A')`
- next `16B` = AES plaintext

- `LEN = 33`
- payload byte `0` = `0x41 ('A')`
- next `32B` = two consecutive AES plaintext blocks

- `LEN = 65`
- payload byte `0` = `0x41 ('A')`
- next `64B` = four consecutive AES plaintext blocks

- `LEN = 129`
- payload byte `0` = `0x41 ('A')`
- next `128B` = eight consecutive AES plaintext blocks

### Explicit SM4 Mode

- `LEN = 17`
- payload byte `0` = `0x53 ('S')`
- next `16B` = SM4 plaintext

- `LEN = 33`
- payload byte `0` = `0x53 ('S')`
- next `32B` = two consecutive SM4 plaintext blocks

- `LEN = 65`
- payload byte `0` = `0x53 ('S')`
- next `64B` = four consecutive SM4 plaintext blocks

- `LEN = 129`
- payload byte `0` = `0x53 ('S')`
- next `128B` = eight consecutive SM4 plaintext blocks

### Block and Error Replies

- ACL block reply: `D\n`
- protocol error reply: `E\n`

### Stats Query

- command: `55 01 3F`
- response: `53 total acl aes sm4 err 0A`

## 4. Module Implementation Ideas

### Parser

- lightweight FSM
- only implements the minimum parsing needed for the current pure-`PL` datapath
- deliberately avoids a full network protocol stack

### ACL

- currently an `8`-entry BRAM-backed matcher
- upgrades the design from a single-rule demo to a small hardware rule engine without growing LUT fan-out

### Crypto Bridge

- avoids complex control protocol
- avoids dynamic key management
- avoids hardware padding
- uses a BRAM-backed block-stream structure:
  - `16B` packer
  - ingress FIFO
  - single-block crypto worker
  - egress FIFO
  - byte scatter
- current verified payload sizes are `16B / 32B / 64B / 128B`

### AES/SM4

- fixed internal test key
- first target is known-vector closure
- after that, the design grows by expanding the bridge, not by bloating the algorithm cores

### Counters and Stats

- all counters stay in a lightweight top-level control block
- keeps the crypto path clean
- gives the host a cheap observability interface

## 5. Why the Design Was Trimmed This Way

The trimming rules are intentional:

- avoid `ARM/PS`
- avoid `DMA/DDR`
- avoid a full protocol stack too early
- first prove the shortest closed loop:
  - input works
  - rule filtering works
  - encryption works
  - output works

This makes the design much better suited to `RX50T` resource and contest constraints.

## 6. Current Conclusion

The system is no longer just a set of isolated modules. It is now a real closed loop:

- UART input works
- parsing works
- ACL works
- AES/SM4 works
- UART output works
- stats readback works
- rule-counter readback works
- BRAM-backed block-stream multiblock encryption is verified through `128B`

Because of that, the current `RX50T` version can already serve as:
- the main contest architecture
- the main technical-document structure
- the board-demo version
