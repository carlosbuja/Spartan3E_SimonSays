## FPGA Simon Game: A Spartan-3E Hardware Implementation 

## Project Overview & Objectives 

This project involves the hardware-level implementation of the Simon memory game on the Spartan-3E FPGA (XC3S500E). The system is engineered to validate user-inputted sequences against hardware-stored arrays generated via pseudo-random logic. The design utilizes a modular Verilog architecture to manage high-speed signal processing and real-time user interface requirements.The primary technical objectives of this implementation include: 

- **Hardware-based Pseudo-Random Generation:** Utilizing  a Linear Feedback Shift Register (LFSR) in the 50 MHz domain to ensure sequence unpredictability through high-frequency entropy sampling. 

- **Real-Time Synchronization:** Implementing a robust  Finite State Machine (FSM) to orchestrate game flow, signal debouncing, and state transitions. 

- **VGA Visual Interface:** Designing a dedicated controller  to drive 640x480 @ 60Hz timing, rendering game states and color-coded feedback on external monitors. 

- **Dynamic Status Display:** Driving an external 16x2  character LCD via a 4-bit data interface to provide real-time telemetry, including scores and level progression. 

- **User Accessibility Logic:** Implementing an "Easy Mode"  featuring a multi-strike counter system for increased fault tolerance. 

## System Versatility & Dual-Mode Operation 

The architecture is designed for dual-output flexibility, ensuring the game is functional across different hardware setups: 

- **VGA Experience:** Provides high-resolution visual feedback  on an external monitor. The system utilizes a 3-bit RGB configuration, enabling an 8-color palette to represent the Simon pads (Red, Green, Blue, and Yellow/Cyan) and UI text. 

- **Stand-alone Mode:** Enables full playability using  only the Spartan-3E Starter Kit's integrated peripherals. Users interact with the game via on-board buttons while observing sequence patterns on the discrete LEDs. 

## Peripheral Mapping for Stand-alone Play 

During execution, the physical inputs are mapped to specific logical values and visual indicators: 

- BTN_WEST (Logic Value 3) corresponds to LED<7>. 

- BTN_NORTH (Logic Value 2) corresponds to LED<6>. 

- BTN_SOUTH_P (Logic Value 1) corresponds to LED<5>. 

- BTN_EAST (Logic Value 0) corresponds to LED<4>.Status and error indicators are handled by the lower LED bank: 

- LED<2:1>: Multi-strike counter (Easy Mode only). 

- LED<0>: Terminal loss indicator. 

## Hardware Configuration & Pin Mapping 

The following table details the physical pin assignments for the XC3S500E, including IO standards and functional descriptions.| Signal Name | FPGA Pin (LOC) | IO Standard | Description/Function || ------ | ------ | ------ | ------ || CLK | C9 | LVCMOS33 | 50 MHz System 

Clock (20 ns Period) || RST | V16 | LVCMOS33 | Global Reset (Rotary Push-button, PULLDOWN) || SW0 | L13 | LVCMOS33 | Game Start / Initiation Switch || SW1 | L14 | LVCMOS33 | Easy Mode (Multi-strike) Toggle || BTN_WEST | D18 | LVTTL | Input: Value 3 (PULLDOWN) || BTN_NORTH | V4 | LVTTL | Input: Value 2 (PULLDOWN) || 

BTN_SOUTH_P | K17 | LVTTL | Input: Value 1 (PULLDOWN) || BTN_EAST | H13* | LVTTL | Input: Value 0 (PULLDOWN) || LED<7:4> | F9, E9, D11, C11 | LVTTL | Sequence and User Input Visualizers || LED<2:1> | E11, E12 | LVTTL | Strike Counter Indicators || LED<0> | F12 | LVTTL | Terminal Game Over / Loss Indicator || HSYNC | F15 | LVTTL | VGA Horizontal Sync (Fast Slew) || VSYNC | F14 | LVTTL | VGA Vertical Sync (Fast Slew) || VGA_R | H14 | LVTTL | VGA Red Channel (1-bit) || VGA_G | H15 | LVTTL | VGA Green Channel (1-bit) || VGA_B | G15 | LVTTL | VGA Blue Channel (1-bit) || LCD_RS | L18 | LVCMOS33 | LCD Register Select || LCD_RW | L17 | LVCMOS33 | LCD Read/Write Control || LCD_E | M18 | LVCMOS33 | LCD Enable Pulse || SF_D<3:0> | M15, P17, R16, R15 | LVCMOS33 | Shared Data Bus (Maps to LCD Bits D7-D4) || SF_CE0 | D16 | LVCMOS33 | StrataFlash Disable (High required for LCD) | 

* _Note: While some project documentation may refer  to pin A18, the UCF designates H13 for BTN_EAST on the standard Spartan-3E Starter Kit revision._ 

## Modular Architecture 

## simon_top 

The top-level integration layer. It manages the instantiation of all sub-modules and signal routing. Crucially, it handles the tri-state logic or disabling of the StrataFlash memory via SF_CE0 to prevent bus contention with the LCD on the shared SF_D<3:0> pins. 

## simon_fsm 

- The core logic engine, implemented as a synchronous Finite State Machine. 

   - **IDLE:** Quiescent state; waits for SW0 high to initiate  system variables. 

   - **GENERATE:** Captures a 2-bit value from the LFSR to  append to the sequence array. 

   - **SHOW_SEQUENCE:** Iterates through the stored array,  driving the LEDs and VGA module. 

   - **USER_INPUT:** Captures debounced button pulses. 

   - **COMPARE:** Validates user input against the sequence  array index. 

   - **NEXT_LEVEL / STRIKE:** A decision branch. If COMPARE  is successful, it increments the ronda_actual (round) counter. If unsuccessful and SW1 is active, it increments the strike counter; otherwise, it triggers a loss. 

   - **GAME_OVER:** Terminal state that resets the game or  holds the final score on the LCD/VGA. 

## vga_simon 

A hardware graphics accelerator that translates FSM state and score data into VGA signals. It implements 640x480 timing at 60Hz. Given the 1-bit per color depth (3-bit total), it renders the game board using a palette of 8 possible colors, ensuring high-contrast feedback for the sequence patterns. 

## debouncer 

Provides signal conditioning for mechanical inputs. The module uses a clock_enable to sample inputs every 5ms (250,000 cycles). It utilizes a 3-stage D-Flip-Flop (Q0, Q1, Q2) chain for **synchronization** to the 50MHz domain and **edge detection** , effectively eliminating metastability and mechanical bounce. 

## LFSR_2bit 

A 2-bit pseudo-random generator. Because this register shifts at 50 MHz, the human interaction delay between IDLE and SW0 activation serves as a high-entropy seed. The FSM takes a "snapshot" of the LFSR during the GENERATE state, ensuring a sequence that is effectively unpredictable to the player. 

## lcd_score 

Drives the 16x2 character LCD via a 4-bit interface. The module specifically maps to the **high nibble (D7-D4)** of the LCD data bus, as the lower nibble is not utilized in this 4-bit mode. 

## Easy Mode & Strike System 

- The strike system, toggled via SW1, provides a hardware-level fault-tolerance mechanism. 

   - **Logic Branching:** In Hard Mode (SW1=0), any mismatch  in the COMPARE state results in an immediate transition to GAME_OVER. 

   - **Strike Tracking:** In Easy Mode (SW1=1), the FSM permits  up to three errors. Mistakes are registered and displayed via LED<2:1>. Upon the third mistake, the logic drives LED<0> high and enters the terminal GAME_OVER state. 

## Technical Specifications 

- **Timing:** 50 MHz Clock (20 ns period); VGA 640x480  @ 60Hz. 

- **Input Requirements:** Active-high logic. All buttons/switches require PULLDOWN resistors and LVTTL or LVCMOS33 IO standards as specified in the UCF. 

- **LCD Interface:** 4-bit mode operation (Data bits D7-D4). 

- **Bus Management:** SF_CE0 must be tied high to disable  StrataFlash and ensure exclusive access to the shared data bus for the LCD. 

- **VGA Output:** 1-bit per color depth (3-bit RGB), driving  standard VGA voltage levels. 

