# Documentation

### COMMUNICATION BRIDGE

```
reg [1:0] sclk_sync, cs_sync;
```

The registers `sclk_sync` and `cs_sync` implement **double-flop synchronization** for the external SPI signals (`sclk` and `cs_n`). Even if the SPI master and the internal peripheral operate at similar frequencies, the clocks are not phase-aligned, meaning the incoming signals must be synchronized to the internal `clk` domain to prevent metastability.

Each synchronizer register stores **two bits**, corresponding to the two most recently sampled values of the external signal. They are initialized to:

- `sclk_sync = 2'b00`
- `cs_sync = 2'b11` (since chip select is active-low)

On every `posedge clk`, the new sampled value is appended:

```
sclk_sync <= {sclk_sync[0], sclk};
cs_sync   <= {cs_sync[0], cs_n};
```

This enables detection of **rising edges**, **falling edges**, and **chip-select activation** through simple bit-pattern comparisons.

---

The SPI logic uses a 3-bit register `byte_cnt` to track the number of bits received within the current byte. Since the system processes only **one byte at a time**, this counter asserts completion once all 8 bits have been shifted in.

The module also contains two 8-bit shift registers:

- `shift_in` — stores the data received from MOSI (and is exposed via `data_in`)
- `shift_out` — contains the byte to be transmitted on MISO

```
reg [2:0] byte_cnt;
reg [7:0] shift_in, shift_out;
reg miso_reg;
assign miso = miso_reg;
assign data_in = shift_in;
```

---

### **SPI Timing Logic: `sclk_rising`, `sclk_falling`, and `cs_active`**

The synchronized SPI signals allow the design to derive the following control events:

- **`sclk_rising`** — SCLK transitions from `0` to `1`
- **`sclk_falling`** — SCLK transitions from `1` to `0`
- **`cs_active`** — chip-select is asserted (`cs_n == 0`)

These signals determine when bits are received or transmitted.

---

### **Main State Machine (`always @(posedge clk or negedge rst_n)`)**

On each rising edge of the internal clock (or falling edge of reset):

#### **1. Reset Condition**

If `rst_n == 0`, all internal registers are set to known values:

- `byte_cnt` resets to `0`
- `shift_in` and `shift_out` clear to `0`
- `miso_reg` outputs `0`

#### **2. Idle State (`cs_active == 0`)**

If reset is not asserted and chip-select is inactive:

- The byte counter is cleared.
- The next transmit byte (`data_out`) is loaded into `shift_out`.
- The first bit to be transmitted (`data_out[7]`) is prepared in `miso_reg`.

This stage prepares the slave before the SPI master begins a transfer.

---

### **3. Active SPI Transfer (`cs_active == 1`)**

When a transaction is active, three possible events occur:

#### **1. `sclk_rising` — Receiving a bit on MOSI**

On the rising edge of SCLK:

- `shift_in` shifts left by one bit.
- The newest MOSI bit is inserted as the least significant bit.
- `byte_cnt` increments.

This corresponds to **data reception**.

#### **2. `sclk_falling` — Sending a bit on MISO**

On the falling edge of SCLK:

- `shift_out` shifts left.
- A `0` is inserted as the LSB.
- `shift_out[6]` is copied into `miso_reg`.

This performs **data transmission**.

#### **3. End-of-Byte Handling (when `byte_cnt == 7`)**

On the rising edge when the last bit of the byte has been received:

- `shift_out` is reloaded with the next `data_out`.
- `miso_reg` is updated with the new MSB (`data_out[7]`).

This supports continuous multi-byte transfers.

---

### **Byte Completion Signal (`byte_sync`)**

The final `always` block generates a single-cycle strobe named `byte_sync` using the internal register `byte_sync_reg`.

A pulse is generated when:

- `cs_active == 1`
- `sclk_rising == 1`
- `byte_cnt == 7`

At this moment, the full 8-bit value in `shift_in` is valid and ready for the downstream logic.

This signal is essential for the component that decodes or processes the received SPI byte.

---

### INSTRUCTION DECODER

The instruction decoder receives bytes from the SPI bridge and interprets them either as **instruction bytes** or **data bytes**, depending on the current internal state. Before implementing the decoding logic, the necessary output registers are defined and connected to their corresponding module outputs through continuous assignments. A single-bit `state` register is also introduced to indicate whether the module is currently processing an instruction (`state = 0`) or receiving the data associated with that instruction (`state = 1`).

```
reg rw_reg;
reg hl_reg;
reg [5:0] addr_reg;
reg [7:0] data_out_reg;
reg [7:0] data_write_reg;
reg write_reg;
reg read_reg;

// 0 = SETUP, 1 = DATA
reg state;

assign data_out   = data_out_reg;
assign data_write = data_write_reg;
assign addr       = addr_reg;
assign read       = read_reg;
assign write      = write_reg;
```

---

### **Decoder Logic Overview**

The main decoding logic resides inside an `always` block that executes on each **posedge** of `clk` or **negedge** of `rst_n`.  
Its behavior can be summarized as follows:

---

### **1. Reset Handling**

If the reset signal is asserted (`rst_n == 0`):

- All internal registers (including control signals and outputs) are cleared to default values.
- The state machine is returned to the **SETUP** state (`state = 0`).

This ensures deterministic behavior when starting the system or recovering from reset.

---

### **2. Normal Operation**

When reset is not asserted, the decoder performs the following steps each cycle:

- `write_reg` and `read_reg` are cleared to `0` at the beginning of the cycle.
- A `case` statement selects the appropriate behavior depending on the current value of the `state` register.

---

### **State 0 – Instruction Interpretation**

When `state == 0`, the incoming byte is treated as an **instruction byte**. Its internal structure is decoded into the following fields:

- `rw_reg` – operation type (read or write), extracted from the **MSB**
- `hl_reg` – selects high or low byte (if addressing partial registers)
- `addr_reg` – 6-bit register address

The decoder then behaves differently depending on whether the operation is a **read** or a **write**:

#### **Write Operation (`rw_reg == 1`)**

- No data needs to be returned to the external master yet.
- `data_out_reg` is cleared to `0` (dummy value).

#### **Read Operation (`rw_reg == 0`)**

- The decoder loads the current value from `data_read` into `data_out_reg`, making it available for transmission back to the SPI master.
- `read_reg` is asserted (`1`), signaling that a read cycle is requested by the system.

After processing the instruction byte, the state machine transitions to:

```
state <= 1;    // proceed to DATA state
```

---

### **State 1 – Data Handling**

When `state == 1`, the decoder handles the **data byte** associated with the previously decoded instruction.

#### **Write Operation**

Only write operations require active handling in this state:

- The incoming data byte (`data_in`) is stored in `data_write_reg`.
- This value is exposed through the `data_write` output, enabling the addressed register to update its contents.
- `write_reg` is asserted (`1`), informing the system that valid write data is available.

#### **Read Operation**

Read operations do **not** require explicit action in this state; by the time state 1 is reached, the read data has already been prepared during state 0.


#### **State Reset**

At the end of state 1:

```
state <= 0;    // return to SETUP and wait for next instruction
```

The decoder waits for the next `byte_sync` signal from the SPI bridge, indicating that a new instruction byte has been received and is ready for processing.

---

# Implementation Notes for `regs.v` + `counter.v`

## Register Block Implementation (`regs.v`)

This section describes only the implementation details specific to my design, not the generic architecture already provided in the assignment.

### Internal Structure

All user-visible registers (`PERIOD`, `COUNTER_EN`, `COMPARE1/2`, `PRESCALE`, `UPNOTDOWN`, `PWM_EN`, `FUNCTIONS`) are stored using Verilog `reg` variables with their exact logical width.  
Two additional internal elements are used:

- `count_reset_sh` – a 2-bit internal countdown for generating the two‑cycle active pulse for `COUNTER_RESET`.
- `data_read` – combinational multiplexer output for read operations.

### Addressing Choices

- The module receives a 6-bit address.
- 16-bit registers are split into LSB/MSB across consecutive addresses.
- Unused addresses have no effect on write and return `0x00` on read.

### COUNTER_RESET Mechanism

Writing to address `0x07` loads `count_reset_sh = 2'b11`, which decrements each clock.  
`count_reset` is high whenever the countdown is non‑zero, producing an exact two‑cycle pulse.

### Write Logic Details

Only meaningful bits are stored:

- Single-bit registers (`en`, `upnotdown`, `pwm_en`) use `data_write[0]`
- `FUNCTIONS` uses `data_write[1:0]`
- 16‑bit registers follow LSB/MSB splitting.

### Read Logic Details

The read path is a combinational multiplexer:

- 16‑bit registers return LSB/MSB halves
- Single‑bit registers are zero‑extended
- `COUNTER_RESET` always returns `0x00`
- Invalid addresses return `0x00`

### Reset Behaviour

Registers initialize to deterministic defaults:  
counter disabled, prescaler zero, comparators zero, PWM disabled, up-count direction.

---

## Counter Implementation (`counter.v`)

### Internal State and Prescaler

Two 16‑bit registers:

- `count_val` – main up/down counter
- `presc_cnt` – internal prescaler counter

A combinational wire computes the prescaler target:

```
prescale_target = 1 << prescale;
```

This implements frequency division by `2^PRESCALE`.

### Reset and Enable Behaviour

- Asynchronous reset clears both registers.
- `count_reset` has highest priority and resets only counter-related registers.
- When `en = 0`, `count_val` holds its value while `presc_cnt` resets.

### Prescaler and Counting Logic

If `PRESCALE = 0`, the counter ticks every clock.  
If `PRESCALE > 0`, the prescaler increments until reaching `prescale_target − 1`, then resets and produces one tick.

### Up/Down and Period Handling

On each tick:

- **Up-counting**: increment until reaching `period`, then wrap to `0`
- **Down-counting**: decrement until `0`, then wrap to `period`

`COMPARE1` and `COMPARE2` are not used in this module; they are consumed by the PWM block.

---

# PWM Generator (`pwm_gen.v`) – Implementation Documentation

## Module Implementation

### 1. Bit Extraction from `functions` Register
```verilog
wire align_left_right = functions[0];
wire aligned_mode = functions[1];
```

* `align_left_right` controls whether the signal is left-aligned or right-aligned.
* `aligned_mode` controls the PWM operating mode (aligned or unaligned).

---

### 2. Overflow/Underflow Detection
```verilog
wire overflow_event = (count_val == period);
wire wrap_event = (count_val == 0 && last_count_val == period);
wire overflow_underflow = overflow_event || wrap_event;
```

* `overflow_event` = 1 when the counter reaches the `PERIOD` value.
* `wrap_event` = 1 when the counter has wrapped from `PERIOD` to 0.
* `overflow_underflow` = combines both events and marks **the beginning of a new period**.

---

### 3. Storing Previous Counter State
```verilog
reg [15:0] last_count_val;
reg last_overflow_underflow;
```

* The counter value and overflow state from the previous step are preserved to detect **the exact moment when a new period begins**.

---

### 4. Retaining Active Configurations at Period Start
```verilog
reg[15:0] active_period;
reg[15:0] active_compare1;
reg[15:0] active_compare2;
reg active_align_left_right;
reg active_aligned_mode;
```

* These registers store the current configuration that will be used **until the next overflow**.
* Update occurs only **on the rising edge of overflow/underflow**:
```verilog
if (overflow_underflow && !last_overflow_underflow) begin
    active_period <= period;
    active_compare1 <= compare1;
    active_compare2 <= compare2;
    active_align_left_right <= align_left_right;
    active_aligned_mode <= aligned_mode;
end
```

---

### 5. PWM Signal Generation

#### 5.1. PWM Disabled
```verilog
if (!pwm_en)
    pwm_out <= pwm_out;
```

* If `pwm_en` = 0, the PWM signal remains in its current state.

---

#### 5.2. Aligned Mode (`aligned_mode == 0`)

* **Left-aligned (`align_left_right == 0`)**
```verilog
if (overflow_underflow && !last_overflow_underflow)
    pwm_out <= 1'b1;
else if (count_val == active_compare1)
    pwm_out <= 1'b0;
```

* At the beginning of the period &rarr; `pwm_out` = 1
* When the counter reaches `COMPARE1` &rarr; `pwm_out` = 0

* **Right-aligned (`align_left_right == 1`)**
```verilog
if (overflow_underflow && !last_overflow_underflow)
    pwm_out <= 1'b0;
else if (count_val == active_compare1)
    pwm_out <= 1'b1;
```

* At the beginning of the period &rarr; `pwm_out` = 0
* At `COMPARE1` &rarr; `pwm_out` = 1

---

#### 5.3. Unaligned Mode (`aligned_mode == 1`)
```verilog
if (overflow_underflow && !last_overflow_underflow)
    pwm_out <= 1'b0;
else if (count_val == active_compare1)
    pwm_out <= 1'b1;
else if (count_val == active_compare2)
    pwm_out <= 1'b0;
```

* At the beginning of the period → `pwm_out` = 0
* At `COMPARE1` &rarr; `pwm_out` = 1
* At `COMPARE2` &rarr; `pwm_out` = 0

---

### 6. Reset and Synchronization

* At asynchronous reset (`rst_n == 0`) &rarr; all registers and the PWM signal are initialized to 0.
* All operations occur on the rising edge of the `clk` clock.

---

### 7. Summary

* The code synchronizes PWM configurations at **the beginning of the period**.
* Supports **left/right aligned** and **aligned/unaligned mode**.
* PWM management is based on `COMPARE1` and `COMPARE2` values and counter state.