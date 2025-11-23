module instr_dcd (
    // peripheral clock signals
    input clk,
    input rst_n,
    // towards SPI slave interface signals
    input byte_sync,
    input[7:0] data_in,
    output[7:0] data_out,
    // register access signals
    output read,
    output write,
    output[5:0] addr,
    input[7:0] data_read,
    output[7:0] data_write
);

reg rw_reg;
reg hl_reg;
reg [5:0] addr_reg;
reg [7:0] data_out_reg;
reg [7:0] data_write_reg;
reg write_reg;
reg read_reg;

// 0 = SETUP, 1 = DATA
reg state;

assign data_out = data_out_reg;
assign data_write = data_write_reg;
assign addr = addr_reg;
assign read = read_reg;
assign write = write_reg;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= 1'b0;
        rw_reg <= 1'b0;
        hl_reg <= 1'b0;
        addr_reg <= 6'd0;
        data_out_reg <= 8'd0;
        data_write_reg <= 8'd0;
        write_reg <= 1'b0;
        read_reg <= 1'b0;
    end else begin
        write_reg  <= 1'b0;
        read_reg <= 1'b0;

        case(state)
            1'b0: begin
                if(byte_sync) begin
                    //decode instruction byte
                    rw_reg <= data_in[7];
                    hl_reg <= data_in[6];
                    addr_reg <= data_in[5:0];

                    if(data_in[7]) begin
                        //write operation
                        data_out_reg <= 8'd0;   //dummy during write setup
                    end else begin
                        //read operation
                        data_out_reg <= data_read;
                        //reading must be done by the time the data phase starts
                        read_reg <= 1'b1;
                    end

                    //movw to DATA
                    state <= 1'b1;
                end
            end

            1'b1: begin
                if (byte_sync) begin
                    if(rw_reg) begin
                        // write operation - receive data payload
                        data_write_reg <= data_in;
                        write_reg <= 1'b1;
                    end
                    //go back to SETUP phase
                    state <= 1'b0;
                end
            end
        endcase
    end
end

endmodule
