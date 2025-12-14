module regs (
    // peripheral clock signals
    input clk,
    input rst_n,
    // decoder facing signals
    input        read,
    input        write,
    input [5:0]  addr,
    output [7:0] data_read,
    input  [7:0] data_write,
    // counter programming signals
    input  [15:0] counter_val,
    output [15:0] period,
    output        en,
    output        count_reset,
    output        upnotdown,
    output [7:0]  prescale,
    // PWM signal programming values
    output        pwm_en,
    output [7:0]  functions,
    output [15:0] compare1,
    output [15:0] compare2
);

/*
    All registers that appear in this block should be similar to this. Please try to abide
    to sizes as specified in the architecture documentation.
*/

// registrele efective
reg [15:0] r_period;
reg        r_en;
reg [15:0] r_compare1;
reg [15:0] r_compare2;
reg [7:0]  r_prescale;
reg        r_upnotdown;
reg        r_pwm_en;
reg [7:0]  r_functions;

// COUNTER_RESET: pulse care durează 2 cicluri
reg [1:0]  r_count_reset_sh;
reg        r_count_reset;


// data_read e combinational
reg [7:0] r_data_read;

assign period      = r_period;
assign en          = r_en;
assign count_reset = r_count_reset;
assign upnotdown   = r_upnotdown;
assign prescale    = r_prescale;
assign pwm_en      = r_pwm_en;
assign functions   = r_functions;
assign compare1    = r_compare1;
assign compare2    = r_compare2;
assign data_read   = r_data_read;

// adrese (pe 6 biți)
localparam ADDR_PERIOD_L       = 6'h00;
localparam ADDR_PERIOD_H       = 6'h01;
localparam ADDR_COUNTER_EN     = 6'h02;
localparam ADDR_COMPARE1_L     = 6'h03;
localparam ADDR_COMPARE1_H     = 6'h04;
localparam ADDR_COMPARE2_L     = 6'h05;
localparam ADDR_COMPARE2_H     = 6'h06;
localparam ADDR_COUNTER_RESET  = 6'h07;
localparam ADDR_COUNTER_VAL_L  = 6'h08;
localparam ADDR_COUNTER_VAL_H  = 6'h09;
localparam ADDR_PRESCALE       = 6'h0A;
localparam ADDR_UPNOTDOWN      = 6'h0B;
localparam ADDR_PWM_EN         = 6'h0C;
localparam ADDR_FUNCTIONS      = 6'h0D;

// WRITE logic + COUNTER_RESET pulse
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_period         <= 16'h0000;
        r_en             <= 1'b0;
        r_upnotdown      <= 1'b0;       // să zicem default down
        r_prescale       <= 8'h00;      // prescale = 0 => div 1
        r_pwm_en         <= 1'b0;
        r_functions      <= 8'h00;
        r_compare1       <= 16'h0000;
        r_compare2       <= 16'h0000;

        r_count_reset_sh <= 2'b00;
        r_count_reset    <= 1'b0;
    end else begin
        // update countdown pentru COUNTER_RESET
        if (r_count_reset_sh != 2'b00) begin
            r_count_reset_sh <= r_count_reset_sh - 2'b01;
        end

        // derivăm semnalul de ieșire
        r_count_reset <= (r_count_reset_sh != 2'b00);

        // scrieri în registre
        if (write) begin
            case (addr)
                ADDR_PERIOD_L:      r_period[7:0]   <= data_write;
                ADDR_PERIOD_H:      r_period[15:8]  <= data_write;

                ADDR_COUNTER_EN:    r_en            <= data_write[0];

                ADDR_COMPARE1_L:    r_compare1[7:0]  <= data_write;
                ADDR_COMPARE1_H:    r_compare1[15:8] <= data_write;

                ADDR_COMPARE2_L:    r_compare2[7:0]  <= data_write;
                ADDR_COMPARE2_H:    r_compare2[15:8] <= data_write;

                ADDR_COUNTER_RESET: r_count_reset_sh <= 2'b11;   // două cicluri active

                ADDR_PRESCALE:      r_prescale      <= data_write;

                ADDR_UPNOTDOWN:     r_upnotdown     <= data_write[0];

                ADDR_PWM_EN:        r_pwm_en        <= data_write[0];

                ADDR_FUNCTIONS:     r_functions[1:0] <= data_write[1:0];
                // restul bitilor din FUNCTIONS îi ignorăm
                default: ; // adrese invalide -> ignorăm scrierea
            endcase
        end
    end
end

// READ logic (combinational)
always @(*) begin
    if (read) begin
        case (addr)
            ADDR_PERIOD_L:      r_data_read = r_period[7:0];
            ADDR_PERIOD_H:      r_data_read = r_period[15:8];

            ADDR_COUNTER_EN:    r_data_read = {7'b0, en};

            ADDR_COMPARE1_L:    r_data_read = r_compare1[7:0];
            ADDR_COMPARE1_H:    r_data_read = r_compare1[15:8];

            ADDR_COMPARE2_L:    r_data_read = r_compare2[7:0];
            ADDR_COMPARE2_H:    r_data_read = r_compare2[15:8];

            ADDR_COUNTER_RESET: r_data_read = 8'h00; // doar W, la citire dăm 0

            ADDR_COUNTER_VAL_L: r_data_read = counter_val[7:0];
            ADDR_COUNTER_VAL_H: r_data_read = counter_val[15:8];

            ADDR_PRESCALE:      r_data_read = r_prescale;

            ADDR_UPNOTDOWN:     r_data_read = {7'b0, r_upnotdown};

            ADDR_PWM_EN:        r_data_read = {7'b0, r_pwm_en};

            ADDR_FUNCTIONS:     r_data_read = r_functions;

            default:            r_data_read = 8'h00;
        endcase
    end else begin
        r_data_read = 8'h00;
    end
end

endmodule