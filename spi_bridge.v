module spi_bridge (
    // peripheral clock signals
    input clk,
    input rst_n,
    // SPI master facing signals
    input sclk,
    input cs_n,
    input mosi,
    output miso,
    // internal facing 
    output byte_sync,
    output[7:0] data_in,
    input[7:0] data_out
);

reg [1:0] sclk_sync, cs_sync;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sclk_sync <= 2'b00;
        cs_sync <= 2'b11;
    end else begin
        sclk_sync <= {sclk_sync[0], sclk};
        cs_sync <= {cs_sync[0], cs_n};
    end
end

wire sclk_rising = (sclk_sync == 2'b01);
wire sclk_falling = (sclk_sync == 2'b10);
wire cs_active = ~cs_sync[1];

// Shift Registers and Counters
reg [2:0] byte_cnt;
reg [7:0] shift_in, shift_out;
reg miso_reg;
assign miso = miso_reg;
assign data_in = shift_in;

// SPI Logic
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        byte_cnt <= 3'd0;
        shift_in <= 8'd0;
        shift_out <= 8'd0;
        miso_reg <= 1'b0;
    end else begin
        if (!cs_active) begin
            byte_cnt <= 3'd0;
            shift_out <= data_out;
            miso_reg <= data_out[7];
        end else begin
            //reading data
            if(sclk_rising) begin
                shift_in <= {shift_in[6:0], mosi};
                byte_cnt <= byte_cnt + 1;    
            end

            //sending data
            if(sclk_falling) begin
                shift_out <= {shift_out[6:0], 1'b0};
                miso_reg <= shift_out[6];
            end

            //reload TX register between bytes
            if (sclk_rising && (byte_cnt == 3'd7)) begin
                shift_out <= data_out;  // load next TX byte
                miso_reg  <= data_out[7];
            end
        end
    end
end

// Generate byte_sync pulse when a full byte is received
reg byte_sync_reg;
assign byte_sync = byte_sync_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        byte_sync_reg <= 1'b0;
    else
        byte_sync_reg <= cs_active && sclk_rising && (byte_cnt == 3'd7);
end

endmodule
