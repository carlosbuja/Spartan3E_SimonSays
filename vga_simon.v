`timescale 1ns / 1ps

module vga_simon (
    input  wire       clk_50mhz,  // 50MHz FPGA system clock
    input  wire       rst,        // Active-high reset
    input  wire [7:0] leds,       // Receives the 8 LEDs: [7:4] sequence | [2:1] strikes | [0] lose indicator
    input  wire       sw1,        // Switch 1: Easy Mode (EASY=1, HARD=0)
    input  wire [3:0] score,      // Receives the current round/score from the FSM
    
    // VGA Signals (1-bit per color channel for Spartan-3E)
    output reg        hsync,
    output reg        vsync,
    output reg        vga_r,
    output reg        vga_g,
    output reg        vga_b
);

    // ---------------------------------------------------------
    // 1. Clock Enable (Generates a 25MHz pixel clock tick)
    // We use a tick (enable signal) instead of a routed clock 
    // to prevent clock skew/jitter on the FPGA fabric.
    // ---------------------------------------------------------
    reg p_tick;
    always @(posedge clk_50mhz) begin
        if (rst) p_tick <= 1'b0;
        else     p_tick <= ~p_tick; // Toggles every cycle (50MHz -> 25MHz)
    end

    // ---------------------------------------------------------
    // 2. VGA Timing Parameters (640x480 @ 60Hz)
    // ---------------------------------------------------------
    localparam H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_BP = 48;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    localparam V_ACTIVE = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP; // 525

    reg [9:0] h_cnt; // Horizontal pixel counter
    reg [9:0] v_cnt; // Vertical line counter

    // Counter logic: Advances only when p_tick is high
    always @(posedge clk_50mhz) begin
        if (rst) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (p_tick) begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    // Sync pulse generation (Active Low for standard VGA)
    always @(posedge clk_50mhz) begin
        if (rst) begin
            hsync <= 1'b1;
            vsync <= 1'b1;
        end else if (p_tick) begin
            hsync <= ~((h_cnt >= (H_ACTIVE + H_FP)) && (h_cnt < (H_ACTIVE + H_FP + H_SYNC)));
            vsync <= ~((v_cnt >= (V_ACTIVE + V_FP)) && (v_cnt < (V_ACTIVE + V_FP + V_SYNC)));
        end
    end

    // Determines if we are currently drawing within the visible 640x480 area
    wire video_active = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
    wire [9:0] x = h_cnt;
    wire [9:0] y = v_cnt;

    // ---------------------------------------------------------
    // 3. Combinational Mini Font-ROM (8x8 Pixels)
    // ---------------------------------------------------------
    reg [4:0] char_to_draw; // Character ID to look up in the ROM
    reg [7:0] font_bits;    // The 8-bit row of the current character
    reg [2:0] bit_x, bit_y; // Internal X/Y coordinates inside the 8x8 character matrix

    // Text Window & Coordinate Selector (Scales 8x8 font up to 16x16 by dividing coordinates by 2)
    always @(*) begin
        char_to_draw = 5'd5; // Default to empty space (Space character ID)
        bit_y        = 3'd0;
        bit_x        = 3'd0;
        
        // Top Window: "ROUND: X" (X range: 256 to 384, Y range: 20 to 36)
        if (y >= 20 && y < 36 && x >= 256 && x < 384) begin
            bit_y = (y - 20) / 2;                 // Divide by 2 scales Y up 2x
            bit_x = 3'd7 - ((x - 256) % 16) / 2;  // Divide by 2 scales X up 2x, inverted for MSB-first reading
            
            case ((x - 256) / 16) // Determines which letter we are drawing based on the X block
                4'd0: char_to_draw = 5'd0;  // R
                4'd1: char_to_draw = 5'd1;  // O
                4'd2: char_to_draw = 5'd2;  // U
                4'd3: char_to_draw = 5'd3;  // N
                4'd4: char_to_draw = 5'd4;  // D
                4'd5: char_to_draw = 5'd22; // :
                4'd6: char_to_draw = 5'd5;  // Space
                4'd7: char_to_draw = (score >= 4'd10) ? 5'd15 : (5'd6 + score - 1'b1); // Dynamic digit (1-9, or 0 if >= 10)
            endcase
        end
        // Left Window: "EASY" or "HARD" (X range: 20 to 84, Y range: 232 to 248)
        else if (y >= 232 && y < 248 && x >= 20 && x < 84) begin
            bit_y = (y - 232) / 2;
            bit_x = 3'd7 - ((x - 20) % 16) / 2;
            
            if (sw1) begin // If Easy Mode is enabled
                case ((x - 20) / 16)
                    4'd0: char_to_draw = 5'd16; // E
                    4'd1: char_to_draw = 5'd17; // A
                    4'd2: char_to_draw = 5'd18; // S
                    4'd3: char_to_draw = 5'd19; // Y
                endcase
            end else begin // If Hard Mode is enabled
                case ((x - 20) / 16)
                    4'd0: char_to_draw = 5'd20; // H
                    4'd1: char_to_draw = 5'd17; // A
                    4'd2: char_to_draw = 5'd0;  // R
                    4'd3: char_to_draw = 5'd21; // D
                endcase
            end
        end
    end

    // Font Bitmap ROM (Hardcoded Hex values map out the pixels for each letter/number)
    always @(*) begin
        case (char_to_draw)
            // Letters
            5'd0:  case(bit_y) 0: font_bits = 8'hFC; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h7C; 4: font_bits = 8'h78; 5: font_bits = 8'h6C; 6: font_bits = 8'h66; 7: font_bits = 8'h66; endcase // R
            5'd1:  case(bit_y) 0: font_bits = 8'h3C; 1: font_bits = 8'h42; 2: font_bits = 8'h81; 3: font_bits = 8'h81; 4: font_bits = 8'h81; 5: font_bits = 8'h81; 6: font_bits = 8'h42; 7: font_bits = 8'h3C; endcase // O
            5'd2:  case(bit_y) 0: font_bits = 8'h81; 1: font_bits = 8'h81; 2: font_bits = 8'h81; 3: font_bits = 8'h81; 4: font_bits = 8'h81; 5: font_bits = 8'h81; 6: font_bits = 8'h42; 7: font_bits = 8'h3C; endcase // U
            5'd3:  case(bit_y) 0: font_bits = 8'h81; 1: font_bits = 8'hC1; 2: font_bits = 8'hA1; 3: font_bits = 8'h91; 4: font_bits = 8'h89; 5: font_bits = 8'h85; 6: font_bits = 8'h83; 7: font_bits = 8'h81; endcase // N
            5'd4:  case(bit_y) 0: font_bits = 8'hF8; 1: font_bits = 8'h64; 2: font_bits = 8'h62; 3: font_bits = 8'h61; 4: font_bits = 8'h61; 5: font_bits = 8'h62; 6: font_bits = 8'h64; 7: font_bits = 8'hF8; endcase // D
            5'd16: case(bit_y) 0: font_bits = 8'hFF; 1: font_bits = 8'h60; 2: font_bits = 8'h60; 3: font_bits = 8'hFC; 4: font_bits = 8'h60; 5: font_bits = 8'h60; 6: font_bits = 8'h60; 7: font_bits = 8'hFF; endcase // E
            5'd17: case(bit_y) 0: font_bits = 8'h18; 1: font_bits = 8'h24; 2: font_bits = 8'h42; 3: font_bits = 8'h42; 4: font_bits = 8'h7E; 5: font_bits = 8'h42; 6: font_bits = 8'h42; 7: font_bits = 8'h42; endcase // A
            5'd18: case(bit_y) 0: font_bits = 8'h3C; 1: font_bits = 8'h42; 2: font_bits = 8'h40; 3: font_bits = 8'h3C; 4: font_bits = 8'h02; 5: font_bits = 8'h02; 6: font_bits = 8'h42; 7: font_bits = 8'h3C; endcase // S
            5'd19: case(bit_y) 0: font_bits = 8'h66; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h3C; 4: font_bits = 8'h18; 5: font_bits = 8'h18; 6: font_bits = 8'h18; 7: font_bits = 8'h18; endcase // Y
            5'd20: case(bit_y) 0: font_bits = 8'h66; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h7E; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h66; 7: font_bits = 8'h66; endcase // H
            5'd21: case(bit_y) 0: font_bits = 8'hF8; 1: font_bits = 8'h64; 2: font_bits = 8'h62; 3: font_bits = 8'h61; 4: font_bits = 8'h61; 5: font_bits = 8'h62; 6: font_bits = 8'h64; 7: font_bits = 8'hF8; endcase // D
            5'd22: case(bit_y) 0: font_bits = 8'h00; 1: font_bits = 8'h18; 2: font_bits = 8'h18; 3: font_bits = 8'h00; 4: font_bits = 8'h00; 5: font_bits = 8'h18; 6: font_bits = 8'h18; 7: font_bits = 8'h00; endcase // :
            
            // Numbers 1 to 9 and 0
            5'd6:  case(bit_y) 0: font_bits = 8'h18; 1: font_bits = 8'h38; 2: font_bits = 8'h18; 3: font_bits = 8'h18; 4: font_bits = 8'h18; 5: font_bits = 8'h18; 6: font_bits = 8'h18; 7: font_bits = 8'h3C; endcase // 1
            5'd7:  case(bit_y) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h06; 3: font_bits = 8'h0C; 4: font_bits = 8'h30; 5: font_bits = 8'h60; 6: font_bits = 8'h66; 7: font_bits = 8'h7F; endcase // 2
            5'd8:  case(bit_y) 0: font_bits = 8'h7E; 1: font_bits = 8'h06; 2: font_bits = 8'h0C; 3: font_bits = 8'h3E; 4: font_bits = 8'h06; 5: font_bits = 8'h06; 6: font_bits = 8'h66; 7: font_bits = 8'h3C; endcase // 3
            5'd9:  case(bit_y) 0: font_bits = 8'h0C; 1: font_bits = 8'h1C; 2: font_bits = 8'h3C; 3: font_bits = 8'h6C; 4: font_bits = 8'hCC; 5: font_bits = 8'hFE; 6: font_bits = 8'h0C; 7: font_bits = 8'h0C; endcase // 4
            5'd10: case(bit_y) 0: font_bits = 8'h7F; 1: font_bits = 8'h60; 2: font_bits = 8'h60; 3: font_bits = 8'h7C; 4: font_bits = 8'h06; 5: font_bits = 8'h06; 6: font_bits = 8'h66; 7: font_bits = 8'h3C; endcase // 5
            5'd11: case(bit_y) 0: font_bits = 8'h3C; 1: font_bits = 8'h60; 2: font_bits = 8'h60; 3: font_bits = 8'h7C; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h66; 7: font_bits = 8'h3C; endcase // 6
            5'd12: case(bit_y) 0: font_bits = 8'h7F; 1: font_bits = 8'h46; 2: font_bits = 8'h0C; 3: font_bits = 8'h18; 4: font_bits = 8'h30; 5: font_bits = 8'h30; 6: font_bits = 8'h30; 7: font_bits = 8'h30; endcase // 7
            5'd13: case(bit_y) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h3C; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h66; 7: font_bits = 8'h3C; endcase // 8
            5'd14: case(bit_y) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h3E; 4: font_bits = 8'h06; 5: font_bits = 8'h06; 6: font_bits = 8'h06; 7: font_bits = 8'h3C; endcase // 9
            5'd15: case(bit_y) 0: font_bits = 8'h3E; 1: font_bits = 8'h66; 2: font_bits = 8'h6E; 3: font_bits = 8'h76; 4: font_bits = 8'h76; 5: font_bits = 8'h6E; 6: font_bits = 8'h66; 7: font_bits = 8'h3E; endcase // 0
            
            default: font_bits = 8'h00;
        endcase
    end

    // Extracts the single pixel value (1 = draw, 0 = background)
    wire text_pixel = font_bits[bit_x];

    // ---------------------------------------------------------
    // 4. Shape Geometry (Diamonds, Defeat Cross, and Strike Circles)
    // ---------------------------------------------------------
    
    // Fixed Centers and Dimensions for the main game layout
    localparam CX = 320, CY = 240, OFFSET = 80, SIZE = 70;

    // Absolute difference function (Used for Manhattan Distance calculation)
    function [9:0] abs_diff;
        input [9:0] a, b;
        begin
            abs_diff = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    // Hitboxes for the 4 Main Diamonds using Manhattan Distance: |x-cx| + |y-cy| < radius
    wire in_top    = (abs_diff(x, CX) + abs_diff(y, CY - OFFSET)) < SIZE; // North Diamond
    wire in_bottom = (abs_diff(x, CX) + abs_diff(y, CY + OFFSET)) < SIZE; // South Diamond
    wire in_left   = (abs_diff(x, CX - OFFSET) + abs_diff(y, CY)) < SIZE; // West Diamond
    wire in_right  = (abs_diff(x, CX + OFFSET) + abs_diff(y, CY)) < SIZE; // East Diamond

    // Map physical LEDs to logical shapes
    wire led_top    = leds[6];
    wire led_bottom = leds[5];
    wire led_left   = leds[7];
    wire led_right  = leds[4];

    // NEW GEOMETRY: Giant Red Cross in the Center
    // Creates a 160x160 bounding box. We calculate two diagonal lines (diff1, diff2)
    // and give them a thickness tolerance of +/- 12 pixels.
    wire signed [11:0] diff1 = (y - 240) - (x - 320);
    wire signed [11:0] diff2 = (y - 240) + (x - 320);
    wire in_cross_box = (x >= 240 && x <= 400 && y >= 160 && y <= 320);
    wire in_red_cross = in_cross_box && ((diff1 >= -12 && diff1 <= 12) || (diff2 >= -12 && diff2 <= 12));

    // NEW GEOMETRY: Two Strike Circles (Easy Mode)
    // Uses the Circle Equation: (x - cx)^2 + (y - cy)^2 < Radius^2
    // We use a radius of 15 pixels. 15^2 = 225.
    wire signed [10:0] dx_s1 = x - 580;
    wire signed [10:0] dy_s1 = y - 210;
    wire in_strike1 = (dx_s1*dx_s1 + dy_s1*dy_s1) < 225; // Top circle

    wire signed [10:0] dx_s2 = x - 580;
    wire signed [10:0] dy_s2 = y - 270;
    wire in_strike2 = (dx_s2*dx_s2 + dy_s2*dy_s2) < 225; // Bottom circle

    // ---------------------------------------------------------
    // 5. Synchronous Color Generation with Visual Priority
    // ---------------------------------------------------------
    always @(posedge clk_50mhz) begin
        if (rst) begin
            vga_r <= 1'b0; vga_g <= 1'b0; vga_b <= 1'b0;
        end else if (p_tick) begin
            if (!video_active) begin
                // Blanking interval (Must output black)
                vga_r <= 1'b0; vga_g <= 1'b0; vga_b <= 1'b0;
            end else begin
                
                // PRIORITY 1: Giant Defeat Cross (If LED[0] is active)
                if (leds[0] && in_red_cross) begin
                    vga_r <= 1'b1; vga_g <= 1'b0; vga_b <= 1'b0; // Pure Red
                end
                
                // PRIORITY 2: Text Characters (Round and Mode Text)
                else if (text_pixel) begin
                    vga_r <= 1'b1; vga_g <= 1'b1; vga_b <= 1'b1; // White Text
                end
                
                // PRIORITY 3: Easy Mode Strike Circles (LD1 and LD2)
                else if (sw1 && leds[1] && in_strike1) begin
                    vga_r <= 1'b1; vga_g <= 1'b0; vga_b <= 1'b0; // Strike 1 (Red)
                end
                else if (sw1 && leds[2] && in_strike2) begin
                    vga_r <= 1'b1; vga_g <= 1'b0; vga_b <= 1'b0; // Strike 2 (Red)
                end
                
                // PRIORITY 4: Base Game Diamonds
                else if (in_top) begin
                    vga_r <= led_top ? 1'b0 : 1'b1; 
                    vga_g <= 1'b1;                  // Green
                    vga_b <= led_top ? 1'b0 : 1'b1; 
                end 
                else if (in_bottom) begin
                    vga_r <= led_bottom ? 1'b0 : 1'b1;
                    vga_g <= led_bottom ? 1'b0 : 1'b1;
                    vga_b <= 1'b1;                  // Blue
                end 
                else if (in_left) begin
                    vga_r <= 1'b1; 
                    vga_g <= 1'b1;                  // Yellow (R+G)
                    vga_b <= led_left ? 1'b0 : 1'b1; 
                end 
                else if (in_right) begin
                    vga_r <= 1'b1;                  // Red
                    vga_g <= led_right ? 1'b0 : 1'b1;
                    vga_b <= led_right ? 1'b0 : 1'b1;
                end 
                
                // BACKGROUND: Absolute Black by default
                else begin
                    vga_r <= 1'b0; vga_g <= 1'b0; vga_b <= 1'b0;
                end
                
            end
        end
    end

endmodule