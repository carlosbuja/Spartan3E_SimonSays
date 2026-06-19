`timescale 1ns / 1ps

module simon_fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire       sw0,        // SW0=1 starts the game
    input  wire       sw1,        // SW1=1 activates Easy Mode (3 strikes)
    input  wire       btn_west,   // 1-cycle pulse -> value 3
    input  wire       btn_north,  // 1-cycle pulse -> value 2
    input  wire       btn_south,  // 1-cycle pulse -> value 1
    input  wire       btn_east,   // 1-cycle pulse -> value 0
    output reg  [7:0] leds,       // [7:4] sequence | [2:1] Strikes | [0] lose led
    output wire [3:0] score
);

    // ---------------------------------------------------------
    // Timing parameters (50 MHz)
    // ---------------------------------------------------------
    parameter LED_ON_TIME  = 32'd25_000_000;
    parameter LED_OFF_TIME = 32'd12_500_000;
    parameter FLASH_TIME   = 32'd50_000_000;
    parameter BLINK_HALF   = 32'd12_500_000;
    parameter MAX_ROUNDS   = 4'd10;

    // ---------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------
    localparam [3:0]
        IDLE       = 4'd0,
        SEQUENCE   = 4'd1,  
        SHOW       = 4'd2,  
        SHOW_PAUSE = 4'd3,  
        WAIT_INPUT = 4'd4,  
        ROUND_WIN  = 4'd5,  
        WIN        = 4'd6,  
        LOSE_ON    = 4'd7,  
        LOSE_OFF   = 4'd8;  

    reg [3:0] state;

    // ---------------------------------------------------------
    // Datapath Registers
    // ---------------------------------------------------------
    reg [1:0]  seq_mem [0:9];
    reg [3:0]  ronda_actual;
    reg [3:0]  show_idx;
    reg [3:0]  input_idx;
    reg [31:0] timer;
    reg [3:0]  blink_cnt;
    reg [4:0]  gen_delay;
    
    // NEW REGISTER: Strikes Counter
    reg [1:0]  strikes;

    // ---------------------------------------------------------
    // LFSR - Always running (Free-Running)
    // ---------------------------------------------------------
    wire [1:0] rand_val;
    
    lfsr_2bit u_lfsr (
        .clk     (clk),
        .reset   (rst),
        .en      (1'b1),
        .rand_val(rand_val)
    );

    // ---------------------------------------------------------
    // Button decoding (Combinational)
    // ---------------------------------------------------------
    wire       btn_any;
    wire [1:0] btn_code;

    assign btn_any  = btn_west | btn_north | btn_south | btn_east;
    assign btn_code = btn_west  ? 2'd3 :
                      btn_north ? 2'd2 :
                      btn_south ? 2'd1 : 2'd0;

    // ---------------------------------------------------------
    // LED Mask for Strikes
    // Ensures LD1 (leds[1]) and LD2 (leds[2]) stay lit
    // regardless of what is happening in the game.
    // ---------------------------------------------------------
    wire [7:0] strike_mask = {5'b00000, (strikes >= 2'd2), (strikes >= 2'd1), 1'b0};

    // =========================================================
    // SINGLE SYNCHRONOUS BLOCK
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            ronda_actual <= 4'd0;
            show_idx     <= 4'd0;
            input_idx    <= 4'd0;
            timer        <= 32'd0;
            blink_cnt    <= 4'd0;
            gen_delay    <= 5'd0;
            strikes      <= 2'd0;
            leds         <= 8'b0;
        end else begin
            case (state)
                
                // -------------------------------------------------
                IDLE: begin
                    leds         <= 8'b0;
                    ronda_actual <= 4'd0;
                    strikes      <= 2'd0; // Clears strikes when turning off the game
                    
                    if (sw0) begin
                        state    <= SEQUENCE;
                        show_idx <= 4'd0;
                    end
                end

                // -------------------------------------------------
                SEQUENCE: begin
                    leds <= strike_mask; // Keeps strikes lit instead of 8'b0
                    // Artificial Delay Buffering: Let the LFSR advance states before freezing a snapshot
                    if (gen_delay < 5'd15) begin
                        gen_delay <= gen_delay + 1'b1;	
                    end else begin
                        gen_delay <= 5'd0;
                        seq_mem[show_idx] <= rand_val;	// Insert fresh random step into the target memory sequence index
                        
						// Check if memory filling has caught up to the current playable round tier
                        if (show_idx == ronda_actual) begin
                            show_idx <= 4'd0;	// Initialize tracking engine for upcoming playback loop
                            timer    <= 32'd0;
                            state    <= SHOW;
                        end else begin
                            show_idx <= show_idx + 1'b1;	// Iterate internally until local sequence space is generated
                        end
                    end
                end

                // -------------------------------------------------
                SHOW: begin
                    case (seq_mem[show_idx])
                        // Combines the sequence LED bit with the strikes bits
                        2'd0: leds <= 8'b0001_0000 | strike_mask;
                        2'd1: leds <= 8'b0010_0000 | strike_mask;
                        2'd2: leds <= 8'b0100_0000 | strike_mask;
                        2'd3: leds <= 8'b1000_0000 | strike_mask;
                    endcase
                    
                    if (timer < LED_ON_TIME - 1) begin
                        timer <= timer + 1'b1;
                    end else begin
                        timer <= 32'd0;
                        state <= SHOW_PAUSE;
                    end
                end

                // -------------------------------------------------
                SHOW_PAUSE: begin
                    leds <= strike_mask;
                    
                    if (timer < LED_OFF_TIME - 1) begin
                        timer <= timer + 1'b1;
                    end else begin
                        timer <= 32'd0;
                        if (show_idx < ronda_actual) begin
                            show_idx <= show_idx + 1'b1;
                            state    <= SHOW;
                        end else begin
                            input_idx <= 4'd0;
                            state     <= WAIT_INPUT;
                        end
                    end
                end

                // -------------------------------------------------
                WAIT_INPUT: begin
                    leds <= strike_mask;	// Retain active strike metrics array display
                    
                    if (btn_any) begin
					// Structural Intercept: Verify if user input code perfectly reflects current memory index target
                        if (btn_code == seq_mem[input_idx]) begin
						// Successfully verified. Determine if user has finished verifying the full chain length
                            if (input_idx == ronda_actual) begin
                                timer <= 32'd0;
                                if (ronda_actual == MAX_ROUNDS - 1)
                                    state <= WIN;	// Perfect score achieved across all tiers
                                else
                                else
                                    state <= ROUND_WIN;	// Current tier verified successfully
                            end else begin
                                input_idx <= input_idx + 1'b1;	// Advance user to evaluate following step in chain
                            end
                        end else begin
                            // WRONG BUTTON
                            timer     <= 32'd0;
                            blink_cnt <= 4'd0;
                            state     <= LOSE_ON;
                        end
                    end
                end

                // -------------------------------------------------
                ROUND_WIN: begin
                    leds <= 8'b1111_0000 | strike_mask;
                    
                    if (timer < FLASH_TIME - 1) begin
                        timer <= timer + 1'b1;
                    end else begin
                        timer        <= 32'd0;
                        ronda_actual <= ronda_actual + 1'b1;
                        show_idx     <= 4'd0;
                        state        <= SEQUENCE;
                    end
                end

                // -------------------------------------------------
                WIN: begin
                    leds <= 8'b1111_1111;
                    if (!sw0) state <= IDLE;
                end

                // -------------------------------------------------
                LOSE_ON: begin
                    leds <= 8'b0000_0001 | strike_mask;
                    if (timer < BLINK_HALF - 1) begin
                        timer <= timer + 1'b1;
                    end else begin
                        timer <= 32'd0;
                        state <= LOSE_OFF;
                    end
                end

                // -------------------------------------------------
                LOSE_OFF: begin
                    leds <= strike_mask; // Turns off the error flash, keeps strikes
                    
                    if (timer < BLINK_HALF - 1) begin
                        timer <= timer + 1'b1;
                    end else begin
                        timer <= 32'd0;
                        
                        if (blink_cnt == 4'd2) begin
                            show_idx <= 4'd0;
                            
                            // --- STRIKES LOGIC (NEW) ---
                            if (sw1) begin
                                // EASY MODE: Active
                                if (strikes == 2'd2) begin
                                    // Failed for the 3rd time (already had 2 strikes) -> Game Over
                                    ronda_actual <= 4'd0;
                                    strikes      <= 2'd0;
                                end else begin
                                    // Has less than 3 strikes -> Gets 1 strike, keeps the round!
                                    strikes <= strikes + 1'b1;
                                end
                            end else begin
                                // HARD MODE: Failing gives an instant reset to Level 1
                                ronda_actual <= 4'd0;
                                strikes      <= 2'd0;
                            end
                            // ---------------------------------
                            
                            state <= SEQUENCE;
                        end else begin
                            blink_cnt <= blink_cnt + 1'b1;
                            state     <= LOSE_ON;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
assign score = ronda_actual + 1'b1;
endmodule