`timescale 1ns / 1ps
// =============================================================
// simon_top.v  -  Complete top-level for the Simon game
// FPGA : Spartan-3E Starter Kit (XC3S500E) @ 50 MHz
// =============================================================

module simon_top (
    input  wire       CLK,          // 50 MHz  (C9)
    input  wire       RST,          // active-high global reset
    input  wire       SW0,          // SW[0] starts the game  (L13)
    input  wire       SW1,          // SW[1] easy mode / 3 strikes (L14)
    input  wire       BTN_WEST,     // player value 3  (D18)
    input  wire       BTN_NORTH,    // player value 2  (V4)
    input  wire       BTN_SOUTH_P,  // player value 1  (K17)
    input  wire       BTN_EAST,     // player value 0  (A18)
    
    output wire [7:0] LED,          // Board LEDs
    
    // --- VGA Ports (Adjusted to 1-bit per color for Spartan-3E) ---
    output wire       HSYNC,
    output wire       VSYNC,
    output wire       VGA_R,
    output wire       VGA_G,
    output wire       VGA_B,
    
    // --- LCD Ports (Spartan 3E) ---
    output wire       LCD_RS,
    output wire       LCD_RW,
    output wire       LCD_E,
    output wire [3:0] SF_D,         // Shared data (StrataFlash/LCD)
    output wire       SF_CE0        // Disable StrataFlash
);

    // ---------------------------------------------------------
    // Internal Signals (Wires)
    // ---------------------------------------------------------
    wire p_west, p_north, p_south, p_east;
    wire [3:0] current_score;

    // ---------------------------------------------------------
    // 1. Debouncers (Clean 1-cycle pulses)
    // ---------------------------------------------------------
    debouncer u_deb_west  (.clk(CLK), .btn_in(BTN_WEST),    .btn_pulse(p_west));
    debouncer u_deb_north (.clk(CLK), .btn_in(BTN_NORTH),   .btn_pulse(p_north));
    debouncer u_deb_south (.clk(CLK), .btn_in(BTN_SOUTH_P), .btn_pulse(p_south));
    debouncer u_deb_east  (.clk(CLK), .btn_in(BTN_EAST),    .btn_pulse(p_east));

    // ---------------------------------------------------------
    // 2. Main FSM (The Brain of the Game)
    // ---------------------------------------------------------
    simon_fsm u_fsm (
        .clk      (CLK),
        .rst      (RST),
        .sw0      (SW0),
        .sw1      (SW1),
        .btn_west (p_west),
        .btn_north(p_north),
        .btn_south(p_south),
        .btn_east (p_east),
        .leds     (LED),
        .score    (current_score)
    );


    // ---------------------------------------------------------
    // 3. Updated VGA Controller (Expanded Connections)
    // ---------------------------------------------------------
    vga_simon u_vga (
        .clk_50mhz (CLK),
        .rst       (RST),
        .leds      (LED),           // Sends the ENTIRE bus to read strikes and defeats
        .sw1       (SW1),           // Sends the mode switch
        .score     (current_score), // Sends the round to write on the screen
        .hsync     (HSYNC),
        .vsync     (VSYNC),
        .vga_r     (VGA_R),
        .vga_g     (VGA_G),
        .vga_b     (VGA_B)
    );

    // ---------------------------------------------------------
    // 4. LCD Controller (Score)
    // ---------------------------------------------------------
    lcd_score u_lcd (
        .clk       (CLK),
        .score     (current_score),
        .lcd_rs    (LCD_RS),
        .lcd_rw    (LCD_RW),
        .lcd_e     (LCD_E),
        .sf_d      (SF_D),
        .sf_ce0    (SF_CE0)
    );

endmodule