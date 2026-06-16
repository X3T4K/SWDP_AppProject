# NAND Flash Microphone Data Logging Report

This document describes how and where the microphone dBSPL data is serialized, buffered, and logged to the SPI NAND Flash memory in the `MainBoard_Firmware` project.

---

## 1. NAND Flash Memory Layout
The system uses a **Micron MT29F4G01ABAFDWB** (4Gb SPI NAND Flash) configured as follows:
* **Total Blocks:** 2048 blocks
* **Pages per Block:** 64 pages
* **Page Size:** 4096 bytes (data area) + 256 bytes (spare area)
* **Start Block:** `b = 1024` (middle of the memory). Logging starts here to preserve any bootloader or configuration data residing in the lower blocks (0–1023).
* **Bad Block Management:** Done dynamically at boot by scanning all 2048 blocks. Good block indices are populated sequentially in the `bad_blocks` lookup array. Only good blocks are written to or read from.

---

## 2. Sample Packet Layout
Each sample logged is exactly **9 bytes** long (`BYTES_PER_SAMPLE = 9`):

| Offset (Bytes) | Field Name | Type | Description |
| :--- | :--- | :--- | :--- |
| `0` | `hh` | `uint8_t` | Hour (RTC) |
| `1` | `mm` | `uint8_t` | Minute (RTC) |
| `2` | `ss` | `uint8_t` | Second (RTC) |
| `3 - 4` | `sss` | `uint16_t` | Milliseconds (RTC Sub-seconds, Big-Endian) |
| `5 - 8` | `microphone` | `float` | 32-bit floating point dBSPL value (IEEE 754) |

---

## 3. Buffering and Writing Mechanism

To minimize flash wear and write overhead, samples are buffered in RAM and written page-by-page.

### Step 1: Serialization into RAM Buffer
When a new dBSPL sample is calculated, the firmware calls `write_packet()` to serialize the timestamp and float value into a 4096-byte RAM page buffer (`NAND_packet`):
* **Function:** [write_packet()](file:///C:/Users/fanin/SWDP/FirmWare/MainBoard_Firmware/Core/Src/Memory_operations.c#L79-L88)
* **Offset calculation:** `uint32_t offset = sample * 9`

### Step 2: Automatic Page Programming
The index `sample` is incremented. When it reaches **455 samples** (`SAMPLES_PER_PAGE`), the buffer is full:
1. `write_memory()` triggers.
2. The entire 4096-byte page is programmed into the NAND flash at block `bad_blocks[b]` and page `pagina_scritta` via `spi_nand_page_program()`.
3. The page index `pagina_scritta` is incremented.
4. The RAM buffer `NAND_packet` is cleared (`memset` to 0), and `sample` is reset to 0.

### Step 3: Block Erasing and Boundaries
* **Block boundaries:** If `pagina_scritta` reaches **64** (block limit), it resets to 0 and the block index `b` is incremented.
* **Block Erasing:** Because NAND cells must be reset to `1` before programming, whenever we advance to a new block (either during the `write_memory()` wrap-around, or at the start of a session), the firmware calls `spi_nand_block_erase()` on `bad_blocks[b]` to prepare the new block.

### Step 4: Session Stop & Flushing
When the user presses the button to stop acquisition, the acquisition terminates immediately. Since there are usually unwritten samples remaining in the RAM buffer (where `sample < 455`), the EXTI callback calls `flush_memory()`. 
* `flush_memory()` writes the partially filled `NAND_packet` as the final page of the current block and clears the buffer.

---

## 4. Code Architecture & References

The key components of the NAND logging subsystem are spread across the following files:

* **[Memory_operations.h](file:///C:/Users/fanin/SWDP/FirmWare/MainBoard_Firmware/Core/Inc/Memory_operations.h)**
  Defines `BYTES_PER_SAMPLE` (9), `SAMPLES_PER_PAGE` (455), and the `Time_Struct` containing the `sss` millisecond field.

* **[Memory_operations.c](file:///C:/Users/fanin/SWDP/FirmWare/MainBoard_Firmware/Core/Src/Memory_operations.c)**
  Implements `find_bad_blocks()` (block scanner) and `write_packet()` (RAM serialization logic).

* **[SPI_NAND.c](file:///C:/Users/fanin/SWDP/FirmWare/MainBoard_Firmware/Core/Src/SPI_NAND.c)**
  Implements the flash writing pipeline:
  * `write_memory()` (checks page limits, programs cache, and auto-erases new blocks).
  * `flush_memory()` (flushes partially filled buffers on session end).
  * `Debug_Read_And_Print_Nand()` (reads logged pages, deserializes the 9-byte packet, and prints details to console).

* **[main.c](file:///C:/Users/fanin/SWDP/FirmWare/MainBoard_Firmware/Core/Src/main.c)**
  Controls the session state transition (`STATE_IDLE` $\rightarrow$ `STATE_ACQUISITION`). Calls the initial `spi_nand_block_erase()`, triggers the polling sequence, reads subseconds from the RTC, and calls `write_packet()` / `write_memory()`.
