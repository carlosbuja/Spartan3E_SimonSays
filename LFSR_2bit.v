// lfsr_2bit.v
// Generates a 2-bit pseudo-random value (0..3) only when en = 1

module lfsr_2bit (
    input  wire       clk,
    input  wire       reset,
    input  wire       en,          // Enable signal to shift the LFSR
    output wire [1:0] rand_val     // 2-bit random output mapped to the 4 LEDs
);

    // 8-bit shift register
    reg [7:0] lfsr_reg;
    
    // Feedback polynomial: x^8 + x^6 + x^5 + x^4 + 1
    // This specific combination of taps (XOR gates) guarantees a "maximal-length sequence",
    // meaning it will cycle through 255 unique pseudo-random states before repeating.
    wire feedback;
    assign feedback = lfsr_reg[7] ^ lfsr_reg[5] ^ lfsr_reg[4] ^ lfsr_reg[3];

    always @(posedge clk or posedge reset) begin
        if (reset)
            // An LFSR must NEVER be initialized to all zeros. 
            // Because 0 XOR 0 is 0, it would stay stuck at zero forever.
            lfsr_reg <= 8'b10000001;   // Non-zero seed
        else if (en)
            // Shift left by 1 bit and insert the calculated feedback at the LSB (Least Significant Bit)
            lfsr_reg <= {lfsr_reg[6:0], feedback};
    end

    // Take the lowest 2 bits as our random number (0, 1, 2, or 3)
    assign rand_val = lfsr_reg[1:0];

endmodule