module lcd_score (
    input  wire       clk,        // Reloj de 50 MHz
    input  wire [3:0] score,      // Número de la ronda (0 a 9)
    
    // Pines hacia el LCD de la Spartan 3E
    output reg        lcd_rs,
    output wire       lcd_rw,
    output reg        lcd_e,
    output reg  [3:0] sf_d,       // Datos (compartidos con StrataFlash)
    
    // Única señal requerida para desactivar la memoria StrataFlash (UG230)
    output wire       sf_ce0
);

    // 1. Bloquear la Flash poniendo su Chip Enable en alto (Standby)
    assign sf_ce0 = 1'b1;
    assign lcd_rw = 1'b0; // Siempre escribimos en la pantalla (Read/Write = 0)

    // 2. Registros de la Máquina de Estados
    reg [23:0] delay     = 0;
    reg [4:0]  state     = 0;
    reg [3:0]  step      = 0;
    reg [3:0]  char_idx  = 0;
    
    reg [8:0] current_tx = 0;  // Bit 8 es RS, Bits 7:0 son el dato/comando
    reg [3:0] n_high     = 0;
    reg [3:0] n_low      = 0;

    // 3. Memoria ROM con el texto "Ronda: X"
    always @(*) begin
        case(char_idx)
            // Comandos de configuración
            4'd0:  current_tx = 9'b0_00101000; // Function Set: 4-bit, 2 líneas
            4'd1:  current_tx = 9'b0_00000110; // Entry Mode: Incrementar cursor
            4'd2:  current_tx = 9'b0_00001100; // Display ON: Ocultar cursor
            4'd3:  current_tx = 9'b0_00000001; // Clear Display
            4'd4:  current_tx = 9'b0_10000000; // Set DDRAM (Mover cursor al inicio)
            // Caracteres ASCII
            4'd5:  current_tx = 9'b1_01010010; // 'R'
            4'd6:  current_tx = 9'b1_01101111; // 'o'
            4'd7:  current_tx = 9'b1_01101110; // 'n'
            4'd8:  current_tx = 9'b1_01100100; // 'd'
            4'd9:  current_tx = 9'b1_01100001; // 'a'
            4'd10: current_tx = 9'b1_00111010; // ':'
            4'd11: current_tx = 9'b1_00100000; // ' '
            4'd12: current_tx = {1'b1, 4'b0011, score}; // 0x30 + score = ASCII del 0 al 9
            default: current_tx = 9'b1_00100000;
        endcase
    end

    // Estados de la máquina
    localparam POWER_ON      = 0, WAKE_UP_SEQ   = 1;
    localparam WAKE_UP_PULSE = 2, WAKE_UP_WAIT  = 3;
    localparam TX_PREPARE    = 4, TX_HIGH_SETUP = 5;
    localparam TX_HIGH_PULSE = 6, TX_LOW_SETUP  = 7;
    localparam TX_LOW_PULSE  = 8, TX_WAIT       = 9;

    always @(posedge clk) begin
        case (state)
            // -- FASE 1: Secuencia de inicialización de 4-bits --
            POWER_ON: begin
                lcd_e <= 0; lcd_rs <= 0;
                if (delay < 750000) delay <= delay + 1; // Esperar 15 ms al encender
                else begin delay <= 0; state <= WAKE_UP_SEQ; step <= 0; end
            end
            
            WAKE_UP_SEQ: begin
                if      (step == 0) sf_d <= 4'h3;
                else if (step == 1) sf_d <= 4'h3;
                else if (step == 2) sf_d <= 4'h3;
                else if (step == 3) sf_d <= 4'h2; 
                state <= WAKE_UP_PULSE; delay <= 0;
            end
            
            WAKE_UP_PULSE: begin
                if (delay < 12) begin lcd_e <= 1; delay <= delay + 1; end
                else begin lcd_e <= 0; delay <= 0; state <= WAKE_UP_WAIT; end
            end
            
            WAKE_UP_WAIT: begin
                if (step == 0 && delay < 250000) delay <= delay + 1;       // 5 ms
                else if (step == 1 && delay < 5000) delay <= delay + 1;    // 100 us
                else if ((step == 2 || step == 3) && delay < 2000) delay <= delay + 1; // 40 us
                else begin
                    delay <= 0;
                    if (step < 3) begin step <= step + 1; state <= WAKE_UP_SEQ; end 
                    else begin state <= TX_PREPARE; char_idx <= 0; end
                end
            end

            // -- FASE 2: Envío de Comandos y Texto --
            TX_PREPARE: begin
                lcd_rs <= current_tx[8];
                n_high <= current_tx[7:4];
                n_low  <= current_tx[3:0];
                state  <= TX_HIGH_SETUP; delay <= 0;
            end
            
            TX_HIGH_SETUP: begin
                sf_d <= n_high;
                if (delay < 2) delay <= delay + 1;
                else begin delay <= 0; state <= TX_HIGH_PULSE; end
            end
            
            TX_HIGH_PULSE: begin
                if (delay < 12) begin lcd_e <= 1; delay <= delay + 1; end
                else begin lcd_e <= 0; delay <= 0; state <= TX_LOW_SETUP; end
            end

            TX_LOW_SETUP: begin
                sf_d <= n_low;
                if (delay < 50) delay <= delay + 1; 
                else begin delay <= 0; state <= TX_LOW_PULSE; end
            end

            TX_LOW_PULSE: begin
                if (delay < 12) begin lcd_e <= 1; delay <= delay + 1; end
                else begin lcd_e <= 0; delay <= 0; state <= TX_WAIT; end
            end

            TX_WAIT: begin
                if (char_idx == 3) begin // Comando Clear Display (2ms)
                    if (delay < 100000) delay <= delay + 1; 
                    else begin delay <= 0; char_idx <= char_idx + 1; state <= TX_PREPARE; end
                end
                else if (char_idx == 12) begin // Fin de línea, refrescar tras 50ms
                    if (delay < 2500000) delay <= delay + 1; 
                    else begin delay <= 0; char_idx <= 4; state <= TX_PREPARE; end 
                end
                else begin // Letras y comandos comunes (40us)
                    if (delay < 2000) delay <= delay + 1; 
                    else begin delay <= 0; char_idx <= char_idx + 1; state <= TX_PREPARE; end
                end
            end
            
            default: state <= POWER_ON;
        endcase
    end
endmodule