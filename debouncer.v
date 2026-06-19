// =========================================================================
// debouncer.v
// Generates a clean, 1-cycle pulse when a physical button is pressed.
// System Clock: 50 MHz -> clock_enable triggers every ~5 ms (250,000 cycles)
// =========================================================================

module debouncer (
    input  clk,       // 50 MHz system clock
    input  btn_in,    // Raw, noisy signal from the physical button
    output btn_pulse  // Clean 1-cycle pulse generated upon press
);
    wire slow_clk_en;
    wire Q0, Q1, Q2;
    reg  btn_prev = 0;

    // Instantiate the clock enable generator (5ms pulse)
    clock_enable u_clken (
        .clk_50M(clk),
        .slow_clk_en(slow_clk_en)
    );

    // 3-Stage Shift Register using D Flip-Flops
    // These flip-flops only update their state every 5ms, filtering out 
    // the rapid mechanical "bouncing" of the physical button.
    dff_en d0 (.clk(clk), .en(slow_clk_en), .D(btn_in), .Q(Q0));
    dff_en d1 (.clk(clk), .en(slow_clk_en), .D(Q0),     .Q(Q1));
    dff_en d2 (.clk(clk), .en(slow_clk_en), .D(Q1),     .Q(Q2));

    // The button is considered stably pressed only if the last two 5ms samples are HIGH
    wire btn_clean = Q1 & Q2;

    // Edge Detection: Delay the clean signal by one clock cycle
    always @(posedge clk)
        btn_prev <= btn_clean;

    // The output pulse is HIGH only on the exact rising edge of the clean signal
    assign btn_pulse = btn_clean & ~btn_prev;

endmodule

// =========================================================================
// Sub-module: clock_enable
// Generates a 1-cycle enable pulse every 5 milliseconds.
// =========================================================================
module clock_enable (
    input  clk_50M,
    output slow_clk_en
);
    reg [17:0] counter = 0;
    
    // At 50 MHz, each cycle is 20ns. 
    // 250,000 cycles * 20ns = 5,000,000 ns = 5 milliseconds.
    always @(posedge clk_50M)
        counter <= (counter >= 249999) ? 0 : counter + 1;

    // Assert the enable signal for exactly 1 clock cycle when the counter peaks
    assign slow_clk_en = (counter == 249999) ? 1'b1 : 1'b0;
endmodule

// =========================================================================
// Sub-module: dff_en
// D Flip-Flop with an Enable input.
// =========================================================================
module dff_en (
    input  clk, 
    input  en, 
    input  D,
    output reg Q = 0
);
    always @(posedge clk)
        if (en) Q <= D; // Only latches the new data when the enable pulse is HIGH
endmodule